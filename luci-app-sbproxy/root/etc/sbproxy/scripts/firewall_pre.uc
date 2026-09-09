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

const derp_enabled = uci.get(cfgname, 'tailscale', 'enabled') === '1' &&
      uci.get(cfgname, 'tailscale', 'derp_server_enabled') === '1';
const derp_firewall = uci.get(cfgname, 'tailscale', 'derp_firewall') !== '0';
const derp_port = uci.get(cfgname, 'tailscale', 'derp_port') || '8443';
const derp_stun_enabled = uci.get(cfgname, 'tailscale', 'derp_stun_enabled') !== '0';
const derp_stun_port = uci.get(cfgname, 'tailscale', 'derp_stun_port') || '3478';
if (derp_enabled && derp_firewall && match(derp_port, /^[0-9]+$/) &&
    int(derp_port) >= 1 && int(derp_port) <= 65535)
	push(input, `tcp dport ${derp_port} counter accept comment "!${cfgname}: accept DERP HTTPS"`);
if (derp_enabled && derp_firewall && derp_stun_enabled &&
    match(derp_stun_port, /^[0-9]+$/) && int(derp_stun_port) >= 1 &&
    int(derp_stun_port) <= 65535)
	push(input, `udp dport ${derp_stun_port} counter accept comment "!${cfgname}: accept DERP STUN"`);
if (derp_enabled && derp_firewall &&
    uci.get(cfgname, 'tailscale', 'derp_tls_mode') === 'acme') {
	const acme_http_port = uci.get(cfgname, 'tailscale', 'derp_acme_http_port') || '80';
	const acme_tls_port = uci.get(cfgname, 'tailscale', 'derp_acme_tls_port') || '443';
	if (match(acme_http_port, /^[0-9]+$/) && int(acme_http_port) >= 1 &&
	    int(acme_http_port) <= 65535)
		push(input, `tcp dport ${acme_http_port} counter accept comment "!${cfgname}: accept DERP ACME HTTP"`);
	if (acme_tls_port !== derp_port && match(acme_tls_port, /^[0-9]+$/) &&
	    int(acme_tls_port) >= 1 && int(acme_tls_port) <= 65535)
		push(input, `tcp dport ${acme_tls_port} counter accept comment "!${cfgname}: accept DERP ACME TLS"`);
}

const input_file = RUN_DIR + '/fw4_input.nft';

if (writefile(input_file, length(input) ? join('\n', input) + '\n' : '') === null)
	exit(1);
