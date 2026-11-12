/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Finds a dot's parts by what they carry, never by child order, which changes with the layout.
 */
.pragma library
.import "treewalk.js" as TreeWalk

/** The capsule Rectangle, the only item carrying both `radius` and `color`. */
function isCircle(c) {
    return c.radius !== undefined && c.color !== undefined;
}

/** A WorkspaceDot, the only item carrying `modelData` and a boolean `active`. */
function isDot(c) {
    return c.modelData !== undefined && typeof c.active === "boolean";
}

/** The dot's ToolTipArea, the only item with `mainText`. */
function isTooltip(c) {
    return c.mainText !== undefined;
}

function circleOf(item) {
    var found = TreeWalk.collect(item, isCircle);
    return found.length ? found[0] : null;
}

/** The circle that is the indicator's own child; every dot's capsule sits deeper. */
function hoverBackgroundOf(indicator) {
    var kids = indicator.children;
    for (var i = 0; i < kids.length; ++i)
        if (isCircle(kids[i]))
            return kids[i];
    return null;
}

function tooltipOf(item) {
    var found = TreeWalk.collect(item, isTooltip);
    return found.length ? found[0] : null;
}

/** Whether `dot` has grown into the pill, measured along a horizontal strip. */
function isCapsule(dot, pillWidth) {
    return Math.abs(dot.width - pillWidth) <= 0.5;
}

function countCapsules(dots, pillWidth) {
    var n = 0;
    for (var i = 0; i < dots.length; ++i)
        if (isCapsule(dots[i], pillWidth))
            ++n;
    return n;
}

function centerOf(item, target) {
    return item.mapToItem(target, item.width / 2, item.height / 2);
}
