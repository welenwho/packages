#!/usr/bin/ucode

'use strict';

import { md5 } from 'digest';
import { cursor } from 'uci';

const configDir = getenv('HOMEPROXY_UCI_CONFIG_DIR');
if (!configDir)
	die('HOMEPROXY_UCI_CONFIG_DIR is required\n');

const uci = cursor(configDir);
const current = 'homeproxy';
const backup = 'homeproxy_backup';
uci.load(current);
uci.load(backup);

function normalizeList(value) {
	if (!value)
		return [];
	return (type(value) === 'array') ? value : [value];
}

function copySection(section) {
	const name = section['.name'];
	uci.delete(current, name);
	uci.set(current, name, section['.type']);
	for (let option in keys(section))
		if (!match(option, /^\./))
			uci.set(current, name, option, section[option]);
}

let allowedGroups = {};
for (let configuredUrl in normalizeList(uci.get(current, 'subscription', 'subscription_url'))) {
	const url = replace(configuredUrl, /#.*$/, '');
	allowedGroups[md5(url)] = true;
}

let restoredNodes = 0;
uci.foreach(backup, 'node', (section) => {
	if (!section.grouphash || !allowedGroups[section.grouphash])
		return;
	copySection(section);
	restoredNodes++;
});

function availableNodes(value) {
	let result = [];
	for (let node in normalizeList(value))
		if (uci.get(current, node) === 'node')
			push(result, node);
	return result;
}

let restoredGroups = 0;
uci.foreach(backup, 'routing_node', (section) => {
	const name = section['.name'];
	if (uci.get(current, name) !== 'routing_node' ||
	    length(normalizeList(uci.get(current, name, 'urltest_nodes'))))
		return;
	const nodes = availableNodes(section.urltest_nodes);
	if (!length(nodes))
		return;
	uci.set(current, name, 'urltest_nodes', nodes);
	if (section.enabled === '1')
		uci.set(current, name, 'enabled', '1');
	restoredGroups++;
});

if (!length(normalizeList(uci.get(current, 'config', 'main_urltest_nodes')))) {
	const nodes = availableNodes(uci.get(backup, 'config', 'main_urltest_nodes'));
	if (length(nodes))
		uci.set(current, 'config', 'main_urltest_nodes', nodes);
}

let retargeted = 0;
const brokenOutbound = getenv('HOMEPROXY_RECOVERY_BROKEN_OUTBOUND');
const fallbackOutbound = getenv('HOMEPROXY_RECOVERY_FALLBACK_OUTBOUND');
if (brokenOutbound || fallbackOutbound) {
	if (!brokenOutbound || !fallbackOutbound)
		die('both recovery outbound variables are required\n');
	const fallbackNodes = availableNodes(uci.get(current, fallbackOutbound, 'urltest_nodes'));
	if (uci.get(current, fallbackOutbound) !== 'routing_node' ||
	    uci.get(current, fallbackOutbound, 'enabled') !== '1' || !length(fallbackNodes))
		die('fallback outbound is unavailable\n');
	for (let sectionType in ['dns_server', 'dns_rule', 'routing_rule'])
		uci.foreach(current, sectionType, (section) => {
			if (section.outbound !== brokenOutbound)
				return;
			uci.set(current, section['.name'], 'outbound', fallbackOutbound);
			retargeted++;
		});
}

if (!restoredNodes)
	die('no matching subscription nodes found in backup\n');
if (uci.commit(current) !== true)
	die('failed to commit recovered configuration\n');

printf('restored_nodes=%d restored_urltest_groups=%d retargeted_outbounds=%d\n',
	restoredNodes, restoredGroups, retargeted);
