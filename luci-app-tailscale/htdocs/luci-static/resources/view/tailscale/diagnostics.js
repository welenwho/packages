/* SPDX-License-Identifier: GPL-3.0-only
 * Copyright (C) 2026 welenwho/packages contributors
 */

'use strict';
'require rpc';
'require ui';
'require view';

const callDiagnostic = rpc.declare({
	object: 'luci.tailscale',
	method: 'diagnostic',
	params: [ 'tool', 'target', 'qtype' ],
	expect: { '': {} }
});

const callStatus = rpc.declare({
	object: 'luci.tailscale',
	method: 'status',
	expect: { '': {} }
});

const TOOLS = [
	[ 'netcheck', _('Network Check') ],
	[ 'ping', _('Tailscale Ping') ],
	[ 'dns_status', _('DNS Status') ],
	[ 'dns_query', _('DNS Query') ],
	[ 'exit_nodes', _('Exit Nodes') ],
	[ 'app_connector', _('App Connector Routes') ],
	[ 'metrics', _('Metrics') ],
	[ 'bugreport', _('Diagnostic Bug Report') ]
];

return view.extend({
	load() {
		return callStatus();
	},

	updateInputs(tool, targetRow, typeRow) {
		targetRow.style.display = (tool === 'ping' || tool === 'dns_query') ? '' : 'none';
		typeRow.style.display = tool === 'dns_query' ? '' : 'none';
	},

	async runDiagnostic(toolSelect, targetInput, typeSelect, button, output) {
		const tool = toolSelect.value;
		button.disabled = true;
		button.classList.add('spinning');
		output.textContent = _('Running diagnostic...');
		try {
			const result = await callDiagnostic(tool, targetInput.value.trim(), typeSelect.value);
			const message = result.output || result.error || _('Command produced no output.');
			output.textContent = result.truncated ? `${message}\n\n${_('Output was truncated.')}` : message;
			if (Number(result.code) !== 0)
				ui.addNotification(null, E('p', {}, String.format(_('Diagnostic command failed with code %s.'), result.code)));
		} catch (error) {
			output.textContent = error.message || String(error);
			ui.addNotification(null, E('p', {}, _('Unable to run diagnostic command.')));
		} finally {
			button.disabled = false;
			button.classList.remove('spinning');
		}
	},

	render(data) {
		const peers = Object.values(data?.status?.Peer || {}).filter(peer => peer.TailscaleIPs?.[0]);
		const listId = 'tailscale-diagnostic-targets';
		const toolSelect = E('select', { class: 'cbi-input-select' },
			TOOLS.map(tool => E('option', { value: tool[0] }, tool[1])));
		const targetInput = E('input', {
			class: 'cbi-input-text',
			type: 'text',
			list: listId,
			placeholder: _('Hostname, Tailscale IP, or DNS name')
		});
		const typeSelect = E('select', { class: 'cbi-input-select' },
			[ 'A', 'AAAA', 'CNAME', 'MX', 'NS', 'PTR', 'SRV', 'TXT' ].map(type => E('option', { value: type }, type)));
		const output = E('pre', {
			class: 'diagnostic-output',
			style: 'min-height:12rem;max-height:38rem;overflow:auto;white-space:pre-wrap'
		}, _('Select a diagnostic and run it.'));
		const button = E('button', {
			class: 'cbi-button cbi-button-action important',
			type: 'button'
		}, _('Run'));
		const targetRow = E('div', { class: 'cbi-value' }, [
			E('label', { class: 'cbi-value-title' }, _('Target')),
			E('div', { class: 'cbi-value-field' }, [ targetInput,
				E('datalist', { id: listId }, peers.map(peer => E('option', {
					value: peer.TailscaleIPs[0],
					label: peer.HostName || peer.DNSName || peer.TailscaleIPs[0]
				}))) ])
		]);
		const typeRow = E('div', { class: 'cbi-value' }, [
			E('label', { class: 'cbi-value-title' }, _('Record Type')),
			E('div', { class: 'cbi-value-field' }, typeSelect)
		]);

		toolSelect.addEventListener('change', () => this.updateInputs(toolSelect.value, targetRow, typeRow));
		button.addEventListener('click', () => this.runDiagnostic(toolSelect, targetInput, typeSelect, button, output));
		this.updateInputs(toolSelect.value, targetRow, typeRow);

		return E([], [
			E('h2', {}, _('Tailscale Diagnostics')),
			E('div', { class: 'cbi-section' }, [
				E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, _('Diagnostic')),
					E('div', { class: 'cbi-value-field' }, toolSelect)
				]),
				targetRow,
				typeRow,
				E('div', { class: 'cbi-value' }, [
					E('div', { class: 'cbi-value-title' }),
					E('div', { class: 'cbi-value-field' }, button)
				])
			]),
			E('div', { class: 'cbi-section' }, [ E('h3', {}, _('Output')), output ])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
