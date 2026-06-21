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

// True when a WorkspaceDot has morphed into the active capsule: its major-axis length matches the
// indicator's pillWidth (within half a px). The caller passes indicator.pillWidth so this stays
// component-agnostic. (The strip is horizontal where this is used, so the major axis is width.)
function isCapsule(dot, pillWidth) {
    return Math.abs(dot.width - pillWidth) <= 0.5;
}

// How many of `dots` are the active capsule — exactly one in steady state.
function countCapsules(dots, pillWidth) {
    var n = 0;
    for (var i = 0; i < dots.length; ++i)
        if (isCapsule(dots[i], pillWidth))
            ++n;
    return n;
}

// The centre point of `item` in `target`'s coordinates (a point with .x/.y) — for centring a
// pointer event (mouseClick/mouseMove) on a dot or asserting cross-axis centre alignment.
function centerOf(item, target) {
    return item.mapToItem(target, item.width / 2, item.height / 2);
}
