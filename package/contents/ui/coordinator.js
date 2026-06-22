/*
 * Plasma Gnome Pager — coordinator.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Cross-instance coordination for dynamic workspaces.
 *
 * The virtual-desktop SET is GLOBAL (only the *current* desktop differs per output), so dynamic-
 * workspace management must be a SINGLE global behaviour. plasmashell runs every panel in ONE QML
 * engine and a `.pragma library` is instantiated ONCE per engine, so the module state below is SHARED
 * across all pager instances — the only pure-QML way to coordinate them (no private imports, no C++).
 * It provides: (1) SETTING SYNC — the enabled flag + name prefix are ONE global value, published to
 * every instance (which mirrors it into its own config) so a toggle on ANY panel applies everywhere;
 * (2) SINGLE-WRITER ELECTION — exactly one present instance (lowest token) issues the KWin add/remove,
 * so two panels never double-add then trim (the "flash"); the pure decision is Logic.electDynamicWriter.
 * If the shared-engine assumption ever failed, each instance would seed/own its own global and elect
 * itself — the per-instance behaviour, degraded but never crashing.
 */
.pragma library
.import "logic.js" as Logic

var _present = {};       // token -> true: instances currently joined (the election candidates)
var _subs = {};          // token -> onSync(enabled, prefix): how to push the global value to each instance
var _enabled = false;    // GLOBAL dynamic-workspaces enabled, synced across all panels
var _prefix = "";        // GLOBAL auto-created-desktop name prefix, synced across all panels
var _haveGlobal = false; // has any instance established the global yet?
var _seq = 0;            // hands out unique, monotonically increasing tokens

// Register this instance. `onSync(enabled, prefix)` is how publish() pushes the global value here.
// Returns the unique token (store it; pass it to leave()/isWriter()). Never returns 0 (the caller's
// "not joined yet" sentinel).
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

// Set the single global setting and push it to EVERY instance (each mirrors it into its own config).
// Called by the panel the user toggled, and once at startup by the first instance to seed the global.
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
// All present instances share the global enabled, so feeding {token: _enabled} to the pure election yields
// the lowest present token when on, or -1 ("nobody") when off.
function isWriter(token) {
    var reg = {};
    for (var t in _present)
        reg[t] = _enabled;
    return Logic.electDynamicWriter(reg) === Number(token);
}
