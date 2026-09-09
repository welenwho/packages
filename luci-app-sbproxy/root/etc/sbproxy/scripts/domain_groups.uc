import { validation } from 'sbproxy';

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

export function loadDomainGroups(uci, config, mode) {
	let groups = [];
	if (mode !== 'bypass_mainland_china') return groups;
	uci.foreach(config, 'domain_route', (section) => {
		if (section.enabled !== '1') return;
		const domains = normalizeGroupDomains(section.domains);
		if (!length(domains)) return;
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
			suffixes: filter(domains, (d) => index(d, '.') !== -1),
			keywords: filter(domains, (d) => index(d, '.') === -1) });
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
