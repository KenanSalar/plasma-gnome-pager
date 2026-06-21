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
 * management must be a SINGLE global behaviour. Without it, two pagers (one per monitor) both see the
 * last desktop fill and BOTH issue createDesktop; the surplus is then trimmed back — the visible
 * "flash" of the dots/pill, and inconsistent auto-naming.
 *
 * plasmashell runs every panel/applet in ONE process and ONE QML engine, and a `.pragma library` is
 * instantiated ONCE per engine — so the module-level state below is SHARED across all pager instances.
 * That is the only pure-QML way to coordinate them (no private imports, no C++ plugin — robustness.md).
 * It provides:
 *   - a registry (token -> enabled) from which exactly ONE "writer" is elected (Logic.electDynamicWriter),
 *     so only that instance creates/removes desktops (kills the flash, makes the behaviour global);
 *   - a shared name prefix (the last ENABLED instance wins) so auto-created desktop NAMES are consistent
 *     and configuring the prefix on ANY panel applies everywhere (the requested cross-panel sync).
 *
 * If the shared-engine assumption ever failed, each instance would simply elect itself and act alone
 * (today's per-instance behaviour) — degraded, never crashing. The election itself is the pure
 * Logic.electDynamicWriter, unit-tested in tst_logic.qml; this file is the thin shared-state holder
 * (smoke-tested by tst_coordinator.qml).
 */
.pragma library
.import "logic.js" as Logic

var _registry = {};      // coordinator token -> feature-enabled(bool); SHARED across pager instances
var _sharedPrefix = "";  // last prefix set by an ENABLED instance — synced naming across panels
var _seq = 0;            // hands out unique tokens

// Register this instance; returns its unique token (store it, pass it back to the calls below).
function join() {
    _seq += 1;
    _registry[_seq] = false;
    return _seq;
}

// Deregister on destruction so a removed panel stops counting toward the election.
function leave(token) {
    delete _registry[token];
}

// Publish this instance's current config. Only an ENABLED instance contributes the shared prefix, so a
// panel with the feature off never overrides the naming chosen on the panels that use it.
function configure(token, enabled, prefix) {
    _registry[token] = !!enabled;
    if (enabled)
        _sharedPrefix = prefix;
}

// Is THIS instance the single elected writer (the lowest-token enabled instance)?
function isWriter(token) {
    return Logic.electDynamicWriter(_registry) === Number(token);
}

// The prefix the writer should use for auto-created desktops (synced across panels). "" = the caller's
// i18n default (main.qml passes the localized "Desktop" into Logic.formatDynamicDesktopName).
function prefix() {
    return _sharedPrefix;
}
