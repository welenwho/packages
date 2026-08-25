#!/usr/bin/ucode

'use strict';

import {
	adaptiveEntryTarget, normalizeAdaptiveTarget, renderAdaptiveRules
} from 'sbproxy';

function expectTarget(value, expected_type, expected_value) {
	const target = normalizeAdaptiveTarget(value);
	if (target?.type !== expected_type || target?.value !== expected_value)
		die(sprintf('unexpected target normalization for %s: %.J\n', value, target));
}

function expectRejected(value) {
	if (normalizeAdaptiveTarget(value))
		die(sprintf('private or invalid target accepted: %s\n', value));
}

expectTarget('Example.COM.', 'domain', 'example.com');
expectTarget('1.1.1.1', 'ipv4', '1.1.1.1');
expectTarget('[2606:4700:4700::1111]', 'ipv6', '2606:4700:4700::1111');
expectTarget('2606:4700:4700:0:0:0:0:1111', 'ipv6', '2606:4700:4700::1111');

for (let value in [
	'192.168.8.1', '10.0.0.1', '100.64.0.1', '127.0.0.1',
	'169.254.1.1', '198.18.0.1', '203.0.113.1', 'fc00::1',
	'fe80::1', 'ff02::1', '2001:db8::1', '2001:0db8::1',
	'[2606:4700:4700::1111', '2606:4700:4700::1111]', 'not-a-target'
])
	expectRejected(value);

const legacy = adaptiveEntryTarget({ domain: 'Legacy.Example' });
if (legacy?.key !== 'domain:legacy.example')
	die(sprintf('legacy domain migration failed: %.J\n', legacy));

const rules = renderAdaptiveRules([
	{ domain: 'legacy.example' },
	{ target: '1.1.1.1', target_type: 'ipv4' },
	{ target: '2606:4700:4700::1111', target_type: 'ipv6' },
	{ target: '192.168.8.1', target_type: 'ipv4' }
], true);

if (rules.rules?.[0]?.domain?.[0] !== 'legacy.example' ||
	 rules.rules?.[1]?.ip_cidr?.[0] !== '1.1.1.1/32' ||
	 rules.rules?.[1]?.ip_cidr?.[1] !== '2606:4700:4700::1111/128')
	die(sprintf('adaptive rule rendering failed: %.J\n', rules));

printf('Adaptive target test passed: public domain/IPv4/IPv6 rules generated\n');
