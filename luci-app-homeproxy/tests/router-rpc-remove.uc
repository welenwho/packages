#!/usr/bin/ucode

'use strict';

const plugin = loadfile(ARGV[0])();
const handler = plugin['luci.homeproxy'].adaptive_remove.call;
const result = handler({ args: { target: '1.1.1.1' } });

if (!result?.result || !result?.removed)
	die(sprintf('adaptive_remove failed: %.J\n', result));

printf('adaptive_remove test passed: %.J\n', result);
