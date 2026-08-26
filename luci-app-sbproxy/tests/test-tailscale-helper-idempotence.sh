#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$TEST_ROOT/bin"
: > "$TEST_ROOT/functions.sh"
: > "$TEST_ROOT/uci.db"
: > "$TEST_ROOT/uci.set-count"
: > "$TEST_ROOT/ip.routes"
: > "$TEST_ROOT/ip.rules"
: > "$TEST_ROOT/ip.rule-add-count"

cat > "$TEST_ROOT/bin/uci" <<-'EOF'
	#!/bin/sh
	set -eu

	db="${MOCK_UCI_DB:?}"
	count="${MOCK_UCI_SET_COUNT:?}"
	[ "${1:-}" != '-q' ] || shift
	action="${1:-}"
	shift || true

	case "$action" in
	get)
		awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; found=1; exit } END { exit !found }' "$db"
		;;
	show)
		prefix="${1:-}"
		if [ -n "$prefix" ]; then
			awk -F= -v prefix="$prefix" '$1 == prefix || index($1, prefix ".") == 1' "$db"
		else
			cat "$db"
		fi
		;;
set)
		key="${1%%=*}"
		value="${1#*=}"
		tmp="$db.new"
		awk -F= -v key="$key" '$1 != key' "$db" > "$tmp"
		printf '%s=%s\n' "$key" "$value" >> "$tmp"
		mv "$tmp" "$db"
		printf 'set\n' >> "$count"
		;;
	add_list)
		key="${1%%=*}"
		value="${1#*=}"
		tmp="$db.new"
		awk -F= -v key="$key" -v value="$value" '
			$1 == key { print key "=" $2 " " value; found=1; next }
			{ print }
			END { if (!found) print key "=" value }
		' "$db" > "$tmp"
		mv "$tmp" "$db"
		printf 'set\n' >> "$count"
		;;
	delete)
		key="$1"
		tmp="$db.new"
		awk -F= -v key="$key" '$1 != key && index($1, key ".") != 1' "$db" > "$tmp"
		mv "$tmp" "$db"
		;;
	*) exit 1 ;;
	esac
EOF
chmod 755 "$TEST_ROOT/bin/uci"

cat > "$TEST_ROOT/bin/ip" <<-'EOF'
	#!/bin/sh
	set -eu

	routes="${MOCK_IP_ROUTES:?}"
	rules="${MOCK_IP_RULES:?}"
	adds="${MOCK_IP_RULE_ADD_COUNT:?}"
	family="$1"
	shift
	object="$1"
	shift
	action="$1"
	shift || true

	show_rules() {
		awk -F'|' -v family="$family" -v priority="${1:-}" '
			$1 == family && (priority == "" || $2 == priority) {
				if ($3 == "lookup") print $2 ": from all lookup " $4
				else if ($3 == "lookup-to") print $2 ": from all to " $4 " lookup 52"
				else if ($3 == "goto") print $2 ": from all goto " $4
				else if ($3 == "fwmark") print $2 ": from all fwmark " $4
				else if ($3 == "nop") print $2 ": from all nop"
			}
		' "$rules"
	}

	case "$object:$action" in
	route:show)
		test "$1" = match
		prefix="$2"
		printf '%s\n' 'default via 192.0.2.1 dev wan'
		awk -F'|' -v family="$family" -v prefix="$prefix" '
			$1 == family && $2 == prefix { print $2 " dev " $3 }
		' "$routes"
		;;
	route:del)
		prefix="$1"
		device="$3"
		tmp="$routes.new"
		awk -F'|' -v family="$family" -v prefix="$prefix" -v device="$device" \
			'!($1 == family && $2 == prefix && $3 == device)' "$routes" > "$tmp"
		mv "$tmp" "$routes"
		;;
	rule:show)
		if [ "${1:-}" = priority ]; then
			show_rules "$2"
		else
			show_rules
		fi
		;;
	rule:add)
		test "$1" = priority
		priority="$2"
		shift 2
		case "$1" in
		to)
			test "$3" = table
			test "$4" = 52
			printf '%s|%s|lookup-to|%s\n' "$family" "$priority" "$2" >> "$rules"
			;;
		goto)
			printf '%s|%s|goto|%s\n' "$family" "$priority" "$2" >> "$rules"
			;;
		*) exit 1 ;;
		esac
		printf 'add\n' >> "$adds"
		;;
	rule:del)
		test "$1" = priority
		priority="$2"
		shift 2
		case "${1:-}" in
		to) kind=lookup-to; target="$2" ;;
		goto) kind=goto; target="$2" ;;
		*) exit 1 ;;
		esac
		tmp="$rules.new"
		awk -F'|' -v family="$family" -v priority="$priority" -v kind="$kind" -v target="$target" \
			'!($1 == family && $2 == priority && $3 == kind && $4 == target)' "$rules" > "$tmp"
		mv "$tmp" "$rules"
		;;
	*) exit 1 ;;
	esac
EOF
chmod 755 "$TEST_ROOT/bin/ip"

export MOCK_UCI_DB="$TEST_ROOT/uci.db"
export MOCK_UCI_SET_COUNT="$TEST_ROOT/uci.set-count"
export MOCK_IP_ROUTES="$TEST_ROOT/ip.routes"
export MOCK_IP_RULES="$TEST_ROOT/ip.rules"
export MOCK_IP_RULE_ADD_COUNT="$TEST_ROOT/ip.rule-add-count"
export PATH="$TEST_ROOT/bin:$PATH"
export SBPROXY_FUNCTIONS_LIB="$TEST_ROOT/functions.sh"
export SBPROXY_TAILSCALE_HELPER_LIBRARY_ONLY=1
export SBPROXY_IP_BIN="$TEST_ROOT/bin/ip"
export SBPROXY_TAILSCALE_ROUTE_STATE="$TEST_ROOT/tailscale_routes"
export SBPROXY_TAILSCALE_NETIFD_PROTO="$TEST_ROOT/netifd-proto"

# shellcheck source=/dev/null
. "$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper"
log_error() { :; }

INTERFACE_NAME='tailscale0'
TS_IPV4='100.86.103.57'
TS_IPV6='fd7a:115c:a1e0::f337:673a'
NAT_FILE="$TEST_ROOT/fw4_tailscale.nft"
ACCESS=''
DISABLE_SNAT=0
ACCEPT_ROUTES=1
EXIT_NODE=''
SUBNET_ROUTES='192.168.7.0/24 192.168.8.0/24 0.0.0.0/0'

cat > "$TEST_ROOT/ip.rules" <<-'EOF'
	-4|5270|lookup|52
	-4|9000|fwmark|0x2024
	-4|9002|nop|
	-4|32766|lookup|main
	-6|5270|lookup|52
	-6|32766|lookup|main
EOF
printf '%s\n' '-4|192.168.8.0/24|br-lan' > "$TEST_ROOT/ip.routes"

configure_network
network_count="$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')"
grep -Fq 'network.sbproxy_ts=interface' "$TEST_ROOT/uci.db"
grep -Fq 'network.sbproxy_ts.proto=sbproxy_tailscale' "$TEST_ROOT/uci.db"
grep -Fq 'network.sbproxy_ts.device=tailscale0' "$TEST_ROOT/uci.db"
grep -Fq 'network.sbproxy_ts.auto=1' "$TEST_ROOT/uci.db"
grep -Fq 'network.sbproxy_ts.ipaddr=100.86.103.57' "$TEST_ROOT/uci.db"
grep -Fq 'network.sbproxy_ts.ip6addr=fd7a:115c:a1e0::f337:673a/128' "$TEST_ROOT/uci.db"
configure_network
test "$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')" -eq "$network_count"

cat >> "$TEST_ROOT/uci.db" <<-'EOF'
	dropbear.main=dropbear
	dropbear.main.DirectInterface=lan
	dropbear.@dropbear[1]=dropbear
	dropbear.@dropbear[1].DirectInterface=tailscale
EOF
configure_dropbear
dropbear_count="$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')"
grep -Fq 'dropbear.main.DirectInterface=lan' "$TEST_ROOT/uci.db"
grep -Fq 'dropbear.@dropbear[1].DirectInterface=sbproxy_ts' "$TEST_ROOT/uci.db"
configure_dropbear
test "$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')" -eq "$dropbear_count"

configure_route_policy
test "$(wc -l < "$TEST_ROOT/ip.rule-add-count" | tr -d ' ')" -eq 5
grep -Fq -- '-4|5260|lookup-to|100.64.0.0/10' "$TEST_ROOT/ip.rules"
grep -Fq -- '-6|5260|lookup-to|fd7a:115c:a1e0::/48' "$TEST_ROOT/ip.rules"
grep -Fq -- '-4|5260|lookup-to|192.168.7.0/24' "$TEST_ROOT/ip.rules"
! grep -Fq -- 'lookup-to|192.168.8.0/24' "$TEST_ROOT/ip.rules"
! grep -Fq -- 'lookup-to|0.0.0.0/0' "$TEST_ROOT/ip.rules"
grep -Fq -- '-4|5269|goto|9000' "$TEST_ROOT/ip.rules"
grep -Fq -- '-6|5269|goto|32766' "$TEST_ROOT/ip.rules"
grep -Fq 'priority4=5270' "$TEST_ROOT/tailscale_routes"
grep -Fq 'resume4=9000' "$TEST_ROOT/tailscale_routes"

configure_route_policy
test "$(wc -l < "$TEST_ROOT/ip.rule-add-count" | tr -d ' ')" -eq 5

# A local route introduced later must remove a previously installed exact rule.
printf '%s\n' '-4|192.168.7.0/24|br-guest' >> "$TEST_ROOT/ip.routes"
configure_route_policy
! grep -Fq -- 'lookup-to|192.168.7.0/24' "$TEST_ROOT/ip.rules"
! grep -Fq '192.168.7.0/24' "$TEST_ROOT/tailscale_routes"

EXIT_NODE='100.87.146.89'
configure_route_policy
! grep -Fq -- '|5260|lookup-to|' "$TEST_ROOT/ip.rules"
! grep -Fq -- '|5269|goto|' "$TEST_ROOT/ip.rules"
test ! -e "$TEST_ROOT/tailscale_routes"

configure_firewall
first_count="$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')"
test "$first_count" -gt "$network_count"
grep -Fq 'firewall.sbproxy_tszone.device=tailscale0' "$TEST_ROOT/uci.db"
! grep -Fq 'firewall.sbproxy_tszone.network=' "$TEST_ROOT/uci.db"
grep -Fq 'firewall.sbproxy_tszone.masq=0' "$TEST_ROOT/uci.db"
grep -Fq 'iifname "tailscale0" oifname != "tailscale0" masquerade' "$NAT_FILE"

FIREWALL_RUNTIME_CHANGED=0
configure_firewall
second_count="$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')"
test "$second_count" -eq "$first_count"
test "$FIREWALL_RUNTIME_CHANGED" -eq 0

DISABLE_SNAT=1
configure_firewall
third_count="$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')"
test "$third_count" -eq "$first_count"
test "$FIREWALL_RUNTIME_CHANGED" -eq 1
test ! -s "$NAT_FILE"

echo 'Tailscale helper test passed: interface ownership, service migration, selected routes, conflicts, exit nodes, and idempotence are safe'
