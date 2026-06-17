/*
 * GNOME Workspace Switcher — logic.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Pure, dependency-free branching logic shared by the QML components. Keeping it here
 * (no Plasma/Kirigami/Qt deps) lets tests/unit/tst_logic.qml import and exercise every
 * branch on a bare qt6 + qttest, with no Plasma session — the project's logic tier
 * (see tests/README.md / CLAUDE.md). The QML side stays a thin caller.
 *
 * `.pragma library` shares one stateless instance across all importers (no per-import
 * copy); it forbids referencing QML ids/context — which is exactly the constraint that
 * keeps this file pure.
 */
.pragma library

/**
 * Step the active index by `delta` (+1 next, -1 previous).
 *
 * Returns the new index in [0, count-1], or -1 for any state the caller must ignore:
 * an empty list, or a `currentIndex` that is out of range (e.g. -1 during a transient
 * add/remove, when indexOf(currentDesktop) has not resolved yet). When `wrap` is false
 * the index clamps at the ends (scrolling past the edge is a no-op); when true it wraps
 * with a true modulo so negative deltas behave.
 */
function stepIndex(currentIndex, count, delta, wrap) {
    if (count <= 0)
        return -1;                                   // empty / no desktops
    if (currentIndex < 0 || currentIndex >= count)
        return -1;                                   // unknown / transient / out-of-range current

    var i = currentIndex + delta;
    if (wrap)
        return ((i % count) + count) % count;        // true modulo (handles negatives)
    if (i < 0)
        return 0;                                     // clamp at the start
    if (i > count - 1)
        return count - 1;                            // clamp at the end
    return i;
}

/** Never remove the last desktop — there must always be at least one. */
function canRemoveDesktop(count) {
    return count > 1;
}

/** UUID of the last desktop, or "" when the list is null/empty (guards transient state). */
function lastDesktopId(ids) {
    if (!ids || ids.length === 0)
        return "";
    return ids[ids.length - 1];
}

/**
 * Accumulate high-resolution / touchpad wheel deltas and emit whole "notches" as integer
 * steps. A standard mouse wheel reports ±120 angle units per notch; touchpads report many
 * small deltas that must sum to a notch before stepping. Returns { steps, remainder } —
 * feed `remainder` back in as `accumulated` on the next event so sub-notch motion is not lost.
 */
function accumulateWheel(accumulated, deltaY, threshold) {
    var t = (threshold && threshold > 0) ? threshold : 120;
    var total = accumulated + deltaY;
    var steps = (total / t) | 0;                      // truncate toward zero
    return { steps: steps, remainder: total - steps * t };
}

/**
 * Opacity for a dot/capsule. The active element IS the highlighted capsule, so it is drawn
 * at full strength (1.0); inactive elements are dimmed to `inactiveOpacity` and brighten to
 * `hoverOpacity` on hover. Hover therefore affects inactive dots only — an active capsule is
 * always fully opaque (hovering it changes nothing).
 */
function dotOpacity(active, hovered, inactiveOpacity, hoverOpacity) {
    if (active)
        return 1.0;
    return hovered ? hoverOpacity : inactiveOpacity;
}

/**
 * Desktops per line for a grid of `rows` rows — mirrors KWin's desktop grid, where the column
 * count is derived from the configured row count: columns = ceil(count / rows). Returns 0 for an
 * empty set, and treats a missing/<1 `rows` as 1 (a single line — the default desktop layout).
 */
function gridColumns(count, rows) {
    if (count <= 0)
        return 0;
    var r = (rows && rows > 0) ? rows : 1;
    return Math.ceil(count / r);
}

/**
 * Split `arr` into consecutive chunks of at most `size` — the row-major lines of the grid (line 0
 * is the first `size` desktops, etc.; the last line may be shorter). Returns [] for a null/empty
 * input or a `size` < 1 (the transient no-desktops state), so a Repeater over it is simply empty.
 */
function chunk(arr, size) {
    if (!arr || arr.length === 0 || !size || size < 1)
        return [];
    var out = [];
    for (var i = 0; i < arr.length; i += size)
        out.push(arr.slice(i, i + size));
    return out;
}

/**
 * Total extent of one reflow line of `count` slots laid end to end with a uniform `gap` between
 * every adjacent pair: ONE slot is the active capsule (`activeExtent`), the rest are dots
 * (`dotSize`). The length is position-independent — it does not matter which slot holds the
 * capsule, only that exactly one does. Returns a single `dotSize` for count <= 0 (the transient
 * no-desktops fallback, so the panel cell never collapses). The cross axis carries no capsule,
 * so callers pass `activeExtent === dotSize` there — the degenerate all-dots case
 * (n·dotSize + (n-1)·gap). Used for both the major-axis strip length and the cross thickness.
 */
function lineExtent(count, dotSize, gap, activeExtent) {
    if (count <= 0)
        return dotSize;
    return activeExtent + (count - 1) * (dotSize + gap);
}
