/*
 * Plasma Gnome Pager — coordinator.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Cross-instance coordination for dynamic workspaces. The desktop SET is GLOBAL, so management must be a
 * SINGLE global behaviour: plasmashell runs every panel in ONE QML engine and a `.pragma library` is one
 * instance per engine, so the module state below is SHARED across all pagers (the only pure-QML way — no
 * private imports, no C++). Provides SETTING SYNC + SINGLE-WRITER election (lowest token writes). See CLAUDE.md.
 */
.pragma library
.import "logic.js" as Logic

var _present = {};       // token -> true: instances currently joined (the election candidates)
var _subs = {};          // token -> onSync(enabled, prefix): how to push the global value to each instance
var _enabled = false;    // GLOBAL dynamic-workspaces enabled, synced across all panels
var _prefix = "";        // GLOBAL auto-created-desktop name prefix, synced across all panels
var _haveGlobal = false; // has any instance established the global yet?
var _seq = 0;            // hands out unique, monotonically increasing tokens

// Register this instance. `onSync(enabled, prefix)` is how publish() pushes the global value here. Returns
// the unique token (store it; pass it to leave()/isWriter()). Never 0 (the caller's "not joined" sentinel).
function join(onSync) {
    _seq += 1;
    _present[_seq] = true;
    _subs[_seq] = onSync;
    return _seq;
}

// Deregister on destruction so a removed panel stops counting toward the election and is not notified.
function leave(token) {
    delete _present[token];
    delete _subs[token];
}

function haveGlobal() { return _haveGlobal; }
function globalEnabled() { return _enabled; }
function globalPrefix() { return _prefix; }

// Set the single global setting and push it to EVERY instance. Called by the panel the user toggled, and
// once at startup by the first instance to seed the global.
function publish(enabled, prefix) {
    _enabled = !!enabled;
    _prefix = prefix;
    _haveGlobal = true;
    for (var t in _subs) {
        try {
            _subs[t](_enabled, _prefix);
        } catch (_e) {
            /* an instance torn down mid-iteration: ignore */
        }
    }
}

// Is THIS instance the single writer — the lowest-token present instance, and only when globally enabled?
// Feeding {token: _enabled} to the pure election yields the lowest present token when on, or -1 when off.
function isWriter(token) {
    var reg = {};
    for (var t in _present)
        reg[t] = _enabled;
    return Logic.electDynamicWriter(reg) === Number(token);
}
