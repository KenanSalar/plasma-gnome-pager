/*
 * Plasma Gnome Pager — logic.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
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
 * Single source of truth for the QML-side config defaults. Each config key mirrors the matching
 * contents/config/main.xml <default> and is the fallback the QML uses when a key reads back
 * `undefined` (a freshly-added schema, a removed/re-added widget). Referenced by main.qml's
 * `?? Logic.DEFAULTS.<key>` guards and by the WorkspaceIndicator/WorkspaceDot property defaults,
 * so the same literal is no longer written three times and cannot drift between them. main.xml
 * stays the SCHEMA source; this is the QML mirror. (`wheelNotchDelta` is the one exception — a
 * shared non-config constant with NO main.xml entry, kept here alongside the other shared values;
 * WorkspaceIndicator reads it via Logic.DEFAULTS.) The theme/HiDPI-derived render fallbacks
 * (dotSize → Kirigami.Units, the theme colours) are NOT here — they are intentionally different
 * from the hex schema defaults and live in the components. `Object.freeze` keeps this one shared
 * (.pragma library) instance immutable. `dotSize`/`animationDuration` 0 are the "auto" sentinels.
 */
var DEFAULTS = Object.freeze({
    // Behaviour (General group)
    enableScroll: true,
    scrollWrap: false,
    showTooltips: true,
    showWindowList: true,        // list the windows open on a desktop in its tooltip
    enableAddRemove: true,
    enableRename: true,          // offer "Rename Current Desktop…" in the right-click menu
    animationDuration: 0,        // ms; 0 = follow the theme (Kirigami.Units.longDuration)
    // Appearance group
    dotSize: 0,                  // px; 0 = auto (HiDPI themed size, resolved in the indicator)
    spacingFactor: 0.5,
    pillWidthFactor: 3.5,
    inactiveOpacity: 0.45,
    hoverOpacity: 0.8,
    followThemeColors: true,
    activeColor: "#3daee9",      // Breeze highlight; used only when followThemeColors is false
    inactiveColor: "#eff0f1",    // Breeze text; used only when followThemeColors is false
    // Interaction (non-config shared constant; no main.xml entry)
    wheelNotchDelta: 120         // QWheelEvent angleDelta units per mouse notch
});

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
 * Resolve the current desktop for one screen. Plasma 6.7's "switch desktops independently for each
 * screen" (kwinrc PerOutputVirtualDesktops) lets each output show a different current desktop, read
 * via VirtualDesktopInfo.currentDesktopByScreenName(name): `perScreen` is that value (a UUID string,
 * or undefined/null/"" when there is no per-screen info — an unknown screen name, the feature off,
 * or an older Plasma without the API). `global` is VirtualDesktopInfo.currentDesktop (the global /
 * active-output current). Prefer the per-screen value when present, else fall back to the global one,
 * so the widget degrades to its single-desktop behaviour whenever per-screen data is missing.
 */
function resolveCurrentDesktop(perScreen, global) {
    if (perScreen !== undefined && perScreen !== null && perScreen !== "")
        return String(perScreen);
    return global ? String(global) : "";
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
 * Colour for a dot/capsule. When `followTheme` is true the element follows the colour scheme
 * (active → `themeActive`, inactive → `themeInactive`); otherwise it uses the user's custom
 * `customActive` / `customInactive`. The caller passes the live Kirigami.Theme colours in as the
 * theme args so the QML binding still tracks them and re-evaluates on a colour-scheme change.
 */
function dotColor(active, followTheme, themeActive, themeInactive, customActive, customInactive) {
    if (followTheme)
        return active ? themeActive : themeInactive;
    return active ? customActive : customInactive;
}

/**
 * Resolve the morph animation duration. `requested` is the user's configured value (0 = auto);
 * `themeDuration` is Kirigami.Units.longDuration (0 when "reduce animations" is on). Returns 0
 * whenever the theme says animations are off (reduce-animations always wins), otherwise the
 * requested override, or the themed default when no override is set (requested <= 0).
 */
function effectiveDuration(requested, themeDuration) {
    if (themeDuration <= 0)
        return 0;                                     // reduce-animations wins
    return requested > 0 ? requested : themeDuration; // override, else themed default
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

/**
 * Dot size that makes ONE full reflow line exactly fill `available` along the major axis — the
 * inverse of lineExtent's major-axis form. A line of `perLine` slots (one capsule + the rest dots,
 * uniform gaps) measures dotSize · (pillWidthFactor + (perLine - 1)·(1 + spacingFactor)); solving
 * that for dotSize at length `available` gives available / denom. Returns POSITIVE_INFINITY (an
 * unbounded "no constraint") when there is nothing to fit — a non-positive `available` (the
 * pre-layout frame where width/height is still 0), no slots (perLine <= 0), or a non-positive
 * denominator — so the caller's min(naturalDotSize, fit) simply keeps the natural size. The caller
 * clamps the result to a legibility floor and to the natural size, which keeps this Kirigami-free
 * (the floor/natural are themed values) and unit-testable. Used by WorkspaceIndicator to shrink the
 * dots/pill to fit a crowded panel instead of overflowing onto the neighbouring widgets.
 */
function fitDotSize(available, perLine, pillWidthFactor, spacingFactor) {
    if (available <= 0 || perLine <= 0)
        return Number.POSITIVE_INFINITY;             // nothing to fit -> caller keeps natural
    var denom = pillWidthFactor + (perLine - 1) * (1 + spacingFactor);
    if (denom <= 0)
        return Number.POSITIVE_INFINITY;             // degenerate factors -> no upper bound
    return available / denom;
}

/**
 * How many window titles a tooltip lists before collapsing the rest into an "…and N other windows"
 * line — the stock KDE pager's rule (applets/pager/qml/main.qml::generateWindowList): show 4, but
 * show all 5 when there are exactly 5, since "…and 1 other window" would waste a line for no gain.
 */
function windowListMaximum(count) {
    return count === 5 ? 5 : 4;
}

/**
 * HTML-escape a window title for the rich-text tooltip (ported verbatim from the stock pager's
 * sanitize()). Titles are arbitrary user/app strings, so `<`, `>`, `&`, quotes and the no-break
 * space must be entity-encoded or they would corrupt the <ul><li> markup the formatter builds.
 * Coerces non-strings (a transient null/undefined title) to "" so the caller never throws.
 */
function sanitizeHtml(input) {
    var table = {
        ">": "&gt;",
        "<": "&lt;",
        "&": "&amp;",
        "'": "&apos;",
        "\"": "&quot;",
        "\u00a0": "&nbsp;"
    };
    return String(input === undefined || input === null ? "" : input).replace(/[<>&'"\u00a0]/g, function (c) {
        return table[c];
    });
}

/**
 * Normalise a user-entered desktop name before the KWin `setDesktopName` DBus write (distinct from
 * sanitizeHtml above, which escapes markup): coerce a null/undefined/non-string to "", trim
 * surrounding whitespace, reject an empty/whitespace-only name by returning "" (the same no-op
 * sentinel convention as lastDesktopId), and cap an absurd length so the name stays sane in the
 * tooltip/markup. The QML caller does `if (!clean) return;` before issuing the call.
 */
function sanitizeDesktopName(input) {
    if (input === undefined || input === null)
        return "";
    var s = String(input).trim();
    if (s.length === 0)
        return "";
    var MAX = 100;
    return s.length > MAX ? s.slice(0, MAX) : s;
}

/**
 * Group a flat window list into per-desktop title lists, index-aligned with `desktopIds` (parallel
 * to desktopNames). `windows` is the snapshot the QML aggregator materialises from TasksModel — each
 * element { title, minimized, onAll, isWindow, desktops:[uuid…] }. For each desktop id it returns
 * { visible: [title…], minimized: [title…] } in model order: a window belongs to a desktop when it
 * is a real window AND (it is on all desktops OR its `desktops` list contains that id); minimized
 * windows go in their own bucket (the stock pager lists them under a separate header). Titles are
 * kept RAW — the i18n "Untitled" substitution and HTML escaping happen in main.qml's formatter (this
 * stays pure/headless-testable). Guards the transient states: a null/empty `windows` still yields one
 * empty entry per desktop, and a null/empty `desktopIds` (desktopIds can be [] for a frame —
 * robustness.md) yields [].
 */
function groupWindowsByDesktop(windows, desktopIds) {
    if (!desktopIds || desktopIds.length === 0)
        return [];
    var wins = windows || [];
    var out = [];
    for (var d = 0; d < desktopIds.length; d++) {
        var uuid = desktopIds[d];
        var visible = [];
        var minimized = [];
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (!w || !w.isWindow)
                continue;
            var here = w.onAll || (w.desktops && w.desktops.indexOf(uuid) !== -1);
            if (!here)
                continue;
            if (w.minimized)
                minimized.push(w.title);
            else
                visible.push(w.title);
        }
        out.push({ visible: visible, minimized: minimized });
    }
    return out;
}
