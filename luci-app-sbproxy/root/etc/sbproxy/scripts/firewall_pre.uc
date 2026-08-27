#!/usr/bin/ucode

'use strict';

import { writefile } from 'fs';
import { cursor } from 'uci';
import { RUN_DIR } from 'sbproxy';

const cfgname = 'sbproxy';
const uci = cursor();
uci.load(cfgname);

let input = [];
if (getenv('SBPROXY_SERVER_READY') === '1')
	uci.foreach(cfgname, 'server', (server) => {
		if (server.enabled !== '1' || server.firewall !== '1')
			return;

		const network = server.network || '{ tcp, udp }';
		push(input, `meta l4proto ${network} th dport ${server.port} counter accept comment "!${cfgname}: accept server ${server['.name']}"`);
	});

/* The dashboard API is intended for the router LAN. Do not expose it to
 * Tailnet peers by default; users who need remote dashboard access can set an
 * API secret and explicitly enable dashboard_allow_tailscale. */
const dashboard_enabled = uci.get(cfgname, 'config', 'dashboard_enabled') === '1';
const dashboard_port = uci.get(cfgname, 'config', 'dashboard_port');
const dashboard_allow_tailscale = uci.get(cfgname, 'config', 'dashboard_allow_tailscale') === '1';
const dashboard_tailscale_interface = uci.get(cfgname, 'tailscale', 'system_interface_name') || 'tailscale0';
if (dashboard_enabled && !dashboard_allow_tailscale && dashboard_port && match(dashboard_port, /^[0-9]+$/) &&
	int(dashboard_port) >= 1 && int(dashboard_port) <= 65535 &&
	match(dashboard_tailscale_interface, /^[A-Za-z0-9_.-]+$/))
	push(input, `iifname "${dashboard_tailscale_interface}" tcp dport ${dashboard_port} counter drop comment "!${cfgname}: keep dashboard off Tailnet"`);

const forward_file = RUN_DIR + '/fw4_forward.nft';
const input_file = RUN_DIR + '/fw4_input.nft';

if (writefile(forward_file, '') === null ||
    writefile(input_file, length(input) ? join('\n', input) + '\n' : '') === null)
	exit(1);
