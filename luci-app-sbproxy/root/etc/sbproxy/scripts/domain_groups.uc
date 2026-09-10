import { validation } from 'sbproxy';
import { renderRouteMatch } from 'route_match';

function list(value) {
	return type(value) === 'array' ? [...value] : (value ? [value] : []);
}

function cleanList(value) {
	return uniq(filter(map(list(value), (v) => trim(v)), (v) => length(v)));
}

export function normalizeGroupDomains(value) {
	const content = type(value) === 'array' ? join('\n', value) : (value || '');
	let result = [];
	for (let line in split(content, /[\r\n]+/)) {
		line = trim(line);
		if (!line || substr(line, 0, 1) === '#') continue;
		const domain = lc(replace(line, /^\.+|\.+$/g, ''));
		if (!domain || !validation('hostname', domain)) die('Invalid diversion domain: ' + line);
		push(result, domain);
	}
	return uniq(result);
}

export function buildGroupMatch(section, uci, config) {
	const legacy = normalizeGroupDomains(section.domains);
	let cfg = { ...section };
	cfg.domain = cleanList(section.domain);
	cfg.domain_suffix = uniq([...filter(legacy, (d) => index(d, '.') !== -1), ...normalizeGroupDomains(section.domain_suffix)]);
	cfg.domain_keyword = uniq([...filter(legacy, (d) => index(d, '.') === -1), ...cleanList(section.domain_keyword)]);
	cfg.domain_regex = cleanList(section.domain_regex);
	for (let domain in cfg.domain)
		if (!validation('hostname', domain)) die('Invalid exact diversion domain: ' + domain);
	for (let field in ['ip_cidr', 'source_ip_cidr']) {
		cfg[field] = cleanList(section[field]);
		for (let value in cfg[field])
			if (!validation('or(cidr,ipaddr)', value)) die('Invalid diversion address: ' + value);
		cfg[field] = map(cfg[field], (value) => index(value, '/') >= 0 ? value : value + (index(value, ':') >= 0 ? '/128' : '/32'));
	}
	for (let field in ['port', 'source_port']) {
		cfg[field] = cleanList(section[field]);
		for (let value in cfg[field])
			if (!match(value, /^[0-9]+$/) || int(value) < 1 || int(value) > 65535) die('Invalid diversion port: ' + value);
	}
	for (let field in ['port_range', 'source_port_range']) {
		cfg[field] = cleanList(section[field]);
		for (let value in cfg[field]) {
			const range = match(value, /^([0-9]*):([0-9]*)$/);
			if (!range || (!range[1] && !range[2])) die('Invalid diversion port range: ' + value);
			const first = range[1] ? int(range[1]) : 1, last = range[2] ? int(range[2]) : 65535;
			if (first < 1 || last > 65535 || first > last) die('Invalid diversion port range: ' + value);
		}
	}
	if (cfg.network && !(cfg.network in ['tcp', 'udp'])) die('Invalid diversion network');
	if (cfg.ip_version && !(cfg.ip_version in ['4', '6'])) die('Invalid diversion IP version');
	const refs = cleanList(section.rule_set);
	let resolved = [], user_refs = [];
	for (let id in refs) {
		if (id in ['builtin:geoip-cn', 'builtin:geosite-cn']) push(resolved, substr(id, 8));
		else {
			if (uci.get(config, id) !== 'ruleset' || uci.get(config, id, 'enabled') !== '1')
				die('Diversion rule set is missing or disabled: ' + id);
			push(resolved, 'cfg-' + id + '-rule');
			push(user_refs, id);
		}
	}
	const rendered = renderRouteMatch(cfg, length(resolved) ? resolved : null);
	let criteria = {};
	for (let key, value in rendered)
		if (value !== null && value !== false && value !== '' && (type(value) !== 'array' || length(value))) criteria[key] = value;
	if (!length(resolved)) delete criteria.rule_set_ip_cidr_match_source;
	// An empty group (or invert-only group) must never become a catch-all rule.
	const populated = filter(keys(criteria), (k) => !(k in ['invert', 'rule_set_ip_cidr_match_source']));
	if (!length(populated)) return null;
	const domain_fields = ['domain', 'domain_suffix', 'domain_keyword', 'domain_regex'];
	const dns_safe = length(filter(populated, (k) => index(domain_fields, k) < 0)) === 0;
	return { match: criteria, rule_set_refs: user_refs, dns_match: dns_safe ? criteria : null,
		suffixes: cfg.domain_suffix, keywords: cfg.domain_keyword,
		needs_sniff: !dns_safe || length(cfg.domain_keyword) > 0 || length(cfg.domain_regex) > 0 || !!criteria.invert };
}


export function loadDomainGroups(uci, config, mode) {
	let groups = [];
	if (mode !== 'bypass_mainland_china') return groups;
	uci.foreach(config, 'domain_route', (section) => {
		if (section.enabled !== '1') return;
		const criteria = buildGroupMatch(section, uci, config);
		if (!criteria) return;
		let node = section.node || '_main';
		if (!(node in ['_main', '_direct']) && uci.get(config, node) !== 'node') {
			if (section.missing_node_action === 'reject') {
				warn('Rejecting unavailable diversion group: ' + section['.name'] + '\n');
				node = '_reject';
			} else {
				if (section.missing_node_action !== 'main')
					die('Diversion group selects an unavailable node: ' + (section.label || section['.name']));
				warn('Diversion group explicitly falls back to main node: ' + section['.name'] + '\n');
				node = '_main';
			}
		}
		push(groups, { id: section['.name'], label: section.label || section['.name'], node,
			...criteria });
	});
	return groups;
}

// Overlaps are legal: first group wins. Return a warning, not a startup error.
export function domainGroupOverlap(groups) {
	let seen = {}, children = {}, keywords = [];
	for (let group in groups) {
		for (let d in group.suffixes) {
			if (children[d] && children[d] !== group.id) return d;
			const parts = split(d, '.');
			for (let i = 0; i < length(parts); i++) {
				const parent = join('.', slice(parts, i));
				if (seen[parent] && seen[parent] !== group.id) return d;
				children[parent] = group.id;
			}
			for (let k in keywords)
				if (k.id !== group.id && index(d, k.value) !== -1) return d;
			seen[d] = group.id;
		}
		for (let d in group.keywords) {
			for (let suffix, owner in seen)
				if (owner !== group.id && index(suffix, d) !== -1) return d;
			for (let k in keywords)
				if (k.id !== group.id && (index(d, k.value) !== -1 || index(k.value, d) !== -1)) return d;
			push(keywords, { id: group.id, value: d });
		}
	}
	return null;
}
