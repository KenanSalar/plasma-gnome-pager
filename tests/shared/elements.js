// Plasma Gnome Pager — tests/shared/elements.js
//
// SPDX-FileCopyrightText: 2026 Kenan Salar
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared element-location helpers for the component/integration tiers: locate the dot's nested circle /
// tooltip by duck-typing the visual tree (never by child order). `.pragma library`, built on the tree walk.
.pragma library
.import "treewalk.js" as TreeWalk

// The dim circle / morphing capsule Rectangle — uniquely carries both `radius` and `color`.
function isCircle(c) {
    return c.radius !== undefined && c.color !== undefined;
}

// A WorkspaceDot delegate — uniquely carries `modelData` (the desktop UUID) plus an `active` bool.
function isDot(c) {
    return c.modelData !== undefined && typeof c.active === "boolean";
}

// The per-dot tooltip (PlasmaCore.ToolTipArea) — uniquely exposes `mainText`.
function isTooltip(c) {
    return c.mainText !== undefined;
}

// The single circle/capsule Rectangle inside `item` (or null).
function circleOf(item) {
    var found = TreeWalk.collect(item, isCircle);
    return found.length ? found[0] : null;
}

// The tooltip area inside `item` (or null).
function tooltipOf(item) {
    var found = TreeWalk.collect(item, isTooltip);
    return found.length ? found[0] : null;
}

// True when a WorkspaceDot has morphed into the active capsule: major-axis length ≈ indicator.pillWidth
// (passed in so this stays component-agnostic; the strip is horizontal here, so the major axis is width).
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

// The centre point of `item` in `target`'s coordinates — for centring a pointer event or asserting alignment.
function centerOf(item, target) {
    return item.mapToItem(target, item.width / 2, item.height / 2);
}
