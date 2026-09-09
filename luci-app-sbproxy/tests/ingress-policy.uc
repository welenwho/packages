import { ingressEnabled, ingressDevices, ingressNft } from 'ingress';
function assert(value, message) { if (!value) die(message); }
const wifi = { radio0: { interfaces: [{ section: 'ap5g', ifname: 'phy0-ap0' }] },
	radio1: { interfaces: [{ section: 'ap2g', ifname: 'phy1-ap0' }] } };
const control = { ingress_enabled: '1', ingress_bypass_wifi: ['ap2g'], ingress_bypass_devices: ['lan1'] };
assert(!ingressEnabled({}), 'Unset policy must be disabled');
assert(!ingressEnabled({ ingress_enabled: '1' }), 'Empty policy must be disabled');
assert(ingressNft({}, {}, 'tun', '100', '5345') === '', 'Unset policy must generate no rules');
assert(join(',', ingressDevices(control, wifi)) === 'lan1,phy1-ap0', 'Wrong source resolution');
const moved = { radio1: { interfaces: [{ section: 'ap2g', ifname: 'phy4-ap1' }] } };
assert(index(ingressDevices(control, moved), 'phy4-ap1') !== -1, 'Must follow WiFi section, not old device');
assert(index(ingressDevices(control, {}), 'phy1-ap0') === -1, 'Unavailable WiFi must not match another interface');
let rejected = false;
try { ingressDevices({ ingress_bypass_devices: ['bad"; flush ruleset'] }, {}); } catch(e) { rejected = true; }
assert(rejected, 'Unsafe device must be rejected');
const tun = ingressNft(control, wifi, 'tun', '100', '5345');
assert(index(tun, 'meta mark set 0x2024 ct mark set meta mark') !== -1, 'TUN bypass mark missing');
assert(index(tun, 'meta l4proto { tcp, udp } th dport 53') !== -1, 'Both DNS transports are required');
assert(index(tun, 'ether type { ip, ip6 }') !== -1, 'IPv6 classification missing');
assert(index(tun, 'ct direction reply') !== -1, 'Must not reclassify replies');
const tproxy = ingressNft(control, wifi, 'tproxy', '100', '5345');
assert(index(tproxy, 'meta mark set 100 counter') !== -1, 'TProxy self mark missing');
assert(index(tproxy, 'ct mark set') === -1, 'TProxy must preserve other connection marks');
if (ARGV[0] === 'tun') print(tun);
else if (ARGV[0] === 'tproxy') print(tproxy);
else print('Ingress policy tests passed\n');
