/*
 * Plasma Gnome Pager — coordinator.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Cross-instance coordination for dynamic workspaces.
 *
 * The virtual-desktop SET is GLOBAL — every monitor/panel shows the same desktops (KWin has no
 * per-output desktop set; only the *current* desktop can differ per output). So dynamic-workspace
 * management must be a SINGLE global behaviour, both in its on/off state and in who acts.
 *
 * plasmashell runs every panel/applet in ONE process and ONE QML engine, and a `.pragma library` is
 * instantiated ONCE per engine — so the module-level state below is SHARED across all pager instances.
 * That is the only pure-QML way to coordinate them (no private imports, no C++ plugin — robustness.md).
 * It provides:
 *   1. SETTING SYNC — the enabled flag and name prefix are ONE global value. publish() records it and
 *      pushes it to every instance via the onSync callback each registered with join(); each instance
 *      mirrors it into its own Plasmoid.configuration, so toggling on ANY panel applies everywhere and
 *      all settings dialogs agree (true global toggle, no per-panel divergence).
 *   2. SINGLE-WRITER ELECTION — among the present instances exactly one (the lowest token) issues the
 *      KWin add/remove, so two panels never double-add then trim (the "flash"). Pure decision:
 *      Logic.electDynamicWriter (unit-tested); this file is the thin shared-state holder
 *      (smoke-tested by tst_coordinator.qml).
 *
 * If the shared-engine assumption ever failed, each instance would seed and own its own global and elect
 * itself — i.e. the per-instance behaviour — degraded, never crashing.
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
        } catch (e) {
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
