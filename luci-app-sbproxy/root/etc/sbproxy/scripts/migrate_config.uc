#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2025 ImmortalWrt.org
 */

'use strict';

import { cursor } from 'uci';
import {
	isEmpty, normalizeList, reconcileUrltestNodes, synchronizeNodeLabels
} from 'sbproxy';

const uciConfigDir = getenv('SBPROXY_UCI_CONFIG_DIR');
const uci = uciConfigDir ? cursor(uciConfigDir) : cursor();
const uciconfig = 'sbproxy';
uci.load(uciconfig);

const stockWanProxyIPv4 = [
	'91.105.192.0/23', '91.108.4.0/22', '91.108.8.0/21', '91.108.16.0/21',
	'91.108.56.0/22', '95.161.64.0/20', '149.154.160.0/20', '185.76.151.0/24'
];
const stockWanProxyIPv6 = [
	'2001:67c:4e8::/48', '2001:b28:f23c::/47',
	'2001:b28:f23f::/48', '2a0a:f280::/32'
];
const stockCommonPort = '22,53,80,143,443,465,587,853,873,993,995,5222,8080,8443,9418';
const updatedCommonPort = '20,21,22,25,53,80,110,119,123,143,389,443,465,514,563,587,636,853,873,989,990,993,995,1194,1883,3306,3389,5222,5432,5671,5672,5900,6379,6443,6514,8080,8443,8883,9418';

function onlyContains(left, right) {
	const values = normalizeList(left);
	return length(values) > 0 && length(filter(values, (value) => index(right, value) === -1)) === 0;
}

function setDefault(section, option, value) {
	if (uci.get(uciconfig, section, option) === null)
		uci.set(uciconfig, section, option, value);
}

function migrateOption(section, oldOption, newOption) {
	const oldValue = uci.get(uciconfig, section, oldOption);
	if (oldValue === null)
		return;
	if (uci.get(uciconfig, section, newOption) === null)
		uci.set(uciconfig, section, newOption, oldValue);
	uci.delete(uciconfig, section, oldOption);
}

function mergeListOption(section, sourceOption, targetOption) {
	const source = normalizeList(uci.get(uciconfig, section, sourceOption));
	const target = normalizeList(uci.get(uciconfig, section, targetOption));
	if (length(source))
		uci.set(uciconfig, section, targetOption, uniq([...target, ...source]));
	if (uci.get(uciconfig, section, sourceOption) !== null)
		uci.delete(uciconfig, section, sourceOption);
}

function splitPortList(value) {
	return filter(map(split(value || '', ','), (port) => trim(port)), (port) => port);
}

function migrateCommonPortExtras(commonPort, basePort) {
	const common = splitPortList(commonPort);
	const base = splitPortList(basePort);
	if (length(common) <= length(base) ||
	    length(filter(base, (port) => index(common, port) === -1)))
		return false;

	const extras = filter(common, (port) => index(base, port) === -1);
	if (!length(extras))
		return false;

	const configured = normalizeList(uci.get(uciconfig, 'config', 'routing_port_extra'));
	uci.set(uciconfig, 'config', 'routing_port_extra', uniq([...configured, ...extras]));
	uci.set(uciconfig, 'infra', 'common_port', updatedCommonPort);
	return true;
}

const commonPort = uci.get(uciconfig, 'infra', 'common_port');
if (commonPort === stockCommonPort)
	uci.set(uciconfig, 'infra', 'common_port', updatedCommonPort);
else if (commonPort !== updatedCommonPort &&
	 !migrateCommonPortExtras(commonPort, updatedCommonPort) &&
	 !migrateCommonPortExtras(commonPort, stockCommonPort))
	setDefault('infra', 'common_port', updatedCommonPort);

/* Only migrate nodes written before this schema marker was recorded. */
const subscriptionNodeMigration = '1';
const subscriptionNodeMigrationOption = 'subscription_node_migration';
const subscriptionNodeMigrationState = uci.get(
	uciconfig, 'migration', subscriptionNodeMigrationOption
);
if (subscriptionNodeMigrationState !== subscriptionNodeMigration) {
	/* The updater reconciles old node IDs after a successful download. Keep the
	 * existing nodes available when the network or subscription is unavailable. */
	if (uci.get(uciconfig, 'migration') === null)
		uci.set(uciconfig, 'migration', 'sbproxy');
	uci.set(
		uciconfig, 'migration', subscriptionNodeMigrationOption,
		subscriptionNodeMigration
	);
}

synchronizeNodeLabels(uci, uciconfig);

/* Keep only the modes implemented by the 1.14 configuration generator. */
if (!(uci.get(uciconfig, 'config', 'routing_mode') in ['bypass_mainland_china', 'custom', 'global']))
	uci.set(uciconfig, 'config', 'routing_mode', 'bypass_mainland_china');
if (!(uci.get(uciconfig, 'config', 'proxy_mode') in ['tun', 'tproxy']))
	uci.set(uciconfig, 'config', 'proxy_mode', 'tun');

for (let option in [
	'main_udp_node', 'main_udp_urltest_nodes',
	'main_udp_urltest_interval', 'main_udp_urltest_tolerance',
	'github_token', 'dashboard_download_url'
])
	if (uci.get(uciconfig, 'config', option) !== null)
		uci.delete(uciconfig, 'config', option);

for (let option in [
	'china_dns_port', 'redirect_port', 'tun_mark', 'tun_gso',
	'sniff_override', 'github_token'
])
	if (uci.get(uciconfig, 'infra', option) !== null)
		uci.delete(uciconfig, 'infra', option);

for (let option in ['endpoint_independent_nat', 'sniff_override'])
	if (uci.get(uciconfig, 'routing', option) !== null)
		uci.delete(uciconfig, 'routing', option);

for (let option in ['independent_cache', 'cache_file_store_rdrc', 'cache_file_rdrc_timeout'])
	if (uci.get(uciconfig, 'dns', option) !== null)
		uci.delete(uciconfig, 'dns', option);

if (uci.get(uciconfig, 'config', 'routing_port') === 'all')
	uci.delete(uciconfig, 'config', 'routing_port');
if (uci.get(uciconfig, 'routing', 'default_outbound') === 'block-out')
	uci.set(uciconfig, 'routing', 'default_outbound', 'reject');

for (let pair in [
	['lan_gaming_mode_ipv4_ips', 'lan_proxy_ipv4_ips'],
	['lan_gaming_mode_mac_addrs', 'lan_proxy_mac_addrs'],
	['lan_global_proxy_ipv4_ips', 'lan_proxy_ipv4_ips'],
	['lan_global_proxy_mac_addrs', 'lan_proxy_mac_addrs']
])
	mergeListOption('control', pair[0], pair[1]);

for (let option in [
	'lan_proxy_mode', 'lan_direct_ipv6_ips', 'lan_proxy_ipv6_ips',
	'lan_global_proxy_ipv6_ips', 'lan_gaming_mode_ipv6_ips'
])
	if (uci.get(uciconfig, 'control', option) !== null)
		uci.delete(uciconfig, 'control', option);

uci.foreach(uciconfig, 'node', (section) => {
	for (let pair in [
		['hysteria_recv_window_conn', 'hysteria_stream_receive_window'],
		['hysteria_revc_window', 'hysteria_connection_receive_window'],
		['hysteria_disable_mtu_discovery', 'hysteria_disable_path_mtu_discovery']
	])
		migrateOption(section['.name'], pair[0], pair[1]);
	if (uci.get(uciconfig, section['.name'], 'hysteria_protocol') !== null)
		uci.delete(uciconfig, section['.name'], 'hysteria_protocol');
});

uci.foreach(uciconfig, 'server', (section) => {
	for (let pair in [
		['hysteria_recv_window_conn', 'hysteria_stream_receive_window'],
		['hysteria_recv_window_client', 'hysteria_connection_receive_window'],
		['hysteria_revc_window_client', 'hysteria_connection_receive_window'],
		['hysteria_max_conn_client', 'hysteria_max_concurrent_streams'],
		['hysteria_disable_mtu_discovery', 'hysteria_disable_path_mtu_discovery']
	])
		migrateOption(section['.name'], pair[0], pair[1]);
	if (uci.get(uciconfig, section['.name'], 'hysteria_protocol') !== null)
		uci.delete(uciconfig, section['.name'], 'hysteria_protocol');
});

/* These Telegram ranges were redundant after the old routing modes were removed. */
if (onlyContains(uci.get(uciconfig, 'control', 'wan_proxy_ipv4_ips'), stockWanProxyIPv4))
	uci.delete(uciconfig, 'control', 'wan_proxy_ipv4_ips');
if (onlyContains(uci.get(uciconfig, 'control', 'wan_proxy_ipv6_ips'), stockWanProxyIPv6))
	uci.delete(uciconfig, 'control', 'wan_proxy_ipv6_ips');

if (uci.get(uciconfig, 'subscription', 'latency_test_mode') !== null)
	uci.delete(uciconfig, 'subscription', 'latency_test_mode');

const subscriptionUserAgent = uci.get(uciconfig, 'subscription', 'user_agent');
if (subscriptionUserAgent === 'v2rayN/7.23.4' ||
	subscriptionUserAgent === 'sing-box/1.14.0-beta.2')
	uci.set(uciconfig, 'subscription', 'user_agent', 'sbproxy');

setDefault('infra', 'ntp_server', 'nil');
if (isEmpty(uci.get(uciconfig, 'infra', 'udp_timeout')))
	uci.set(uciconfig, 'infra', 'udp_timeout', '300');
setDefault('infra', 'tailscale_api_port', 'auto');
setDefault('infra', 'tailscale_api_port_initialized', '0');
setDefault('config', 'main_urltest_interval', '180');
setDefault('config', 'main_urltest_tolerance', '50');
setDefault('config', 'main_urltest_interrupt_exist_connections', '1');
setDefault('config', 'log_level', 'warn');
setDefault('routing', 'tcpip_stack', 'mixed');
if (isEmpty(uci.get(uciconfig, 'routing', 'udp_timeout')))
	uci.set(uciconfig, 'routing', 'udp_timeout', '300');
setDefault('routing', 'bypass_cn_traffic', '0');
setDefault('routing', 'default_outbound', 'nil');
setDefault('routing', 'default_outbound_dns', 'default-dns');
setDefault('dns', 'default_strategy', 'prefer_ipv4');
setDefault('dns', 'default_server', 'default-dns');
setDefault('dns', 'disable_cache', '0');
setDefault('dns', 'disable_cache_expire', '0');
setDefault('dns', 'optimistic', '0');
setDefault('dns', 'timeout', '10');
setDefault('dns', 'cache_file_store_dns', '0');
setDefault('server', 'log_level', 'warn');

if (uci.get(uciconfig, 'tailscale') === null)
	uci.set(uciconfig, 'tailscale', 'sbproxy');
setDefault('tailscale', 'enabled', '0');
setDefault('tailscale', 'state_directory', '/etc/sbproxy/tailscale');
setDefault('tailscale', 'system_interface_name', 'tailscale0');
setDefault('tailscale', 'system_interface_mtu', '1280');
setDefault('tailscale', 'listen_port', '41641');
setDefault('tailscale', 'accept_routes', '0');
setDefault('tailscale', 'magic_dns', '1');
setDefault('tailscale', 'accept_search_domain', '1');
setDefault('tailscale', 'advertise_exit_node', '0');
setDefault('tailscale', 'exit_node_allow_lan_access', '0');
setDefault('tailscale', 'disable_snat_subnet_routes', '0');
setDefault('tailscale', 'relay_server_enabled', '0');
setDefault('tailscale', 'relay_server_port', '0');
setDefault('tailscale', 'ephemeral', '0');
setDefault('tailscale', 'ssh_server', '0');
setDefault('tailscale', 'ssh_disable_pty', '0');
setDefault('tailscale', 'ssh_disable_sftp', '0');
setDefault('tailscale', 'ssh_disable_forwarding', '0');
setDefault('tailscale', 'taildrop_enabled', '0');
setDefault('tailscale', 'taildrop_directory', '/etc/sbproxy/tailscale/Taildrop');
setDefault('tailscale', 'udp_timeout', '300');

reconcileUrltestNodes(uci, uciconfig);

const mainNode = uci.get(uciconfig, 'config', 'main_node') || 'nil';
if (mainNode !== 'nil' && mainNode !== 'urltest' &&
	uci.get(uciconfig, mainNode) !== 'node')
	uci.set(uciconfig, 'config', 'main_node', uci.get_first(uciconfig, 'node') || 'nil');

if (getenv('SBPROXY_MIGRATION_SKIP_CLEANUP') !== '1')
	system('rm -f "/etc/sbproxy/resources/china_list.txt" "/etc/sbproxy/resources/china_list.ver" "/etc/sbproxy/resources/gfw_list.txt" "/etc/sbproxy/resources/gfw_list.ver"');

if (!isEmpty(uci.changes(uciconfig)) && uci.commit(uciconfig) !== true)
	exit(1);
