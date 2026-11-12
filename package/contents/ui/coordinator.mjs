/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Dynamic workspaces across every pager in plasmashell. The shell runs all panels in one QML engine,
 * which evaluates a module once, so the state below is shared by them all: the one global setting,
 * and the election of the one instance that adds and removes desktops.
 */
import * as Logic from "./logic.mjs";

var _subs = {}; // token -> its onSync(enabled, prefix), one per joined instance
var _enabled = false;
var _prefix = "";
var _haveGlobal = false; // whether any instance has published yet
var _seq = 0;

/**
 * Registers an instance, which `publish` then reaches through `onSync(enabled, prefix)`.
 * @returns the instance's token, never 0, which callers keep as "not joined yet"
 */
export function join(onSync) {
    _seq += 1;
    _subs[_seq] = onSync;
    return _seq;
}

/** Drops an instance from the election and from the sync. */
export function leave(token) {
    delete _subs[token];
}

export function haveGlobal() {
    return _haveGlobal;
}
export function globalEnabled() {
    return _enabled;
}
export function globalPrefix() {
    return _prefix;
}

/** Sets the global setting and pushes it to every joined instance. */
export function publish(enabled, prefix) {
    _enabled = !!enabled;
    _prefix = prefix;
    _haveGlobal = true;
    for (var t in _subs) {
        try {
            _subs[t](_enabled, _prefix);
        } catch (_e) {
            // An instance torn down mid-loop; the others still get the value.
        }
    }
}

/** Whether `token` is the one instance that writes: the lowest joined token, while the setting is on. */
export function isWriter(token) {
    return _enabled && Logic.electDynamicWriter(Object.keys(_subs)) === Number(token);
}
