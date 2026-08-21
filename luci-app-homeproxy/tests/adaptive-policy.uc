#!/usr/bin/ucode

'use strict';

import { adaptiveEntryMatchesPolicy, resolveAdaptivePolicy } from 'homeproxy';

function cursor(values) {
	return {
		get: (config, section, option) => values[`${config}.${section}.${option}`]
	};
}

function expectPolicy(label, values, expected) {
	const policy = resolveAdaptivePolicy(cursor(values), 'homeproxy', 'homeproxy-adaptive');
	for (let key, value in expected)
		if (policy[key] !== value)
			die(sprintf('%s policy %s mismatch: %.J\n', label, key, policy));
	return policy;
}

const direct = expectPolicy('custom direct default', {
	'homeproxy.config.routing_mode': 'custom',
	'homeproxy.routing.default_outbound': 'direct-out',
	'homeproxy-adaptive.main.enabled': '1',
	'homeproxy-adaptive.main.outbound': 'proxy-route'
}, {
	enabled: true,
	baseline_kind: 'direct',
	target_kind: 'proxy',
	id: 'custom|direct|routing:proxy-route'
});

const proxy = expectPolicy('custom proxy default', {
	'homeproxy.config.routing_mode': 'custom',
	'homeproxy.routing.default_outbound': 'proxy-route',
	'homeproxy-adaptive.main.enabled': '1'
}, {
	enabled: true,
	baseline_kind: 'proxy',
	target_kind: 'direct',
	id: 'custom|routing:proxy-route|direct'
});

expectPolicy('mainland proxy default', {
	'homeproxy.config.routing_mode': 'bypass_mainland_china',
	'homeproxy.config.main_node': 'main-node',
	'homeproxy-adaptive.main.enabled': '1'
}, {
	enabled: true,
	baseline_kind: 'proxy',
	target_kind: 'direct',
	id: 'bypass_mainland_china|main:main-node|direct'
});

expectPolicy('global requires opt-in', {
	'homeproxy.config.routing_mode': 'global',
	'homeproxy.config.main_node': 'main-node',
	'homeproxy-adaptive.main.enabled': '1'
}, { enabled: false, mode_allowed: false });

expectPolicy('global explicit opt-in', {
	'homeproxy.config.routing_mode': 'global',
	'homeproxy.config.main_node': 'main-node',
	'homeproxy-adaptive.main.enabled': '1',
	'homeproxy-adaptive.main.allow_global': '1'
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
