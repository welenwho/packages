/*
 * SPDX-License-Identifier: GPL-2.0-only
 */

'use strict';
'require baseclass';
'require dom';
'require form';
'require poll';
'require rpc';
'require uci';
'require ui';

const callAdaptiveStatus = rpc.declare({
	object: 'luci.sbproxy',
	method: 'adaptive_status',
	expect: { '': {} }
});

const callAdaptiveClear = rpc.declare({
	object: 'luci.sbproxy',
	method: 'adaptive_clear',
	expect: { '': {} }
});

const callAdaptiveRemove = rpc.declare({
	object: 'luci.sbproxy',
	method: 'adaptive_remove',
	params: [ 'target' ],
	expect: { '': {} }
});

function formatTime(epoch) {
	return epoch ? new Date(epoch * 1000).toLocaleString() : '-';
}

function refreshRuntime() {
	const statusContainer = document.getElementById('adaptive_status');
	const learnedContainer = document.getElementById('adaptive_learned');
	const candidatesContainer = document.getElementById('adaptive_candidates');
	const containers = [ statusContainer, learnedContainer, candidatesContainer ].filter(Boolean);
	if (!containers.some((container) => !container.closest('.hidden')))
		return Promise.resolve();
	return L.resolveDefault(callAdaptiveStatus(), {}).then((status) => {
		if (statusContainer)
			dom.content(statusContainer, renderStatus(status));
		if (learnedContainer)
			dom.content(learnedContainer, renderLearned(status));
		if (candidatesContainer)
			dom.content(candidatesContainer, renderCandidates(status));
	});
}

function removeAdaptiveRule(target) {
	ui.showModal(_('Delete learned rule'), [
		E('p', {}, _('Remove %s from automatically learned targets?').format(target)),
		E('div', { class: 'right' }, [
			E('button', { class: 'btn', click: ui.hideModal }, _('Cancel')),
			' ',
			E('button', {
				class: 'btn cbi-button-negative',
				click: () => L.resolveDefault(callAdaptiveRemove(target), { result: false }).then((result) => {
					ui.hideModal();
					if (!result.result)
						ui.addNotification(null, E('p', {}, result.error || _('Failed to delete learned rule.')));
					else
						return refreshRuntime();
				})
			}, _('Delete'))
		])
	]);
}

function clearAdaptiveRules() {
	ui.showModal(_('Clear learned rules'), [
		E('p', {}, _('Remove all automatically learned targets?')),
		E('div', { class: 'right' }, [
			E('button', { class: 'btn', click: ui.hideModal }, _('Cancel')),
			' ',
			E('button', {
				class: 'btn cbi-button-negative',
				click: () => L.resolveDefault(callAdaptiveClear(), { result: false }).then((result) => {
					ui.hideModal();
					if (!result.result)
						ui.addNotification(null, E('p', {}, result.error || _('Failed to clear learned rules.')));
					else
						return refreshRuntime();
				})
			}, _('Clear'))
		])
	]);
}

function targetValue(entry) {
	return entry.target || entry.domain || entry.ip || '-';
}

function targetType(entry) {
	switch (entry.target_type) {
	case 'ipv4': return _('IPv4');
	case 'ipv6': return _('IPv6');
	default: return _('Domain');
	}
}

function renderEntries(entries, dryRun, candidates) {
	if (!entries.length)
		return E('p', {}, _('No targets recorded.'));

	const headings = [
		E('th', { class: 'th' }, _('Target')),
		E('th', { class: 'th' }, _('Type')),
		E('th', { class: 'th' }, _('Direct')),
		E('th', { class: 'th' }, _('Proxy')),
		E('th', { class: 'th' }, _('Observations')),
		E('th', { class: 'th' }, candidates ? _('First seen') : (dryRun ? _('Suggested at') : _('Added at'))),
		E('th', { class: 'th' }, _('Last seen'))
	];
	if (!candidates)
		headings.push(E('th', { class: 'th' }, _('Action')));

	return E('table', { class: 'table' }, [
		E('tr', { class: 'tr table-titles' }, headings),
		...entries.map((entry) => {
			const cells = [
				E('td', { class: 'td' }, targetValue(entry)),
				E('td', { class: 'td' }, targetType(entry)),
				E('td', { class: 'td' }, entry.direct_ms ? '%d ms'.format(entry.direct_ms) : '-'),
				E('td', { class: 'td' }, entry.proxy_ms ? '%d ms'.format(entry.proxy_ms) : '-'),
				E('td', { class: 'td' }, String(entry.observations || 0)),
				E('td', { class: 'td' }, formatTime(candidates ? entry.first_seen : entry.added_at)),
				E('td', { class: 'td' }, formatTime(entry.last_seen))
			];
			if (!candidates)
				cells.push(E('td', { class: 'td' }, E('button', {
					class: 'btn cbi-button cbi-button-remove',
					click: () => removeAdaptiveRule(targetValue(entry))
				}, _('Delete'))));
			return E('tr', { class: 'tr' }, cells);
		})
	]);
}

function renderStatus(status) {
	const running = status.running;
	const state = running ? _('RUNNING') : _('NOT RUNNING');
	const color = running ? 'green' : 'red';

	return [
		E('p', {}, [
			E('strong', { style: 'color:%s'.format(color) }, state),
			' | ',
			_('Tracked connections: %d').format(status.active_connections || 0),
			' | ',
			_('Polls: %d').format(status.poll_count || 0),
			' | ',
			_('Probes: %d').format(status.probe_count || 0)
		]),
		status.baseline_kind && status.target_kind ? E('p', {},
			_('Default path: %s; learned target: %s').format(
				status.baseline_kind === 'direct' ? _('Direct') : _('Proxy'),
				status.target_kind === 'direct' ? _('Direct') : _('Proxy'))) : null,
		status.paused_for_load ? E('p', { class: 'alert-message warning' }, _('Detection paused due to router load.')) : null,
		status.last_error ? E('p', { class: 'alert-message warning' }, status.last_error) : null
	];
}

function renderLearned(status) {
	const learned = (status.learned || []).slice().sort((a, b) =>
		(b.last_seen || 0) - (a.last_seen || 0));
	return [
		E('div', { class: 'right' }, E('button', {
			class: 'btn cbi-button-negative',
			click: clearAdaptiveRules
		}, _('Clear all'))),
		renderEntries(learned, status.dry_run)
	];
}

function renderCandidates(status) {
	const candidates = (status.candidates || []).slice().sort((a, b) =>
		(b.last_seen || 0) - (a.last_seen || 0));
	return renderEntries(candidates, true, true);
}

return baseclass.extend({
	loadStatus() {
		return L.resolveDefault(callAdaptiveStatus(), {});
	},

	addForm(map, parentSection, initialStatus) {
		let s, o;

		map.chain('sbproxy-adaptive');
		parentSection.tab('adaptive', _('Adaptive Routing'));
		o = parentSection.taboption('adaptive', form.SectionValue, '_adaptive',
			form.NamedSection, 'main', 'adaptive');
		o.depends('routing_mode', 'custom');
		o.depends('routing_mode', 'bypass_mainland_china');
		o.depends('routing_mode', 'global');
		o.description = _('Adaptive routing observes only traffic using the final default path. It learns proxy exceptions when the default is direct, and direct exceptions when the default is proxy. Manual routing rules keep priority.');

		s = o.subsection;
		s.uciconfig = 'sbproxy-adaptive';
		s.hidetitle = true;
		s.tab('general', _('General Settings'));
		s.tab('learned', _('Learned Rules'));
		s.tab('candidates', _('Pending Candidates'));
		s.tab('detection', _('Detection'));
		s.tab('performance', _('Performance'));

		o = s.taboption('general', form.DummyValue, '_runtime');
		o.render = function() {
			const container = E('div', { class: 'cbi-section', id: 'adaptive_status' }, renderStatus(initialStatus || {}));
			poll.add(refreshRuntime, 5);
			return container;
		};

		o = s.taboption('learned', form.DummyValue, '_learned');
		o.render = () => E('div', { class: 'cbi-section', id: 'adaptive_learned' },
			renderLearned(initialStatus || {}));

		o = s.taboption('candidates', form.DummyValue, '_candidates');
		o.render = () => E('div', { class: 'cbi-section', id: 'adaptive_candidates' },
			renderCandidates(initialStatus || {}));

		o = s.taboption('general', form.Flag, 'enabled', _('Enable'));
		o.default = o.disabled;
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'dry_run', _('Dry-run'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'allow_global', _('Allow direct exceptions in global mode'),
			_('Required before adaptive routing can create direct exceptions in global proxy mode.'));
		o.default = o.disabled;
		o.rmempty = false;
		o.depends('sbproxy.config.routing_mode', 'global');

		o = s.taboption('general', form.ListValue, 'outbound', _('Comparison proxy outbound'),
			_('Used as the learned target only when the custom routing default outbound is Direct.'));
		o.value('', _('Select an outbound'));
		uci.sections('sbproxy', 'routing_node', (section) => {
			if (section.enabled === '1')
				o.value(section['.name'], section.label || section['.name']);
		});
		o.validate = function(sectionId, value) {
			const routingMode = parentSection.formvalue('config', 'routing_mode');
			const enabled = this.section.formvalue(sectionId, 'enabled');
			const defaultOption = map.lookupOption('default_outbound', 'routing')?.[0];
			const defaultOutbound = defaultOption?.formvalue('routing') ||
				uci.get('sbproxy', 'routing', 'default_outbound');
			if (routingMode === 'custom' && defaultOutbound === 'direct-out' &&
			    enabled === '1' && !value)
				return _('A proxy outbound is required.');
			return true;
		};
		o.depends({
			'sbproxy.config.routing_mode': 'custom',
			'sbproxy.routing.default_outbound': 'direct-out'
		});
		o.rmempty = true;

		o = s.taboption('general', form.ListValue, 'candidate_trigger', _('Candidate trigger'));
		o.value('slow_or_failure', _('Slow connections or failures'));
		o.value('failure_only', _('Failures only'));
		o.default = 'slow_or_failure';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'max_rules', _('Maximum learned rules'));
		o.datatype = 'range(1,100)';
		o.default = '100';
		o.rmempty = false;

		o = s.taboption('general', form.Value, 'max_ip_rules', _('Maximum learned IP rules'));
		o.datatype = 'range(1,100)';
		o.default = '20';
		o.rmempty = false;

		o = s.taboption('general', form.DynamicList, 'exclude_suffix', _('Excluded domain suffixes'));

		o = s.taboption('detection', form.Value, 'slow_seconds', _('Slow connection window (seconds)'));
		o.datatype = 'range(5,300)';
		o.default = '10';
		o.rmempty = false;
		o.depends('candidate_trigger', 'slow_or_failure');

		o = s.taboption('detection', form.Value, 'slow_bytes', _('Maximum bytes during slow window (bytes)'));
		o.datatype = 'range(0,10485760)';
		o.default = '65536';
		o.rmempty = false;
		o.depends('candidate_trigger', 'slow_or_failure');

		o = s.taboption('detection', form.Value, 'min_observations', _('Minimum observations'));
		o.datatype = 'range(1,10)';
		o.default = '2';
		o.rmempty = false;
		o.depends('candidate_trigger', 'slow_or_failure');

		o = s.taboption('detection', form.Value, 'baseline_slow_ms', _('Default path latency threshold (ms)'));
		o.datatype = 'range(100,30000)';
		o.default = '1200';
		o.cfgvalue = function(sectionId) {
			return uci.get('sbproxy-adaptive', sectionId, 'baseline_slow_ms') ||
				uci.get('sbproxy-adaptive', sectionId, 'direct_slow_ms') || this.default;
		};
		o.rmempty = false;

		o = s.taboption('detection', form.Value, 'min_improvement_ms', _('Minimum latency improvement (ms)'));
		o.datatype = 'range(50,30000)';
		o.default = '300';
		o.rmempty = false;

		o = s.taboption('detection', form.Value, 'min_improvement_percent', _('Minimum improvement percentage'));
		o.datatype = 'range(1,99)';
		o.default = '40';
		o.rmempty = false;

		o = s.taboption('performance', form.Value, 'poll_interval', _('Connection polling interval (seconds)'));
		o.datatype = 'range(10,300)';
		o.default = '15';
		o.rmempty = false;

		o = s.taboption('performance', form.Value, 'probe_interval', _('Probe interval (seconds)'));
		o.datatype = 'range(30,86400)';
		o.default = '60';
		o.rmempty = false;

		o = s.taboption('performance', form.Value, 'probe_timeout', _('Probe timeout (ms)'));
		o.datatype = 'range(1000,15000)';
		o.default = '5000';
		o.rmempty = false;

		o = s.taboption('performance', form.ListValue, 'probe_samples', _('Probe samples'));
		o.value('1');
		o.value('2');
		o.value('3');
		o.default = '2';
		o.rmempty = false;

		o = s.taboption('performance', form.Value, 'max_load', _('Pause at 1-minute load average'));
		o.datatype = 'range(0,128)';
		o.default = '2';
		o.rmempty = false;

		return o;
	}
});
