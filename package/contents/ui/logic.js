/*
 * Plasma Gnome Pager — logic.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Pure, dependency-free branching logic (no Plasma/Qt deps), headless-tested by tst_logic.qml.
 * `.pragma library`: one stateless instance, no QML ids/context.
 */
.pragma library

// QML-side config fallback defaults (the `?? Logic.DEFAULTS.<key>` guard), mirroring main.xml.
// dotSize/pillSize/animationDuration 0 = "auto" sentinel; wheelNotchDelta has no schema entry.
var DEFAULTS = Object.freeze({
    // Behaviour
    enableScroll: true,
    scrollWrap: false,
    invertScroll: false,         // wheel up → next desktop instead of previous
    showTooltips: true,
    showWindowList: true,
    enableAddRemove: true,
    enableRename: true,
    dynamicWorkspaces: false,    // GNOME-style: auto-keep one empty trailing desktop
    dynamicNamePrefix: "",       // base name for auto-created desktops ("" = i18n default "Desktop")
    pillClickAction: 0,          // what clicking the CURRENT desktop's pill does; see PILL_CLICK_ACTION (0 = None)
    animationDuration: 0,        // ms; 0 = follow the theme
    // Appearance
    dotSize: 0,                  // px; 0 = auto (HiDPI themed)
    pillSize: 0,                 // px pill thickness; 0 = auto (match dots)
    spacingFactor: 0.5,
    pillWidthFactor: 3.5,        // pill length / pill thickness (aspect ratio)
    inactiveOpacity: 0.45,
    hoverOpacity: 0.8,
    showOccupancy: false,        // mark the dots of desktops that hold windows
    occupiedOpacity: 0.7,        // opacity of the occupied marker (all styles); empty < occupied < hover < active
    occupancyStyle: 0,           // HOW an occupied dot is marked; see OCCUPANCY (0 = Filled, mirrors main.xml)
    followThemeColors: true,
    activeColor: "#3daee9",      // used only when followThemeColors is false
    inactiveColor: "#eff0f1",    // used only when followThemeColors is false
    occupiedColor: "#3daee9",    // occupied-marker colour; used only when followThemeColors is false (else theme accent)
    wheelNotchDelta: 120         // angleDelta units per mouse notch (no schema entry)
});

// Occupied-dot indicator styles (showOccupancy on). The int values MIRROR the main.xml occupancyStyle
// choices and the ConfigAppearance combo order, so a stored index always maps to the same style. Every
// style marks the OCCUPIED dot using the occupied colour + occupiedOpacity; they differ only in shape:
//   Filled   — the whole occupied dot is filled with the occupied colour.
//   InnerDot — a small occupied-colour dot drawn on top of an otherwise-dim dot.
//   Ring     — a hollow occupied-colour ring drawn on top of an otherwise-dim dot.
// InnerDot and Ring keep the normal dim dot as their background and add an overlay marker; only Filled
// recolours/brightens the dot body itself.
var OCCUPANCY = Object.freeze({ Filled: 0, InnerDot: 1, Ring: 2 });

// Action taken when the ALREADY-CURRENT desktop's pill is clicked (default None). Int values MIRROR the
// main.xml pillClickAction choices and the ConfigGeneral combo order, so a stored index always maps to the
// same action. Each non-None action TOGGLES a KWin global shortcut (see pillClickSpec); clicking an
// inactive dot still just switches desktops.
var PILL_CLICK_ACTION = Object.freeze({ None: 0, ShowDesktop: 1, Overview: 2, Grid: 3 });

// Coerce to string, mapping null/undefined to "". Shared by the sanitize* functions.
function toStringOrEmpty(value) {
    return (value === undefined || value === null) ? "" : String(value);
}

// Step the active index by delta → new index in [0, count-1], or -1 to ignore (empty/transient). wrap clamps/wraps.
function stepIndex(currentIndex, count, delta, wrap) {
    if (count <= 0)
        return -1;
    if (currentIndex < 0 || currentIndex >= count)
        return -1;

    var i = currentIndex + delta;
    if (wrap)
        return ((i % count) + count) % count;        // true modulo (handles negatives)
    if (i < 0)
        return 0;
    if (i > count - 1)
        return count - 1;
    return i;
}

// Never remove the last desktop — there must always be at least one.
function canRemoveDesktop(count) {
    return count > 1;
}

// UUID of the last desktop, or "" when the list is null/empty (guards transient state).
function lastDesktopId(ids) {
    if (!ids || ids.length === 0)
        return "";
    return ids[ids.length - 1];
}

// Current desktop for one screen (Plasma 6.7 per-output): prefer the per-screen value, else global —
// degrades when the screen is unknown, the feature is off, or Plasma is older.
function resolveCurrentDesktop(perScreen, global) {
    if (perScreen !== undefined && perScreen !== null && perScreen !== "")
        return String(perScreen);
    return global ? String(global) : "";
}

// Accumulate hi-res/touchpad wheel deltas and emit whole notches as integer steps. Returns { steps,
// remainder } — feed `remainder` back as `accumulated` next event so sub-notch motion is not lost.
function accumulateWheel(accumulated, deltaY, threshold) {
    var t = (threshold > 0) ? threshold : DEFAULTS.wheelNotchDelta;
    var total = accumulated + deltaY;
    var steps = (total / t) | 0;                      // truncate toward zero
    return { steps: steps, remainder: total - steps * t };
}

// Opacity of the DOT body (brightest first): active capsule full (1.0); hover brightens to hoverOpacity;
// a Filled-style occupied dot (whose body IS the marker) brightens to occupiedOpacity; else inactiveOpacity.
// InnerDot and Ring keep a dim body — their markers are OVERLAYS that carry occupiedOpacity themselves.
// `occupied` is always false when showOccupancy is off, so the empty look is unchanged.
function dotOpacity(active, hovered, occupied, style, inactiveOpacity, hoverOpacity, occupiedOpacity) {
    if (active)
        return 1.0;
    if (hovered)
        return hoverOpacity;
    if (occupied && style === OCCUPANCY.Filled)
        return occupiedOpacity;
    return inactiveOpacity;
}

// Which colour fills the dot BODY, from three pre-resolved colours (the caller resolves theme-vs-custom):
// the active capsule → activeColor; a Filled-style occupied dot → occupiedColor; otherwise inactiveColor
// (an empty dot, or the dim body under the InnerDot/Ring styles, whose markers are drawn as overlays on top).
function dotColor(active, occupied, style, activeColor, inactiveColor, occupiedColor) {
    if (active)
        return activeColor;
    if (occupied && style === OCCUPANCY.Filled)
        return occupiedColor;
    return inactiveColor;
}

// Ring style: an OCCUPIED inactive dot shows a hollow occupied-colour ring OVERLAY on top of the dim dot (empty/active do not).
function ringOverlayVisible(active, occupied, style) {
    return style === OCCUPANCY.Ring && !active && occupied;
}

// InnerDot style: an OCCUPIED inactive dot shows a small occupied-colour dot OVERLAY in its centre (empty/active do not).
function innerDotVisible(active, occupied, style) {
    return style === OCCUPANCY.InnerDot && !active && occupied;
}

// Morph duration: reduce-animations (themeDuration <= 0) wins → 0; else the override, else the themed default.
function effectiveDuration(requested, themeDuration) {
    if (themeDuration <= 0)
        return 0;
    return requested > 0 ? requested : themeDuration;
}

// Desktops per line, mirroring KWin's grid: columns = ceil(count / rows). 0 for empty; missing/<1 rows → 1.
function gridColumns(count, rows) {
    if (count <= 0)
        return 0;
    var r = (rows && rows > 0) ? rows : 1;
    return Math.ceil(count / r);
}

// Split `arr` into row-major chunks of at most `size` (the grid lines; last may be shorter). [] for null/empty/size<1.
function chunk(arr, size) {
    if (!arr || arr.length === 0 || !size || size < 1)
        return [];
    var out = [];
    for (var i = 0; i < arr.length; i += size)
        out.push(arr.slice(i, i + size));
    return out;
}

// Shallow element-wise equality for arrays of primitives — the aggregator's compare-before-assign
// guard (a QML var property notifies on every reassignment, even to an equal fresh array).
function arraysShallowEqual(a, b) {
    if (a === b)
        return true;
    if (!a || !b || a.length !== b.length)
        return false;
    for (var i = 0; i < a.length; i++)
        if (a[i] !== b[i])
            return false;
    return true;
}

// Total extent of one reflow line: `count` slots with uniform `gap`, exactly ONE active capsule
// (`activeExtent`), the rest dots. `dotSize` for count <= 0. Cross axis passes activeExtent == dotSize.
function lineExtent(count, dotSize, gap, activeExtent) {
    if (count <= 0)
        return dotSize;
    return activeExtent + (count - 1) * (dotSize + gap);
}

// Dot size that makes ONE full line exactly fill `available` — the inverse of lineExtent. +Infinity
// when there's nothing to fit (so the caller's min(natural, fit) keeps natural). Caller clamps.
function fitDotSize(available, perLine, pillWidthFactor, spacingFactor) {
    if (available <= 0 || perLine <= 0)
        return Number.POSITIVE_INFINITY;
    var denom = pillWidthFactor + (perLine - 1) * (1 + spacingFactor);
    if (denom <= 0)
        return Number.POSITIVE_INFINITY;
    return available / denom;
}

// Title count before "…and N other windows": 4, but all 5 when exactly 5 (stock KDE pager rule).
function windowListMaximum(count) {
    return count === 5 ? 5 : 4;
}

// HTML-escape a window title for the rich-text tooltip: markup chars + no-break space, NOT the ordinary space (must wrap).
function sanitizeHtml(input) {
    var table = {
        ">": "&gt;",
        "<": "&lt;",
        "&": "&amp;",
        "'": "&apos;",
        "\"": "&quot;",
        "\u00a0": "&nbsp;"
    };
    return toStringOrEmpty(input).replace(/[<>&'"\u00a0]/g, function (c) {
        return table[c];
    });
}

// Cap (chars) on a user-entered desktop name, so an absurd name stays sane in the tooltip/markup.
var MAX_DESKTOP_NAME_LENGTH = 100;

// Normalise a user-entered name before the setDesktopName write: trim, empty/whitespace → "" (no-op sentinel), cap length.
function sanitizeDesktopName(input) {
    var s = toStringOrEmpty(input).trim();
    if (s.length === 0)
        return "";
    return s.length > MAX_DESKTOP_NAME_LENGTH ? s.slice(0, MAX_DESKTOP_NAME_LENGTH) : s;
}

// Does `window`'s own `desktops` list name `uuid`? The membership primitive shared by the tooltip and
// occupancy predicates below (each adds its own on-all/skipPager handling). Missing list → false.
function windowListsDesktop(window, uuid) {
    return !!(window.desktops && window.desktops.indexOf(uuid) !== -1);
}

// Tooltip membership: a real window that is on-all or whose `desktops` lists uuid. Null/missing → false.
function windowIsOnDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    return !!(window.onAll || windowListsDesktop(window, uuid));
}

// Group a flat window snapshot into per-desktop { visible:[title…], minimized:[title…] }, index-aligned
// with `desktopIds`. Titles stay RAW (i18n + HTML happen in main.qml). Null windows → empty; null ids → [].
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
            if (!windowIsOnDesktop(w, uuid))
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

// Dynamic workspaces (GNOME-style, default OFF): the PURE decision layer keeping one empty trailing
// desktop — main.qml dispatches the single add/remove these return.

// Does `window` make a desktop NON-EMPTY for dynamic workspaces? Real window only; UNLIKE
// windowIsOnDesktop, on-all/skipPager do NOT count (would pin every desktop); minimized DO count.
function windowOccupiesDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    if (window.onAll || window.skipPager)
        return false;
    return windowListsDesktop(window, uuid);
}

// Reduce a window snapshot to a per-desktop occupancy boolean[], index-aligned with `desktopIds`:
// each entry is true when ANY window satisfies the `occupies(window, uuid)` predicate. Null windows →
// all-false; null/empty ids → []. The shared scaffold for the global and per-screen reducers below.
function foldDesktopOccupancy(windows, desktopIds, occupies) {
    if (!desktopIds || desktopIds.length === 0)
        return [];
    var wins = windows || [];
    var out = [];
    for (var d = 0; d < desktopIds.length; d++) {
        var uuid = desktopIds[d];
        var occupied = false;
        for (var i = 0; i < wins.length; i++) {
            if (occupies(wins[i], uuid)) {
                occupied = true;
                break;
            }
        }
        out.push(occupied);
    }
    return out;
}

// Global (screen-agnostic) per-desktop occupancy boolean[], index-aligned with `desktopIds`.
function computeDesktopOccupancy(windows, desktopIds) {
    return foldDesktopOccupancy(windows, desktopIds, windowOccupiesDesktop);
}

// A usable screen rect: present with a positive size. A null/zero rect means "don't know" → callers
// fall back to GLOBAL (screen-agnostic) occupancy rather than hiding windows (robustness.md).
function isValidScreenRect(r) {
    return !!r && r.width > 0 && r.height > 0;
}

// Per-screen occupancy (Plasma 6.7 "switch desktops independently per screen"): a window only marks a
// desktop occupied on the pager whose monitor it is physically on. Extends windowOccupiesDesktop with a
// screen-ORIGIN match (each output has a unique top-left; width/height can differ between the window's
// reported screen rect and the pager's under per-output scaling, so compare (x,y) only — integers, exact).
// NEVER drops a window: an unknown target rect (pager not placed) OR an unknown own screen (e.g. a window
// with no geometry) counts everywhere, degrading to the global behaviour.
function windowOccupiesDesktopOnScreen(window, uuid, screenRect) {
    if (!windowOccupiesDesktop(window, uuid))
        return false;
    if (!isValidScreenRect(screenRect))
        return true;
    var ws = window.screen;
    if (!isValidScreenRect(ws))
        return true;
    return ws.x === screenRect.x && ws.y === screenRect.y;
}

// Per-desktop occupancy boolean[] for ONE pager's screen, index-aligned with `desktopIds`. An unknown
// `screenRect` delegates to computeDesktopOccupancy → the byte-identical GLOBAL array, so single-monitor
// setups and pre-placement frames behave exactly as before (no per-screen difference).
function computeDesktopOccupancyForScreen(windows, desktopIds, screenRect) {
    if (!isValidScreenRect(screenRect))
        return computeDesktopOccupancy(windows, desktopIds);
    return foldDesktopOccupancy(windows, desktopIds, function (w, uuid) {
        return windowOccupiesDesktopOnScreen(w, uuid, screenRect);
    });
}

// The SINGLE dynamic-workspace action, or null (one per call → re-triggering converges to one trailing
// empty): 0 trailing empties → add; >=2 → remove the LAST; else null. Only the trailing run is managed.
// Transient frames no-op (null/empty arrays, or occupancy.length !== desktopIds.length).
function dynamicWorkspacePlan(occupancy, desktopIds) {
    if (!occupancy || !desktopIds)
        return null;
    var n = desktopIds.length;
    if (n === 0 || occupancy.length !== n)
        return null;

    var trailing = 0;
    for (var i = n - 1; i >= 0 && !occupancy[i]; i--)
        trailing++;

    if (trailing === 0)
        return { kind: "add" };
    if (trailing >= 2 && canRemoveDesktop(n))
        return { kind: "remove", uuid: desktopIds[n - 1] };
    return null;
}

// Name for an auto-created desktop: "<base> <number>". NEVER empty — KWin silently drops createDesktop on an empty name.
function formatDynamicDesktopName(prefix, number, fallback) {
    var base = sanitizeDesktopName(prefix);
    if (base === "")
        base = sanitizeDesktopName(fallback);
    if (base === "")
        base = "Desktop";
    return base + " " + number;
}

// Elect the single dynamic-workspace "writer" among the pager instances: the ENABLED instance with the
// smallest coordinator token (-1 when none enabled). Without it two pagers double-create on a fill → flash.
function electDynamicWriter(registry) {
    if (!registry)
        return -1;
    var winner = -1;
    for (var token in registry) {
        if (!registry[token])
            continue;
        var t = Number(token);
        if (winner === -1 || t < winner)
            winner = t;
    }
    return winner;
}

// Should a TasksModel dataChanged(…, roles) trigger a rebuild? Only when a relevant role changed —
// skips the high-frequency IsActive focus churn. Empty/absent `changedRoles` is Qt's "all changed" → yes.
function dataChangeAffectsRoles(changedRoles, relevantRoles) {
    if (!changedRoles || changedRoles.length === 0)
        return true;
    for (var i = 0; i < changedRoles.length; i++)
        if (relevantRoles.indexOf(changedRoles[i]) !== -1)
            return true;
    return false;
}

/*
 * KWin DBus call SHAPES. Each builder returns { service, path, iface, member, args } (or null on a
 * robustness guard); main.qml maps each arg { t, v } to a DBus.* constructor. The exact strings/types
 * matter — a wrong one fails SILENTLY (KWin drops the call), so these are unit-tested.
 */
var KWIN_SERVICE = "org.kde.KWin";
var KWIN_VDM_PATH = "/VirtualDesktopManager";
var KWIN_VDM_IFACE = "org.kde.KWin.VirtualDesktopManager";
var DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

// kglobalaccel's public Component interface: invokeShortcut(uniqueName) TOGGLES a KWin global shortcut.
// Used by the pill-click action — public/stable and avoids the version-suffixed effect DBus paths (e.g.
// /org/kde/KWin/Effect/Overview/<ver>) that break across KWin upgrades. Same session bus as KWin.
var KGLOBALACCEL_SERVICE = "org.kde.kglobalaccel";
var KGLOBALACCEL_KWIN_PATH = "/component/kwin";
var KGLOBALACCEL_COMPONENT_IFACE = "org.kde.kglobalaccel.Component";

// Shared envelope for the createDesktop/removeDesktop/setDesktopName writes (all on KWIN_VDM_IFACE;
// switchSpec differs). Key order is load-bearing — tst_logic compares specs via JSON.stringify.
function vdmCall(member, args) {
    return {
        service: KWIN_SERVICE,
        path: KWIN_VDM_PATH,
        iface: KWIN_VDM_IFACE,
        member: member,
        args: args
    };
}

// Switch the (global) current desktop to `uuid` via the VirtualDesktopManager "current" property (null
// for a falsy uuid). The variant arg wraps a PLAIN string — a wrapped DBus.string is silently rejected.
function switchSpec(uuid) {
    if (!uuid)
        return null;
    return {
        service: KWIN_SERVICE,
        path: KWIN_VDM_PATH,
        iface: DBUS_PROPERTIES_IFACE,
        member: "Set",
        args: [{ t: "s", v: KWIN_VDM_IFACE }, { t: "s", v: "current" }, { t: "v", v: uuid }]
    };
}

// Append a new desktop at `position` (createDesktop(uint32, string)). `position|0` coerces a transient undefined/NaN to 0.
function addSpec(position, name) {
    return vdmCall("createDesktop", [{ t: "u", v: position | 0 }, { t: "s", v: String(name) }]);
}

// Remove the desktop `uuid` (removeDesktop(string)). null for a falsy uuid OR count <= 1 (never-remove-last).
function removeSpec(uuid, count) {
    if (!uuid || !canRemoveDesktop(count))
        return null;
    return vdmCall("removeDesktop", [{ t: "s", v: uuid }]);
}

// Rename `uuid` to `name` (setDesktopName(string, string)) via sanitizeDesktopName; null for falsy uuid / empty name.
function renameSpec(uuid, name) {
    var clean = sanitizeDesktopName(name);
    if (!uuid || !clean)
        return null;
    return vdmCall("setDesktopName", [{ t: "s", v: uuid }, { t: "s", v: clean }]);
}

// Invoke (toggle) a KWin global shortcut by its unique name (invokeShortcut(string)); null for a falsy
// name. Key order is load-bearing — tst_logic compares specs via JSON.stringify.
function invokeShortcutSpec(name) {
    if (!name)
        return null;
    return {
        service: KGLOBALACCEL_SERVICE,
        path: KGLOBALACCEL_KWIN_PATH,
        iface: KGLOBALACCEL_COMPONENT_IFACE,
        member: "invokeShortcut",
        args: [{ t: "s", v: name }]
    };
}

// Map a pill-click action (PILL_CLICK_ACTION) to its KWin shortcut spec, or null for None / any unknown
// value (a safe no-op). The shortcut UNIQUE NAMES are DBus identifiers (verified live) — NEVER i18n-wrapped,
// which is why they live here in the i18n-free logic tier. KWin's name for the "Grid" option is "Grid View".
function pillClickSpec(action) {
    switch (action) {
    case PILL_CLICK_ACTION.ShowDesktop:
        return invokeShortcutSpec("Show Desktop");
    case PILL_CLICK_ACTION.Overview:
        return invokeShortcutSpec("Overview");
    case PILL_CLICK_ACTION.Grid:
        return invokeShortcutSpec("Grid View");
    default:
        return null;
    }
}
