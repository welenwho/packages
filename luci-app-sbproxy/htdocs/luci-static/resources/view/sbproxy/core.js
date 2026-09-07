/*
 * SPDX-License-Identifier: GPL-2.0-only
 */

'use strict';
'require dom';
'require rpc';
'require ui';
'require view';

const callCoreStatus = rpc.declare({
	object: 'luci.sbproxy',
	method: 'core_status',
	expect: { '': {} }
});

const callCoreCheckUpdate = rpc.declare({
	object: 'luci.sbproxy',
	method: 'core_check_update',
	expect: { '': {} }
});

const callCoreUpgrade = rpc.declare({
	object: 'luci.sbproxy',
	method: 'core_upgrade',
	params: [ 'target' ],
	expect: { '': {} }
});

const callCoreRollback = rpc.declare({
	object: 'luci.sbproxy',
	method: 'core_rollback',
	expect: { '': {} }
});

const coreErrors = {
	already_rolled_back: _('The rollback core is already installed.'),
	candidate_rejected: _('The downloaded package failed metadata, feature, or configuration validation.'),
	checksum_mismatch: _('The downloaded core package failed SHA-256 verification.'),
	current_version_unknown: _('Unable to determine the installed core package version.'),
	download_failed: _('Unable to download the selected core package.'),
	insufficient_storage: _('Not enough persistent storage is available for this core operation.'),
	invalid_target: _('Invalid core package selection.'),
	not_an_upgrade: _('The selected package is not newer than the installed core.'),
	operation_in_progress: _('Another core operation is already in progress.'),
	release_query_failed: _('Unable to query the SBProxy package release.'),
	rollback_checksum_mismatch: _('The rollback package failed SHA-256 verification.'),
	rollback_download_failed: _('Unable to download the current core package for rollback.'),
	rollback_failed: _('Core rollback failed. Check the core manager log immediately.'),
	rollback_metadata_invalid: _('Rollback metadata is incomplete.'),
	rollback_rejected: _('The rollback package failed metadata, feature, or configuration validation.'),
	rollback_source_unavailable: _('The installed core package is no longer in the trusted release, so a safe rollback cannot be prepared.'),
	rollback_unavailable: _('No rollback package is available.'),
	target_unavailable: _('The selected core package is no longer available.'),
	temporary_directory_failed: _('Unable to create a temporary directory.'),
	unsupported_architecture: _('Core updates are not available for this architecture.'),
	upgrade_and_rollback_failed: _('The new core failed and automatic rollback also failed. Check the core manager log immediately.'),
	upgrade_failed_rolled_back: _('The new core failed to install or start; the previous core was restored.')
};

function formatBytes(bytes) {
	const value = Number(bytes) || 0;
	if (value >= 1024 * 1024)
		return _('%s MiB').format((value / 1024 / 1024).toFixed(1));
	if (value >= 1024)
		return _('%s KiB').format((value / 1024).toFixed(1));
	return _('%s B').format(value);
}

function formatKiB(kib) {
	return _('%s MiB').format(((Number(kib) || 0) / 1024).toFixed(1));
}

function formatDate(value) {
	if (!value)
		return '-';
	const date = new Date(value);
	return isNaN(date.getTime()) ? value : date.toLocaleString();
}

function statusText(active, enabled, disabled) {
	return E('strong', { 'style': 'color:%s'.format(active ? 'green' : 'gray') }, [
		active ? enabled : disabled
	]);
}

function resultMessage(result) {
	if (result?.error_code && coreErrors[result.error_code])
		return coreErrors[result.error_code];
	if (result?.error)
		return result.error;
	if (result?.output)
		return result.output;
	return _('Unknown error.');
}

function statusTable(status) {
	const sourceUrl = status.release_tag ?
		'https://github.com/%s/releases/tag/%s'.format(status.repository, status.release_tag) : null;
	const required = status.required_tags || [];
	const tags = status.tags || [];
	const featuresReady = required.length > 0 && required.every((tag) => tags.includes(tag));
	const rollback = status.rollback_available ?
		_('%s (saved at %s)').format(status.rollback_package_version || status.rollback_version || '-',
			status.rollback_saved_at || '-') : _('Unavailable');
	const rows = [
		[ _('Core version'), status.version || '-' ],
		[ _('Installed package'), status.package_version || '-' ],
		[ _('Architecture'), [ status.system_arch, status.package_arch ].filter(Boolean).join(' / ') || '-' ],
		[ _('SBProxy service'), statusText(status.service_running, _('Running'), _('Stopped')) ],
		[ _('Build features'), tags.length ? tags.join(', ') : '-' ],
		[ _('Required features'), statusText(featuresReady, _('Complete'), _('Missing')) ],
		[ _('Rollback package'), rollback ],
		[ _('Persistent storage available'), formatKiB(status.overlay_available_kb) ],
		[ _('Temporary storage available'), formatKiB(status.tmp_available_kb) ],
		[ _('Package source'), sourceUrl ? E('a', {
			'href': sourceUrl,
			'target': '_blank',
			'rel': 'noreferrer noopener'
		}, [ status.repository ]) : (status.repository || '-') ]
	];
	const table = E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, [ _('Item') ]),
			E('th', { 'class': 'th' }, [ _('Status') ])
		])
	]);
	cbi_update_table(table, rows);
	return table;
}

function featureTable(status) {
	const compiledTags = status.tags || [];
	const features = [
		[ 'with_acme', _('ACME certificates'), _('Server Settings'), true ],
		[ 'with_clash_api', _('Clash API'), _('URLTest and adaptive routing'), true ],
		[ 'with_dhcp', _('DHCP DNS transport'), _('Client DNS settings'), true ],
		[ 'with_gvisor', _('gVisor network stack'), _('Client TUN settings'), true ],
		[ 'with_quic', _('QUIC protocols'), _('Hysteria, Hysteria2, TUIC and QUIC DNS'), true ],
		[ 'with_tailscale', _('Tailscale'), _('Tailscale, HTTPS certificates and DERP'), true ],
		[ 'with_utls', _('uTLS fingerprints'), _('Node TLS settings'), true ],
		[ 'with_wireguard', _('WireGuard endpoint'), _('Node Settings'), true ],
		[ null, _('Memory pressure guard'), _('Client advanced settings'), true ]
	];
	const table = E('table', { 'class': 'table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, [ _('Capability') ]),
			E('th', { 'class': 'th' }, [ _('Compiled') ]),
			E('th', { 'class': 'th' }, [ _('LuCI integration') ])
		])
	]);
	cbi_update_table(table, features.map((feature) => [
		feature[1],
		statusText(feature[0] === null || compiledTags.includes(feature[0]), _('Yes'), _('No')),
		statusText(feature[3], feature[2], feature[2])
	]));
	return table;
}

return view.extend({
	load() {
		return L.resolveDefault(callCoreStatus(), {
			code: 1,
			manager_supported: false,
			error: _('Unable to read core status.')
		});
	},

	showFailure(title, result) {
		ui.showModal(title, [
			E('p', { 'class': 'alert-message error' }, [ resultMessage(result) ]),
			result?.automatic_rollback ?
				E('p', { 'class': 'alert-message warning' }, [
					_('The previous core was restored automatically and SBProxy has been restarted.')
				]) : '',
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn',
					'click': ui.hideModal
				}, [ _('Close') ])
			])
		]);
	},

	showSuccess(title, message) {
		ui.showModal(title, [
			E('p', { 'class': 'alert-message success' }, [ message ]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': () => window.location.reload()
				}, [ _('Refresh status') ])
			])
		]);
	},

	runOperation(title, promise, successMessage) {
		ui.showModal(title, [
			E('p', { 'class': 'spinning' }, [
				_('Downloading, validating and applying the core package. Do not power off the router.')
			])
		]);
		return promise.then((result) => {
			if (result?.code || (!result?.upgraded && !result?.rolled_back))
				return this.showFailure(title, result || {});
			this.showSuccess(title, successMessage.format(result.package_version || '-'));
		}).catch((error) => {
			this.showFailure(title, { error: String(error) });
		});
	},

	confirmOperation(title, message, operation) {
		ui.showModal(title, [
			E('p', {}, [ message ]),
			E('p', { 'class': 'alert-message warning' }, [
				_('SBProxy will be restarted if it is currently running. Network access may pause briefly.')
			]),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn',
					'click': ui.hideModal
				}, [ _('Cancel') ]),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': operation
				}, [ _('Continue') ])
			])
		]);
	},

	render(status) {
		const updateInfo = E('div', { 'class': 'cbi-section-descr' }, [
			_('Check for a newer stable core from the trusted SBProxy package release.')
		]);
		const selector = E('select', {
			'class': 'cbi-input-select',
			'disabled': '',
			'style': 'min-width:18em'
		}, [ E('option', { 'value': '' }, [ _('Check for updates first') ]) ]);
		const upgradeButton = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'disabled': '',
			'click': () => {
				const target = selector.value;
				if (!target)
					return;
				const selected = selector.options[selector.selectedIndex]?.textContent || target;
				this.confirmOperation(_('Upgrade sing-box core'),
					_('Upgrade the sing-box core to %s?').format(selected), () =>
						this.runOperation(_('Upgrade sing-box core'), callCoreUpgrade(target),
							_('The sing-box core was upgraded to %s successfully.')));
			}
		}, [ _('Upgrade') ]);
		const checkButton = E('button', {
			'class': 'btn cbi-button cbi-button-action',
			'disabled': (status.busy || status.manager_supported === false) ? '' : null,
			'click': ui.createHandlerFn(this, () => {
				checkButton.disabled = true;
				dom.content(updateInfo, E('span', { 'class': 'spinning' }, [ _('Checking for updates...') ]));
				return L.resolveDefault(callCoreCheckUpdate(), { code: 1 }).then((result) => {
					if (result.code) {
						dom.content(updateInfo, E('span', { 'style': 'color:red' }, [ resultMessage(result) ]));
						return;
					}
					const newer = (result.assets || []).filter((asset) => asset.relation === 'newer')
						.sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
					dom.content(selector, newer.length ? newer.map((asset) => E('option', {
						'value': asset.filename
					}, [ _('%s · %s · %s').format(asset.package_version,
						formatBytes(asset.size), formatDate(asset.created_at)) ])) :
						E('option', { 'value': '' }, [ _('Already at the latest stable version') ]));
					selector.disabled = newer.length ? false : true;
					upgradeButton.disabled = newer.length ? false : true;
					dom.content(updateInfo, newer.length ?
						_('Latest stable package: %s').format(result.latest_package_version || newer[0].package_version) :
						_('The installed core is already the latest stable package (%s).')
							.format(result.package_version || result.latest_package_version || '-'));
				}).finally(() => {
					checkButton.disabled = false;
				});
			})
		}, [ _('Check for updates') ]);
		const rollbackButton = E('button', {
			'class': 'btn cbi-button cbi-button-negative',
			'disabled': (!status.rollback_available || status.busy || status.manager_supported === false) ? '' : null,
			'click': () => this.confirmOperation(_('Roll back sing-box core'),
				_('Roll back the sing-box core to %s?').format(
					status.rollback_package_version || status.rollback_version || '-'), () =>
					this.runOperation(_('Roll back sing-box core'), callCoreRollback(),
						_('The sing-box core was rolled back to %s successfully.')))
		}, [ _('Roll back') ]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ _('Core Management') ]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Manage the sing-box core used by the client, server and embedded Tailscale services.')
			]),
			E('p', { 'class': 'alert-message warning' }, [
				_('Only sing-box packages built by this project are accepted. Official upstream binaries do not include the SBProxy-specific Tailscale compatibility patches.')
			]),
			status.manager_supported === false ? E('p', { 'class': 'alert-message error' }, [
				_('Core management is not available on this architecture.')
			]) : '',
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('Core Status') ]),
				statusTable(status)
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('Feature Coverage') ]),
				E('div', { 'class': 'cbi-section-descr' }, [
					_('Shows whether each optional core feature is compiled and where SBProxy currently uses it.')
				]),
				featureTable(status)
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('Upgrade') ]),
				updateInfo,
				E('div', { 'style': 'display:flex;gap:.5em;align-items:center;flex-wrap:wrap;margin-top:1em' }, [
					checkButton,
					selector,
					upgradeButton
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ _('Rollback') ]),
				E('div', { 'class': 'cbi-section-descr' }, [
					status.rollback_available ?
						_('One previous verified package is stored locally for rollback.') :
						_('A rollback package will be created automatically before the first managed upgrade.')
				]),
				E('div', { 'style': 'margin-top:1em' }, [ rollbackButton ])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
