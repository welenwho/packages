#!/usr/bin/ucode
'use strict';
import { readfile } from 'fs';

// Execute real worker functions, but never enter its service loop or write
// live state. Call with a valid test UCI config and the modified module path.
const source = readfile(ARGV[0]);
const boundary = index(source, '\nif (system(`/bin/mkdir -p');
if (boundary < 0) die('worker test boundary missing\n');
const run = loadstring(substr(source, 0, boundary) + `
function check(ok, label) { if (!ok) die(label + '\n'); }
let item = { target: '8.8.8.8', target_type: 'ipv4', probe_attempts: 3,
    observations: 2, fast_failures: 2, last_seen: time(), next_probe: 0 };
candidates = { 'ipv4:8.8.8.8': item };
finishUnsuccessfulProbe(item);
check(item.next_probe >= time() + 3598, 'unsuccessful probes need a cooldown');
observe(normalizeAdaptiveTarget('8.8.8.8'), true);
check(selectCandidate(time()) === null, 'failure observations must not reset cooldown');
item.next_probe = 0;
item.observations = 1;
settings.min_observations = 2;
check(selectCandidate(time()) === null, 'one fast failure must not bypass minimum observations');
item.observations = 2;
check(selectCandidate(time()) === item, 'two observations should qualify');

let promoted = false, attempts = 0;
promote = function() { promoted = true; };
ipDelay = function(port, target) {
    attempts++;
    // Direct fails twice; only one of two target samples succeeds.
    return attempts === 2 ? 100 : null;
};
settings.probe_samples = 2;
last_probe = 0;
probeCandidate();
check(!promoted, 'one successful sample out of two must not promote');
check(probe_suppressed['ipv4:8.8.8.8'] > time(), 'probe target must be excluded from failure feedback');
check(!baselineFailureTags()[PROBE_DIRECT_TAG], 'direct probe errors must not become baseline failures');
if (protect_mainland) {
    check(validTarget('49.7.47.89') === null, 'mainland IP must not be learned');
    check(validTarget('8.8.8.8') !== null, 'non-mainland IP must remain eligible');
}
print('Adaptive cooldown, failure threshold, sample majority and probe isolation tests passed\n');
`);
if (!run) die('unable to compile worker tests\n');
run();
