#!/usr/bin/ucode

'use strict';

import { adaptiveEntryMatchesPolicy, resolveAdaptivePolicy } from 'sbproxy';

function cursor(values) {
	return {
		get: (config, section, option) => values[`${config}.${section}.${option}`]
	};
}

function expectPolicy(label, values, expected) {
	const policy = resolveAdaptivePolicy(cursor(values), 'sbproxy', 'sbproxy-adaptive');
	for (let key, value in expected)
		if (policy[key] !== value)
			die(sprintf('%s policy %s mismatch: %.J\n', label, key, policy));
	return policy;
}

const direct = expectPolicy('custom direct default', {
	'sbproxy.config.routing_mode': 'custom',
	'sbproxy.routing.default_outbound': 'direct-out',
	'sbproxy-adaptive.main.enabled': '1',
	'sbproxy-adaptive.main.outbound': 'proxy-route'
}, {
	enabled: true,
	baseline_kind: 'direct',
	target_kind: 'proxy',
	id: 'custom|direct|routing:proxy-route'
});

const proxy = expectPolicy('custom proxy default', {
	'sbproxy.config.routing_mode': 'custom',
	'sbproxy.routing.default_outbound': 'proxy-route',
	'sbproxy-adaptive.main.enabled': '1'
}, {
	enabled: true,
	baseline_kind: 'proxy',
	target_kind: 'direct',
	id: 'custom|routing:proxy-route|direct'
});

expectPolicy('mainland proxy default', {
	'sbproxy.config.routing_mode': 'bypass_mainland_china',
	'sbproxy.config.main_node': 'main-node',
	'sbproxy-adaptive.main.enabled': '1'
}, {
	enabled: true,
	baseline_kind: 'proxy',
	target_kind: 'direct',
	id: 'bypass_mainland_china|main:main-node|direct'
});

expectPolicy('global requires opt-in', {
	'sbproxy.config.routing_mode': 'global',
	'sbproxy.config.main_node': 'main-node',
	'sbproxy-adaptive.main.enabled': '1'
}, { enabled: false, mode_allowed: false });

expectPolicy('global explicit opt-in', {
	'sbproxy.config.routing_mode': 'global',
	'sbproxy.config.main_node': 'main-node',
	'sbproxy-adaptive.main.enabled': '1',
	'sbproxy-adaptive.main.allow_global': '1'
}, {
	enabled: true,
	baseline_kind: 'proxy',
	target_kind: 'direct',
	id: 'global|main:main-node|direct'
});

if (!adaptiveEntryMatchesPolicy({ target: 'legacy.example' }, direct) ||
	 adaptiveEntryMatchesPolicy({ target: 'legacy.example' }, proxy) ||
	 !adaptiveEntryMatchesPolicy({ policy_id: proxy.id }, proxy))
	die('adaptive policy state isolation failed\n');

printf('Adaptive policy test passed: modes, directions, global opt-in, and state isolation resolved\n');
