// Plasma Gnome Pager — tests/shared/elements.js
//
// SPDX-FileCopyrightText: 2026 Kenan Salar
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared element-location helpers for the component/integration tiers. The dot's circle and
// tooltip are nested inside per-dot ToolTipAreas/Repeaters, so the tests locate them by
// duck-typing the visual tree (never by child order/depth). These predicates + collectors were
// copy-pasted into both tst_workspacedot.qml and tst_workspaceindicator.qml; this is the single
// shared copy. `.pragma library` (parsed once, no QML context), built on the shared tree walk.
.pragma library
.import "treewalk.js" as TreeWalk

// The dim circle / morphing capsule Rectangle — uniquely carries both `radius` and `color`
// (the MouseArea/ToolTipArea have neither).
function isCircle(c) {
    return c.radius !== undefined && c.color !== undefined;
}

// A WorkspaceDot delegate — uniquely carries `modelData` (the desktop UUID) plus the `active`
// bool; no other item in the tree carries both.
function isDot(c) {
    return c.modelData !== undefined && typeof c.active === "boolean";
}

// The per-dot tooltip (PlasmaCore.ToolTipArea) — uniquely exposes `mainText`.
function isTooltip(c) {
    return c.mainText !== undefined;
}

// The single circle/capsule Rectangle inside `item` (or null) — used to assert size/colour/opacity.
function circleOf(item) {
    var found = TreeWalk.collect(item, isCircle);
    return found.length ? found[0] : null;
}

// The tooltip area inside `item` (or null).
function tooltipOf(item) {
    var found = TreeWalk.collect(item, isTooltip);
    return found.length ? found[0] : null;
}
