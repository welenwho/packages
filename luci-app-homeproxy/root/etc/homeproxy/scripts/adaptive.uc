#!/usr/bin/ucode
/* SPDX-License-Identifier: GPL-2.0-only */

'use strict';

import { open, popen, readfile, stat, writefile } from 'fs';
import { cursor } from 'uci';

import {
	adaptiveEntryTarget, normalizeAdaptiveTarget, renderAdaptiveRules, shellQuote
} from 'homeproxy';

const CONFIG = 'homeproxy-adaptive';
const SECTION = 'main';
const RUN_DIR = getenv('HOMEPROXY_ADAPTIVE_RUN_DIR') || '/var/run/homeproxy-adaptive';
const STATUS_PATH = RUN_DIR + '/status.json';
const RULES_PATH = getenv('HOMEPROXY_ADAPTIVE_RULES_PATH') || RUN_DIR + '/rules.json';
const LEARNED_PATH = getenv('HOMEPROXY_ADAPTIVE_LEARNED_PATH') || '/etc/homeproxy/adaptive/learned.json';
const CORE_LOG_PATH = getenv('HOMEPROXY_ADAPTIVE_CORE_LOG_PATH') || '/var/run/homeproxy/sing-box-c.log';
const ADAPTIVE_TAG = 'homeproxy-adaptive-out';
const FINAL_DIRECT_TAG = 'homeproxy-adaptive-final-direct-out';
const DIRECT_TAG = 'direct-out';
const MAX_ACTIVE = 1024;
const MAX_CONNECTIONS_PER_POLL = 4096;
const MAX_CANDIDATES = 256;
const MAX_UNSUCCESSFUL_PROBES = 3;
const CANDIDATE_MAX_IDLE = 86400;
const PREPARE_ONLY = getenv('HOMEPROXY_ADAPTIVE_PREPARE') === '1';
const STATUS_INTERVAL = int(getenv('HOMEPROXY_ADAPTIVE_STATUS_INTERVAL')) || 60;

const uci_config_dir = getenv('HOMEPROXY_UCI_CONFIG_DIR');
const uci = uci_config_dir ? cursor(uci_config_dir) : cursor();
uci.load(CONFIG);
uci.load('homeproxy');

if (uci.get(CONFIG, SECTION, 'enabled') !== '1' ||
    uci.get('homeproxy', 'config', 'routing_mode') !== 'custom')
	exit(0);

function configInt(name, fallback, minimum, maximum) {
	const raw = uci.get(CONFIG, SECTION, name);
	let value = int(raw);
	if (raw === null || value < minimum || value > maximum)
		value = fallback;
	return value;
}

function normalizeList(value) {
	if (!value)
		return [];
	return (type(value) === 'array') ? value : [value];
}

const settings = {
	dry_run: uci.get(CONFIG, SECTION, 'dry_run') !== '0',
	poll_interval: configInt('poll_interval', 15, 10, 300),
	slow_seconds: configInt('slow_seconds', 10, 5, 300),
	slow_bytes: configInt('slow_bytes', 65536, 0, 10485760),
	min_observations: configInt('min_observations', 2, 1, 10),
	probe_interval: configInt('probe_interval', 60, 30, 86400),
	probe_timeout: configInt('probe_timeout', 5000, 1000, 15000),
	probe_samples: configInt('probe_samples', 2, 1, 3),
	direct_slow_ms: configInt('direct_slow_ms', 1200, 100, 30000),
	min_improvement_ms: configInt('min_improvement_ms', 300, 50, 30000),
	min_improvement_percent: configInt('min_improvement_percent', 40, 1, 99),
	max_rules: configInt('max_rules', 100, 1, 100),
	max_ip_rules: configInt('max_ip_rules', 20, 1, 100),
	max_load: configInt('max_load', 2, 0, 128),
	exclude_suffix: normalizeList(uci.get(CONFIG, SECTION, 'exclude_suffix'))
};

let direct_probe_port = int(getenv('HOMEPROXY_ADAPTIVE_DIRECT_PROBE_PORT')) ||
	int(uci.get(CONFIG, SECTION, 'direct_probe_port'));
let proxy_probe_port = int(getenv('HOMEPROXY_ADAPTIVE_PROXY_PROBE_PORT')) ||
	int(uci.get(CONFIG, SECTION, 'proxy_probe_port'));

const clash_api_port = int(uci.get('homeproxy', 'infra', 'clash_api_port'));
const controller = `http://127.0.0.1:${clash_api_port}`;

let active = {};
let active_count = 0;
let candidates = {};
let candidate_lru = {};
let learned = [];
let learned_by_target = {};
let learned_lru = {};
let persisted_seen = {};
let learned_dirty = false;
let lru_clock = 0;
let last_persist = 0;
let last_status = 0;
let last_probe = 0;
let last_cleanup = 0;
let last_error = null;
let last_poll = 0;
let poll_count = 0;
let probe_count = 0;
let failure_count = 0;
let paused_for_load = false;
let log_offset = 0;
let log_remainder = '';
let log_tail = '';

function atomicWrite(path, content, mode) {
	const lockfd = open(RUN_DIR + '/write.lock', 'w', 0600);
	if (!lockfd || lockfd.lock('x') !== true) {
		lockfd?.close();
		return false;
	}
	const temporary = path + '.tmp';
	let result = writefile(temporary, content) !== null && system(sprintf(
		'/bin/chmod %s %s && /bin/mv -f %s %s',
		shellQuote(mode), shellQuote(temporary), shellQuote(temporary), shellQuote(path)
	)) === 0;
	lockfd.lock('u');
	lockfd.close();
	return result;
}

function parseJson(content) {
	if (!content)
		return null;
	try {
		return json(content);
	} catch (e) {
		return null;
	}
}

function readCommand(command) {
	const fd = popen(command);
	if (!fd)
		return null;

	let chunks = [], total = 0;
	while (true) {
		const chunk = fd.read(64 * 1024);
		if (chunk === null || chunk === '')
			break;
		total += length(chunk);
		if (total > 2 * 1024 * 1024) {
			fd.close();
			return null;
		}
		push(chunks, chunk);
	}
	const status = fd.close();
	return (status === 0) ? join('', chunks) : null;
}

function setError(message) {
	message = message || null;
	if (message === last_error)
		return;
	last_error = message;
	if (message)
		warn(`homeproxy-adaptive: ${message}\n`);
}

function validTarget(value) {
	const target = normalizeAdaptiveTarget(sprintf('%s', value || ''));
	if (!target || target.type !== 'domain')
		return target;

	for (let suffix in settings.exclude_suffix) {
		suffix = lc(trim(sprintf('%s', suffix || '')));
		suffix = replace(suffix, /^\.+|\.+$/g, '');
		if (!suffix)
			continue;
		if (target.value === suffix ||
		    substr(target.value, -(length(suffix) + 1)) === '.' + suffix)
			return null;
	}

	return target;
}

function hasChain(connection, tag) {
	for (let chain in normalizeList(connection?.chains))
		if (chain === tag)
			return true;
	return false;
}

function learnedKey(entry) {
	return adaptiveEntryTarget(entry)?.key;
}

function evictEntry(index) {
	const key = learnedKey(learned[index]);
	delete persisted_seen[key];
	delete learned_lru[key];
	delete learned_by_target[key];
	splice(learned, index, 1);
}

function oldestLearnedIndex(ip_only) {
	let oldest = -1;
	for (let i = 0; i < length(learned); i++) {
		const target = adaptiveEntryTarget(learned[i]);
		if (!target || (ip_only && target.type === 'domain'))
			continue;
		if (oldest === -1 || learned[i].last_seen < learned[oldest].last_seen ||
		    (learned[i].last_seen === learned[oldest].last_seen &&
		     learned_lru[target.key] < learned_lru[learnedKey(learned[oldest])]))
			oldest = i;
	}
	return oldest;
}

function evictOldest() {
	let evicted = false, ip_count = 0;
	for (let entry in learned)
		if (adaptiveEntryTarget(entry)?.type !== 'domain')
			ip_count++;

	while (ip_count > settings.max_ip_rules) {
		const oldest = oldestLearnedIndex(true);
		if (oldest < 0)
			break;
		evictEntry(oldest);
		ip_count--;
		evicted = true;
	}
	while (length(learned) > settings.max_rules) {
		const oldest = oldestLearnedIndex(false);
		if (oldest < 0)
			break;
		evictEntry(oldest);
		evicted = true;
	}
	return evicted;
}

function loadLearned() {
	const state = parseJson(readfile(LEARNED_PATH));
	const now = time();
	for (let entry in normalizeList(state?.entries)) {
		const target = validTarget(entry?.target || entry?.domain || entry?.ip);
		const last_seen = int(entry?.last_seen) || int(entry?.added_at) || now;
		if (!target || learned_by_target[target.key]) {
			learned_dirty = true;
			continue;
		}
		const normalized = {
			target: target.value,
			target_type: target.type,
			added_at: int(entry.added_at) || now,
			last_seen,
			direct_ms: int(entry.direct_ms),
			proxy_ms: int(entry.proxy_ms),
			observations: int(entry.observations),
			reason: entry.reason || 'latency'
		};
		push(learned, normalized);
		learned_by_target[target.key] = normalized;
		learned_lru[target.key] = ++lru_clock;
		persisted_seen[target.key] = last_seen;
		if (entry.target !== target.value || entry.target_type !== target.type)
			learned_dirty = true;
	}
	if (evictOldest())
		learned_dirty = true;
}

function writeRules() {
	const ruleset = renderAdaptiveRules(learned, !settings.dry_run);
	return atomicWrite(RULES_PATH, sprintf('%.J\n', ruleset), '0644');
}

function persistLearned(force) {
	const now = time();
	if (!learned_dirty && !force)
		return true;
	if (!force && now - last_persist < 3600)
		return true;

	const state = { version: 1, entries: learned };
	if (!atomicWrite(LEARNED_PATH, sprintf('%.J\n', state), '0600'))
		return false;
	persisted_seen = {};
	for (let entry in learned)
		persisted_seen[learnedKey(entry)] = entry.last_seen;
	learned_dirty = false;
	last_persist = now;
	return true;
}

function touchLearned(entry, now) {
	const key = learnedKey(entry);
	entry.last_seen = now;
	learned_lru[key] = ++lru_clock;
	if (now - (persisted_seen[key] || 0) >= 86400)
		learned_dirty = true;
}

function candidateArray() {
	let result = [];
	for (let domain, candidate in candidates)
		push(result, candidate);
	return result;
}

function deleteCandidate(key) {
	delete candidates[key];
	delete candidate_lru[key];
}

function oldestCandidateKey() {
	let oldest = null;
	for (let key, candidate in candidates) {
		if (oldest === null || candidate.last_seen < candidates[oldest].last_seen ||
		    (candidate.last_seen === candidates[oldest].last_seen &&
		     candidate_lru[key] < candidate_lru[oldest]))
			oldest = key;
	}
	return oldest;
}

function writeStatus(force) {
	const now = time();
	if (!force && now - last_status < STATUS_INTERVAL)
		return;
	const status = {
		version: 1,
		running: true,
		dry_run: settings.dry_run,
		last_poll,
		last_error,
		poll_count,
		probe_count,
		failure_count,
		paused_for_load,
		active_connections: active_count,
		candidates: candidateArray(),
		learned
	};
	if (atomicWrite(STATUS_PATH, sprintf('%.J\n', status), '0644'))
		last_status = now;
}

function observe(target, fast_failure) {
	if (!target || learned_by_target[target.key])
		return;
	const now = time();
	let candidate = candidates[target.key];
	if (!candidate) {
		if (length(candidates) >= MAX_CANDIDATES) {
			const oldest = oldestCandidateKey();
			if (oldest !== null)
				deleteCandidate(oldest);
		}
		candidate = {
			target: target.value,
			target_type: target.type,
			first_seen: now,
			last_seen: now,
			observations: 0,
			last_probe: 0,
			next_probe: 0,
			probe_attempts: 0,
			fast_failures: 0,
			direct_ms: 0,
			proxy_ms: 0
		};
		candidates[target.key] = candidate;
	}
	candidate.last_seen = now;
	candidate_lru[target.key] = ++lru_clock;
	candidate.observations++;
	if (fast_failure)
		candidate.fast_failures++;
}

function connectionTarget(metadata) {
	const host = trim(sprintf('%s', metadata?.host || ''));
	if (host)
		return validTarget(host);
	return validTarget(metadata?.destinationIP || metadata?.destination_ip);
}

function isFinalDirect(connection) {
	return connection.rule === 'final' &&
		(hasChain(connection, FINAL_DIRECT_TAG) || hasChain(connection, DIRECT_TAG));
}

function pollConnections() {
	if (clash_api_port < 1 || clash_api_port > 65535) {
		setError('Clash API port is unavailable');
		return false;
	}

	const payload = readCommand(sprintf(
		'/usr/bin/curl -fsS --connect-timeout 1 --max-time 2 %s 2>/dev/null',
		shellQuote(controller + '/connections')
	));
	const response = parseJson(payload);
	if (type(response?.connections) !== 'array') {
		setError('Clash API connection snapshot is unavailable');
		return false;
	}

	const now = time();
	let seen = {}, processed = 0;
	for (let connection in response.connections) {
		if (++processed > MAX_CONNECTIONS_PER_POLL)
			break;
		const id = trim(sprintf('%s', connection?.id || ''));
		const metadata = connection?.metadata || {};
		const target = connectionTarget(metadata);
		const port = int(metadata.destinationPort || metadata.destination_port);
		if (!id || !target || metadata.network !== 'tcp' || port !== 443)
			continue;

		const learned_entry = learned_by_target[target.key];
		if (learned_entry &&
		    (hasChain(connection, ADAPTIVE_TAG) || isFinalDirect(connection))) {
			touchLearned(learned_entry, now);
			continue;
		}

		if (!isFinalDirect(connection))
			continue;
		seen[id] = true;
		let tracked = active[id];
		if (!tracked) {
			if (active_count >= MAX_ACTIVE)
				continue;
			active[id] = {
				target,
				first_seen: now,
				download: int(connection.download),
				observed: false
			};
			active_count++;
			continue;
		}

		if (!tracked.observed && now - tracked.first_seen >= settings.slow_seconds &&
		    int(connection.download) - tracked.download <= settings.slow_bytes) {
			observe(tracked.target);
			tracked.observed = true;
		}
	}

	for (let id, tracked in active) {
		if (!seen[id]) {
			delete active[id];
			active_count--;
		}
	}

	last_poll = now;
	poll_count++;
	setError(null);
	return true;
}

function initFailureLog() {
	const metadata = stat(CORE_LOG_PATH);
	log_offset = int(metadata?.size);
	log_remainder = '';
	log_tail = '';
	if (!log_offset)
		return;
	const fd = open(CORE_LOG_PATH, 'r');
	if (!fd)
		return;
	const tail_start = (log_offset > 128) ? log_offset - 128 : 0;
	if (fd.seek(tail_start) === true)
		log_tail = fd.read(log_offset - tail_start) || '';
	fd.close();
}

function pollFastFailures() {
	const metadata = stat(CORE_LOG_PATH);
	if (!metadata)
		return;
	if (metadata.size < log_offset) {
		log_offset = 0;
		log_remainder = '';
		log_tail = '';
	}
	if (metadata.size === log_offset)
		return;

	const fd = open(CORE_LOG_PATH, 'r');
	if (!fd)
		return;
	if (log_offset && length(log_tail)) {
		const tail_start = log_offset - length(log_tail);
		if (fd.seek(tail_start) !== true || fd.read(length(log_tail)) !== log_tail) {
			log_offset = 0;
			log_remainder = '';
			log_tail = '';
		}
	}
	if (fd.seek(log_offset) !== true) {
		fd.close();
		return;
	}

	let chunks = [], total = 0;
	while (true) {
		const chunk = fd.read(64 * 1024);
		if (chunk === null || chunk === '')
			break;
		total += length(chunk);
		if (total > 256 * 1024) {
			chunks = [];
			log_remainder = '';
			break;
		}
		push(chunks, chunk);
	}
	log_offset = fd.tell();
	fd.close();
	if (!length(chunks))
		return;

	const appended = join('', chunks);
	log_tail = substr(log_tail + appended, -128);
	const content = log_remainder + appended;
	const lines = split(content, /\n/);
	log_remainder = pop(lines) || '';
	for (let line in lines) {
		const matched = match(line,
			/open connection to (\[[0-9a-fA-F:]+\]|[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]):443 using outbound\/direct\[homeproxy-adaptive-final-direct-out\]:/);
		const target = matched ? validTarget(matched[1]) : null;
		if (!target)
			continue;
		observe(target, true);
		failure_count++;
	}
}

function currentLoad() {
	const fields = split(trim(readfile('/proc/loadavg') || ''), /\s+/);
	return +(fields[0] || '0');
}

function domainDelay(tag, domain) {
	const payload = readCommand(sprintf(
		'/usr/bin/curl -fsS --connect-timeout 1 --max-time %d --get --data-urlencode %s --data-urlencode %s %s 2>/dev/null',
		int((settings.probe_timeout + 1999) / 1000),
		shellQuote(`url=https://${domain}/`),
		shellQuote(`timeout=${settings.probe_timeout}`),
		shellQuote(`${controller}/proxies/${tag}/delay`)
	));
	const response = parseJson(payload);
	const value = int(response?.delay);
	return value > 0 ? value : null;
}

function probePort(kind) {
	let port = kind === 'direct' ? direct_probe_port : proxy_probe_port;
	if (port >= 1 && port <= 65535)
		return port;

	const config_arg = uci_config_dir ? `-c ${shellQuote(uci_config_dir)} ` : '';
	port = int(trim(readCommand(sprintf('/sbin/uci -q %sget %s 2>/dev/null',
		config_arg, shellQuote(`${CONFIG}.${SECTION}.${kind}_probe_port`))) || ''));
	if (port < 1 || port > 65535)
		return null;
	if (kind === 'direct')
		direct_probe_port = port;
	else
		proxy_probe_port = port;
	return port;
}

function ipDelay(probe_port, target) {
	if (probe_port < 1 || probe_port > 65535)
		return null;

	const host = target.type === 'ipv6' ? `[${target.value}]` : target.value;
	const timeout = int((settings.probe_timeout + 999) / 1000);
	const payload = readCommand(sprintf(
		'/usr/bin/curl -k -sS -o /dev/null --head --noproxy %s --proxy %s ' +
		'--connect-timeout %d --max-time %d --write-out %s %s 2>/dev/null || true',
		shellQuote(''), shellQuote(`socks5://127.0.0.1:${probe_port}`),
		timeout, timeout, shellQuote('%{time_appconnect}'),
		shellQuote(`https://${host}:443/`)
	));
	const seconds = +(trim(payload || '') || '0');
	const milliseconds = int(seconds * 1000 + 0.5);
	return milliseconds > 0 ? milliseconds : null;
}

function median(values) {
	if (!length(values))
		return null;
	for (let i = 1; i < length(values); i++) {
		let value = values[i], j = i - 1;
		while (j >= 0 && values[j] > value) {
			values[j + 1] = values[j];
			j--;
		}
		values[j + 1] = value;
	}
	const middle = int(length(values) / 2);
	return (length(values) % 2) ? values[middle] : int((values[middle - 1] + values[middle]) / 2);
}

function promote(candidate, direct_ms, proxy_ms, reason) {
	const target = adaptiveEntryTarget(candidate);
	if (!target || learned_by_target[target.key])
		return;
	const entry = {
		target: target.value,
		target_type: target.type,
		added_at: time(),
		last_seen: candidate.last_seen,
		direct_ms: direct_ms || 0,
		proxy_ms,
		observations: candidate.observations,
		reason
	};
	push(learned, entry);
	learned_by_target[target.key] = entry;
	learned_lru[target.key] = ++lru_clock;
	deleteCandidate(target.key);
	evictOldest();
	learned_dirty = true;
	writeRules();
	persistLearned(true);
}

function finishUnsuccessfulProbe(candidate) {
	if (candidate.probe_attempts < MAX_UNSUCCESSFUL_PROBES)
		return;
	const target = adaptiveEntryTarget(candidate);
	if (target)
		deleteCandidate(target.key);
}

function candidateHasPriority(candidate, selected) {
	if (!selected)
		return true;
	if (candidate.fast_failures !== selected.fast_failures)
		return candidate.fast_failures > selected.fast_failures;
	if (candidate.last_seen !== selected.last_seen)
		return candidate.last_seen > selected.last_seen;
	if (candidate.observations !== selected.observations)
		return candidate.observations > selected.observations;
	return candidate.next_probe < selected.next_probe;
}

function selectCandidate(now) {
	let selected = null;
	for (let key, candidate in candidates) {
		if (candidate.observations < settings.min_observations && !candidate.fast_failures)
			continue;
		if (now < candidate.next_probe || now - candidate.last_seen > 3600)
			continue;
		if (candidateHasPriority(candidate, selected))
			selected = candidate;
	}
	return selected;
}

function probeCandidate() {
	const now = time();
	if (now - last_probe < settings.probe_interval)
		return;

	const candidate = selectCandidate(now);
	if (!candidate)
		return;

	last_probe = now;
	candidate.last_probe = now;
	candidate.probe_attempts++;
	let backoff = settings.probe_interval;
	for (let i = 1; i < candidate.probe_attempts && i < 8; i++)
		backoff *= 2;
	if (backoff > 86400)
		backoff = 86400;
	candidate.next_probe = now + backoff;
	let direct = [], proxy = [];
	const target = adaptiveEntryTarget(candidate);
	if (!target) {
		finishUnsuccessfulProbe(candidate);
		return;
	}
	for (let i = 0; i < settings.probe_samples; i++) {
		const direct_value = target.type === 'domain' ?
			domainDelay(DIRECT_TAG, target.value) : ipDelay(probePort('direct'), target);
		if (direct_value)
			push(direct, direct_value);
		const proxy_value = target.type === 'domain' ?
			domainDelay(ADAPTIVE_TAG, target.value) : ipDelay(probePort('proxy'), target);
		if (proxy_value)
			push(proxy, proxy_value);
	}
	probe_count++;

	const direct_ms = median(direct);
	const proxy_ms = median(proxy);
	candidate.direct_ms = direct_ms || 0;
	candidate.proxy_ms = proxy_ms || 0;
	if (!proxy_ms) {
		finishUnsuccessfulProbe(candidate);
		return;
	}

	const required_successes = int((settings.probe_samples + 1) / 2);
	if (length(proxy) < required_successes) {
		finishUnsuccessfulProbe(candidate);
		return;
	}
	if (!direct_ms) {
		promote(candidate, null, proxy_ms, 'direct_failed');
		return;
	}
	if (length(direct) < required_successes || direct_ms < settings.direct_slow_ms) {
		finishUnsuccessfulProbe(candidate);
		return;
	}

	const improvement = direct_ms - proxy_ms;
	const percent = int(improvement * 100 / direct_ms);
	if (improvement >= settings.min_improvement_ms && percent >= settings.min_improvement_percent)
		promote(candidate, direct_ms, proxy_ms, 'proxy_faster');
	else
		finishUnsuccessfulProbe(candidate);
}

function cleanupCandidates() {
	const now = time();
	if (now - last_cleanup < 3600)
		return;
	last_cleanup = now;

	for (let key, candidate in candidates)
		if (now - candidate.last_seen > CANDIDATE_MAX_IDLE)
			deleteCandidate(key);
}

if (system(`/bin/mkdir -p ${shellQuote(RUN_DIR)} ${shellQuote('/etc/homeproxy/adaptive')}`) !== 0)
	exit(1);
loadLearned();
initFailureLog();
if (!writeRules())
	exit(1);
if (learned_dirty && !persistLearned(true))
	exit(1);
if (PREPARE_ONLY)
	exit(0);
writeStatus(true);

sleep(5000);
while (true) {
	paused_for_load = settings.max_load && currentLoad() >= settings.max_load;
	if (!paused_for_load) {
		pollConnections();
		pollFastFailures();
		probeCandidate();
	}
	cleanupCandidates();
	persistLearned(false);
	writeStatus(false);
	sleep(settings.poll_interval * 1000);
}
