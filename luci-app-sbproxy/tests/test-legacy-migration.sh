#!/bin/sh

set -eu

PACKAGE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

mkdir -p "$TEST_ROOT/etc/config" \
	"$TEST_ROOT/etc/homeproxy/adaptive" \
	"$TEST_ROOT/etc/homeproxy/certs" \
	"$TEST_ROOT/etc/homeproxy/resources" \
	"$TEST_ROOT/etc/sbproxy/adaptive" \
	"$TEST_ROOT/usr/share/sbproxy/defaults"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy" \
	"$TEST_ROOT/usr/share/sbproxy/defaults/sbproxy"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy-adaptive" \
	"$TEST_ROOT/usr/share/sbproxy/defaults/sbproxy-adaptive"

cat > "$TEST_ROOT/etc/config/homeproxy" <<-'EOF'
	config homeproxy 'config'
		option main_node 'legacy-node'
		option dashboard_path '/etc/homeproxy/dashboard'
	config homeproxy 'subscription'
		option user_agent 'homeproxy'
EOF
cat > "$TEST_ROOT/etc/config/homeproxy-adaptive" <<-'EOF'
	config adaptive 'main'
		option enabled '1'
EOF
printf '%s\n' '{"version":1,"learned":{"legacy.example":{}}}' \
	> "$TEST_ROOT/etc/homeproxy/adaptive/learned.json"
printf '%s\n' 'legacy certificate' > "$TEST_ROOT/etc/homeproxy/certs/client.pem"
printf '%s\n' 'legacy.example' > "$TEST_ROOT/etc/homeproxy/resources/proxy_list.txt"
printf '%s\n' '{"version":1,"learned":{}}' > "$TEST_ROOT/etc/sbproxy/adaptive/learned.json"

old_config_hash="$(cksum "$TEST_ROOT/etc/config/homeproxy")"
old_adaptive_hash="$(cksum "$TEST_ROOT/etc/config/homeproxy-adaptive")"
old_data_hash="$(cksum "$TEST_ROOT/etc/homeproxy/adaptive/learned.json")"
SBPROXY_MIGRATION_ROOT="$TEST_ROOT" \
	sh "$PACKAGE_ROOT/root/etc/uci-defaults/00-luci-sbproxy-migrate"

test "$(cksum "$TEST_ROOT/etc/config/homeproxy")" = "$old_config_hash"
test "$(cksum "$TEST_ROOT/etc/config/homeproxy-adaptive")" = "$old_adaptive_hash"
test "$(cksum "$TEST_ROOT/etc/homeproxy/adaptive/learned.json")" = "$old_data_hash"
grep -Fq "config sbproxy 'config'" "$TEST_ROOT/etc/config/sbproxy"
grep -Fq "option dashboard_path '/etc/sbproxy/dashboard'" "$TEST_ROOT/etc/config/sbproxy"
grep -Fq "option user_agent 'sbproxy'" "$TEST_ROOT/etc/config/sbproxy"
grep -Fq "option enabled '1'" "$TEST_ROOT/etc/config/sbproxy-adaptive"
grep -Fq 'legacy.example' "$TEST_ROOT/etc/sbproxy/adaptive/learned.json"
grep -Fq 'legacy certificate' "$TEST_ROOT/etc/sbproxy/certs/client.pem"
grep -Fq 'legacy.example' "$TEST_ROOT/etc/sbproxy/resources/proxy_list.txt"

printf '%s\n' "option local_change '1'" >> "$TEST_ROOT/etc/config/sbproxy"
printf '%s\n' "option old_change '1'" >> "$TEST_ROOT/etc/config/homeproxy"
printf '%s\n' 'new legacy certificate' > "$TEST_ROOT/etc/homeproxy/certs/client.pem"
SBPROXY_MIGRATION_ROOT="$TEST_ROOT" \
	sh "$PACKAGE_ROOT/root/etc/uci-defaults/00-luci-sbproxy-migrate"
grep -Fq "option local_change '1'" "$TEST_ROOT/etc/config/sbproxy"
if grep -Fq "option old_change '1'" "$TEST_ROOT/etc/config/sbproxy"; then
	echo 'Existing SBProxy configuration was overwritten during a repeated migration' >&2
	exit 1
fi
grep -Fq 'legacy certificate' "$TEST_ROOT/etc/sbproxy/certs/client.pem"

DEFAULT_ROOT="$(mktemp -d)"
mkdir -p "$DEFAULT_ROOT/usr/share/sbproxy/defaults"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy" \
	"$DEFAULT_ROOT/usr/share/sbproxy/defaults/sbproxy"
cp "$PACKAGE_ROOT/root/usr/share/sbproxy/defaults/sbproxy-adaptive" \
	"$DEFAULT_ROOT/usr/share/sbproxy/defaults/sbproxy-adaptive"
SBPROXY_MIGRATION_ROOT="$DEFAULT_ROOT" \
	sh "$PACKAGE_ROOT/root/etc/uci-defaults/00-luci-sbproxy-migrate"
grep -Fq "config sbproxy 'config'" "$DEFAULT_ROOT/etc/config/sbproxy"
grep -Fq "config adaptive 'main'" "$DEFAULT_ROOT/etc/config/sbproxy-adaptive"
rm -rf "$DEFAULT_ROOT"

echo 'Legacy migration test passed: SBProxy receives an isolated one-time copy and leaves the source unchanged'
