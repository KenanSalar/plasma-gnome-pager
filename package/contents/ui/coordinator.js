/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Dynamic workspaces across every pager in plasmashell. The shell runs all panels in one QML engine,
 * which loads a `.pragma library` once, so the state below is shared by them all: the one global
 * setting, and the election of the one instance that adds and removes desktops.
 */
.pragma library
.import "logic.js" as Logic

var _present = {};       // token -> true for each joined instance
var _subs = {};          // token -> its onSync(enabled, prefix)
var _enabled = false;
var _prefix = "";
var _haveGlobal = false; // whether any instance has published yet
var _seq = 0;

/**
 * Registers an instance, which `publish` then reaches through `onSync(enabled, prefix)`.
 * @returns the instance's token, never 0, which callers keep as "not joined yet"
 */
function join(onSync) {
    _seq += 1;
    _present[_seq] = true;
    _subs[_seq] = onSync;
    return _seq;
}

/** Drops an instance from the election and from the sync. */
function leave(token) {
    delete _present[token];
    delete _subs[token];
}

function haveGlobal() { return _haveGlobal; }
function globalEnabled() { return _enabled; }
function globalPrefix() { return _prefix; }

/** Sets the global setting and pushes it to every joined instance. */
function publish(enabled, prefix) {
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
function isWriter(token) {
    var reg = {};
    for (var t in _present)
        reg[t] = _enabled;
    return Logic.electDynamicWriter(reg) === Number(token);
}
