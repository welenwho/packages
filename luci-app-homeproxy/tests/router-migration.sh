#!/bin/sh

set -eu

MIGRATION_SCRIPT="${1:-/tmp/migrate-config-safe.uc}"
TEST_ROOT='/tmp/homeproxy-migration-test'
UCI_DIR="$TEST_ROOT/uci"

cleanup() {
	rm -rf /tmp/homeproxy-migration-test
}

trap cleanup EXIT INT TERM
rm -rf /tmp/homeproxy-migration-test
mkdir -p "$UCI_DIR"

cat >"$UCI_DIR/homeproxy" <<-'EOF'
config homeproxy 'infra'
	option common_port '22,53,80,143,443,465,587,853,873,993,995,5222,6002,8080,8443,9418'
config homeproxy 'config'
	option routing_mode 'custom'
	option proxy_mode 'tun'
config homeproxy 'control'
config homeproxy 'routing'
config homeproxy 'dns'
config homeproxy 'subscription'
config homeproxy 'server'
config node 'subscription_node'
	option label 'Subscription node'
	option grouphash 'subscription-group'
	option type 'shadowsocks'
	option address '192.0.2.1'
	option port '443'
	option shadowsocks_encrypt_method 'aes-128-gcm'
	option password 'test'
config node 'manual_node'
	option label 'Manual node'
	option type 'shadowsocks'
	option address '192.0.2.2'
	option port '443'
	option shadowsocks_encrypt_method 'aes-128-gcm'
	option password 'test'
config routing_node 'subscription_urltest'
	option label 'Subscription URLTest'
	option enabled '1'
	option node 'urltest'
	list urltest_nodes 'subscription_node'
EOF

run_migration() {
	HOMEPROXY_UCI_CONFIG_DIR="$UCI_DIR" \
	HOMEPROXY_MIGRATION_SKIP_CLEANUP='1' \
		/usr/bin/ucode -S -L /etc/homeproxy/scripts "$MIGRATION_SCRIPT"
}

run_migration
run_migration

[ "$(uci -q -c "$UCI_DIR" get homeproxy.subscription_node)" = 'node' ]
[ "$(uci -q -c "$UCI_DIR" get homeproxy.manual_node)" = 'node' ]
[ "$(uci -q -c "$UCI_DIR" get homeproxy.subscription_urltest.enabled)" = '1' ]
[ "$(uci -q -c "$UCI_DIR" get homeproxy.subscription_urltest.urltest_nodes)" = 'subscription_node' ]
[ "$(uci -q -c "$UCI_DIR" get homeproxy.migration.subscription_node_migration)" = '1' ]
[ "$(uci -q -c "$UCI_DIR" get homeproxy.infra.common_port)" = '20,21,22,25,53,80,110,119,123,143,389,443,465,514,563,587,636,853,873,989,990,993,995,1194,1883,3306,3389,5222,5432,5671,5672,5900,6379,6443,6514,8080,8443,8883,9418' ]
[ "$(uci -q -c "$UCI_DIR" get homeproxy.config.routing_port_extra)" = '6002' ]

echo 'Migration test passed: subscription nodes and URLTest references preserved, custom common ports extracted'
