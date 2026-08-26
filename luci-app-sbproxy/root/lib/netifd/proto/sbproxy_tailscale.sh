#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-only

. /lib/functions.sh
. /lib/netifd/netifd-proto.sh

notify_status() {
	local interface="$1" device="$2" ipv4="$3" ipv6="$4" up="$5"

	proto_init_update "$device" "$up" 1
	proto_set_keep 1
	if [ "$up" = "1" ]; then
		case "$ipv4" in
			'') ;;
			*/*) proto_add_ipv4_address "${ipv4%/*}" "${ipv4#*/}" ;;
			*) proto_add_ipv4_address "$ipv4" 32 ;;
		esac
		case "$ipv6" in
			'') ;;
			*/*) proto_add_ipv6_address "${ipv6%/*}" "${ipv6#*/}" ;;
			*) proto_add_ipv6_address "$ipv6" 128 ;;
		esac
	fi
	proto_send_update "$interface"
}

if [ "${1:-}" = "notify" ]; then
	notify_status "$2" "$3" "$4" "$5" "${6:-1}"
	exit $?
fi

init_proto "$@"

proto_sbproxy_tailscale_init_config() {
	proto_config_add_string device
	proto_config_add_string ipaddr
	proto_config_add_array "ip6addr:list(string)"
	no_device=1
	available=1
	no_proto_task=1
}

proto_sbproxy_tailscale_setup() {
	local interface="$1" device ipaddr ip6addr address up=0

	json_get_vars device ipaddr
	json_get_values ip6addr ip6addr
	[ -n "$device" ] || device=tailscale0
	[ -d "/sys/class/net/$device" ] && up=1
	for address in $ip6addr; do
		ip6addr="$address"
		break
	done
	notify_status "$interface" "$device" "$ipaddr" "$ip6addr" "$up"
}

proto_sbproxy_tailscale_teardown() {
	local interface="$1" device

	json_get_var device device
	[ -n "$device" ] || device=tailscale0
	notify_status "$interface" "$device" '' '' 0
}

add_protocol sbproxy_tailscale
