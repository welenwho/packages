import { strToBool, strToInt } from 'sbproxy';

function ports(value) {
	return type(value) === 'array' && length(value) ? map(value, (port) => int(port)) : null;
}

// Shared with custom routing. Keep a default rule, not an OR of every field:
// sing-box combines destination selectors within their category and applies
// network, source and port constraints using its normal rule semantics.
export function renderRouteMatch(cfg, rule_sets) {
	return {
		ip_version: strToInt(cfg.ip_version), protocol: cfg.protocol, client: cfg.client,
		network: cfg.network, domain: cfg.domain, domain_suffix: cfg.domain_suffix,
		domain_keyword: cfg.domain_keyword, domain_regex: cfg.domain_regex,
		source_ip_cidr: cfg.source_ip_cidr, source_ip_is_private: strToBool(cfg.source_ip_is_private),
		ip_cidr: cfg.ip_cidr, ip_is_private: strToBool(cfg.ip_is_private),
		source_port: ports(cfg.source_port), source_port_range: cfg.source_port_range,
		port: ports(cfg.port), port_range: cfg.port_range,
		process_name: cfg.process_name, process_path: cfg.process_path,
		process_path_regex: cfg.process_path_regex, user: cfg.user,
		rule_set: rule_sets, rule_set_ip_cidr_match_source: strToBool(cfg.rule_set_ip_cidr_match_source),
		invert: strToBool(cfg.invert)
	};
}
