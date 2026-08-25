#!/usr/bin/ucode

'use strict';

import { resolveUrltestNodes } from 'sbproxy';

const sections = {
	alpha: { '.name': 'alpha', '.type': 'node', grouphash: 'sub-a' },
	beta: { '.name': 'beta', '.type': 'node', grouphash: 'sub-a' },
	manual: { '.name': 'manual', '.type': 'node' },
	other: { '.name': 'other', '.type': 'node', grouphash: 'sub-b' }
};

const fakeUci = {
	get: (config, section, option) => {
		if (option)
			return sections[section]?.[option];
		return sections[section]?.['.type'];
	},
	foreach: (config, type, callback) => {
		for (let name in sections)
			if (sections[name]['.type'] === type)
				callback(sections[name]);
	}
};

const nodes = resolveUrltestNodes(fakeUci, 'sbproxy', [ 'manual', 'alpha' ], [ 'sub-a' ]);
if (length(nodes) !== 3 || nodes[0] !== 'manual' || nodes[1] !== 'alpha' || nodes[2] !== 'beta')
	die(sprintf('subscription URLTest expansion failed: %.J\n', nodes));

const other = resolveUrltestNodes(fakeUci, 'sbproxy', [], [ 'sub-b' ]);
if (length(other) !== 1 || other[0] !== 'other')
	die(sprintf('second subscription URLTest expansion failed: %.J\n', other));

printf('URLTest subscription expansion test passed\n');
