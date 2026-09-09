#!/usr/bin/ucode
import { cursor } from 'uci';
import { connect } from 'ubus';
import { readfile } from 'fs';
import { ingressEnabled, ingressNft } from 'ingress';

const uci = getenv('SBPROXY_UCI_CONFIG_DIR') ? cursor(getenv('SBPROXY_UCI_CONFIG_DIR')) : cursor();
const control = uci.get_all('sbproxy', 'control') || {};
if (!ingressEnabled(control))
	exit(0);
let wireless = {};
if (length(control.ingress_bypass_wifi || [])) {
	const fixture = getenv('SBPROXY_INGRESS_WIRELESS_STATUS');
	wireless = fixture ? json(readfile(fixture)) : connect()?.call('network.wireless', 'status', {});
	if (type(wireless) !== 'object')
		die('Unable to resolve wireless ingress devices');
}
print(ingressNft(control, wireless, uci.get('sbproxy', 'infra', 'ingress_dns_port')));
