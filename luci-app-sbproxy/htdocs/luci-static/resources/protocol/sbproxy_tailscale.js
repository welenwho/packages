'use strict';
'require network';

network.registerPatternVirtual(/^tailscale[0-9]*$/);

return network.registerProtocol('sbproxy_tailscale', {
	getI18n: function() {
		return _('SBProxy Tailscale');
	},

	getPackageName: function() {
		return 'luci-app-sbproxy';
	},

	getIfname: function() {
		return this._ubus('l3_device') || this._ubus('device') || 'tailscale0';
	},

	isFloating: function() {
		return true;
	},

	isVirtual: function() {
		return true;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return network.getIfnameOf(ifname) === this.getIfname();
	}
});
