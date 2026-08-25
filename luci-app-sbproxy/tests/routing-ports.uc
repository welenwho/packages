#!/usr/bin/ucode

'use strict';

import { resolveRoutingPorts } from 'sbproxy';

function expectPorts(label, actual, expected) {
	if (join(',', actual) !== join(',', expected))
		die(sprintf('%s routing ports mismatch: %.J\n', label, actual));
}

expectPorts('all', resolveRoutingPorts('', '80,443,8080', [ '6002' ]), []);
expectPorts(
	'common plus extras',
	resolveRoutingPorts('common', '80,443,8080', [ '6002', '10000-10100', '8080' ]),
	[ '80', '443', '8080', '6002', '10000-10100' ]
);
expectPorts(
	'custom replacement',
	resolveRoutingPorts('80,443,8443-8444', '53,80,443,8080', [ '6002' ]),
	[ '80', '443', '8443-8444' ]
);

printf('Routing port tests passed: all, common plus extras, and custom replacement resolved\n');
