#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$TEST_ROOT/bin"
: > "$TEST_ROOT/functions.sh"
: > "$TEST_ROOT/uci.db"
: > "$TEST_ROOT/uci.set-count"

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
	set)
		key="${1%%=*}"
		value="${1#*=}"
		tmp="$db.new"
		awk -F= -v key="$key" '$1 != key' "$db" > "$tmp"
		printf '%s=%s\n' "$key" "$value" >> "$tmp"
		mv "$tmp" "$db"
		printf 'set\n' >> "$count"
		;;
	delete)
		key="$1"
		tmp="$db.new"
		awk -F= -v key="$key" '$1 != key && index($1, key ".") != 1' "$db" > "$tmp"
		mv "$tmp" "$db"
		;;
	*)
		exit 1
		;;
	esac
EOF
chmod 755 "$TEST_ROOT/bin/uci"

export MOCK_UCI_DB="$TEST_ROOT/uci.db"
export MOCK_UCI_SET_COUNT="$TEST_ROOT/uci.set-count"
export PATH="$TEST_ROOT/bin:$PATH"
export SBPROXY_FUNCTIONS_LIB="$TEST_ROOT/functions.sh"
export SBPROXY_TAILSCALE_HELPER_LIBRARY_ONLY=1

# shellcheck source=/dev/null
. "$PACKAGE_ROOT/root/usr/sbin/sbproxy_tailscale_helper"

INTERFACE_NAME='tailscale0'
NAT_FILE="$TEST_ROOT/fw4_tailscale.nft"
ACCESS=''
DISABLE_SNAT=0

configure_firewall
first_count="$(wc -l < "$TEST_ROOT/uci.set-count" | tr -d ' ')"
test "$first_count" -gt 0
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

echo 'Tailscale helper idempotence test passed: stable sync does not rewrite UCI and scoped SNAT updates independently'
