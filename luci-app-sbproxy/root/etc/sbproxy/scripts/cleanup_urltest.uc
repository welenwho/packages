#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026
 */

'use strict';

import { cursor } from 'uci';
import { reconcileUrltestNodes } from 'sbproxy';

const config_dir = getenv('SBPROXY_UCI_CONFIG_DIR');
const uci = config_dir ? cursor(config_dir) : cursor();
const config = 'sbproxy';
uci.load(config);

// Closing the proxy must not rewrite the saved node/group selection.
if (uci.get(config, 'config', 'routing_mode') === 'disabled')
	exit(0);

const result = reconcileUrltestNodes(uci, config, (message) => {
	print(sprintf('[URLTEST] %s\n', message));
});

if (result.changed && uci.commit(config) !== true)
	exit(1);
