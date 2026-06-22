/*
 * Plasma Gnome Pager — logic.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Pure, dependency-free branching logic shared by the QML components (no Plasma/Kirigami/Qt deps), so
 * tst_logic.qml exercises every branch headless. `.pragma library` shares one stateless instance and
 * forbids QML ids/context. The deep rationale for each function lives in CLAUDE.md.
 */
.pragma library

// Single source of truth for the QML-side config fallback defaults, each mirroring a main.xml
// <default> (the `?? Logic.DEFAULTS.<key>` guard for the transient-undefined frame). dotSize/pillSize/
// animationDuration 0 are "auto" sentinels; wheelNotchDelta has no schema entry. Frozen = immutable.
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
    animationDuration: 0,        // ms; 0 = follow the theme
    // Appearance
    dotSize: 0,                  // px; 0 = auto (HiDPI themed)
    pillSize: 0,                 // px pill thickness; 0 = auto (match dots)
    spacingFactor: 0.5,
    pillWidthFactor: 3.5,        // pill length / pill thickness (aspect ratio)
    inactiveOpacity: 0.45,
    hoverOpacity: 0.8,
    followThemeColors: true,
    activeColor: "#3daee9",      // used only when followThemeColors is false
    inactiveColor: "#eff0f1",    // used only when followThemeColors is false
    wheelNotchDelta: 120         // angleDelta units per mouse notch (no schema entry)
});

// Coerce to string, mapping null/undefined to "". Shared by the sanitize* functions.
function toStringOrEmpty(value) {
    return (value === undefined || value === null) ? "" : String(value);
}

// Step the active index by delta (+1/-1) → new index in [0, count-1], or -1 for states the caller
// must ignore (empty list, or out-of-range current during a transient add/remove). wrap clamps/wraps.
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

// Resolve the current desktop for one screen (Plasma 6.7 per-output desktops). Prefer the per-screen
// value, else fall back to global — degrades to single-desktop when per-screen data is missing
// (unknown screen, feature off, older Plasma). See CLAUDE.md "Per-screen current desktop".
function resolveCurrentDesktop(perScreen, global) {
    if (perScreen !== undefined && perScreen !== null && perScreen !== "")
        return String(perScreen);
    return global ? String(global) : "";
}

// Accumulate hi-res/touchpad wheel deltas and emit whole notches as integer steps (a wheel reports
// ±120 per notch; touchpads send sub-notch deltas). Returns { steps, remainder } — feed `remainder`
// back as `accumulated` next event so sub-notch motion is not lost.
function accumulateWheel(accumulated, deltaY, threshold) {
    var t = (threshold > 0) ? threshold : DEFAULTS.wheelNotchDelta;
    var total = accumulated + deltaY;
    var steps = (total / t) | 0;                      // truncate toward zero
    return { steps: steps, remainder: total - steps * t };
}

// Opacity: active capsule is full (1.0); inactive dots dim to inactiveOpacity, brighten to
// hoverOpacity on hover (so hovering the active capsule does nothing).
function dotOpacity(active, hovered, inactiveOpacity, hoverOpacity) {
    if (active)
        return 1.0;
    return hovered ? hoverOpacity : inactiveOpacity;
}

// Colour: follow the scheme (theme args) when followTheme, else the user's custom colours. The caller
// passes the live Kirigami.Theme colours so the binding re-evaluates on a colour-scheme change.
function dotColor(active, followTheme, themeActive, themeInactive, customActive, customInactive) {
    if (followTheme)
        return active ? themeActive : themeInactive;
    return active ? customActive : customInactive;
}

// Morph duration: reduce-animations (themeDuration <= 0) always wins → 0; else the requested override,
// else the themed default. So animationDuration can shorten but never re-enable disabled motion.
function effectiveDuration(requested, themeDuration) {
    if (themeDuration <= 0)
        return 0;
    return requested > 0 ? requested : themeDuration;
}

// Desktops per line for `rows` rows, mirroring KWin's grid: columns = ceil(count / rows). 0 for an
// empty set; a missing/<1 `rows` is treated as 1 (single line).
function gridColumns(count, rows) {
    if (count <= 0)
        return 0;
    var r = (rows && rows > 0) ? rows : 1;
    return Math.ceil(count / r);
}

// Split `arr` into consecutive chunks of at most `size` — the row-major grid lines (last may be
// shorter). [] for a null/empty input or size < 1 (transient no-desktops), so a Repeater is empty.
function chunk(arr, size) {
    if (!arr || arr.length === 0 || !size || size < 1)
        return [];
    var out = [];
    for (var i = 0; i < arr.length; i += size)
        out.push(arr.slice(i, i + size));
    return out;
}

// Shallow element-wise equality for arrays of primitives — the compare-before-assign guard: a QML
// var/object property notifies on EVERY reassignment to a fresh reference, so the aggregator keeps the
// OLD reference when contents match to avoid waking downstream on an unchanged snapshot. Flat compare.
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

// Total extent of one reflow line: `count` slots end to end with a uniform `gap`, exactly ONE the
// active capsule (`activeExtent`), the rest dots. Position-independent. `dotSize` for count <= 0
// (transient). Cross axis carries no capsule, so callers pass activeExtent == dotSize there.
function lineExtent(count, dotSize, gap, activeExtent) {
    if (count <= 0)
        return dotSize;
    return activeExtent + (count - 1) * (dotSize + gap);
}

// Dot size that makes ONE full line exactly fill `available` — the algebraic inverse of lineExtent.
// POSITIVE_INFINITY when there is nothing to fit (non-positive available/perLine/denominator) so the
// caller's min(natural, fit) keeps natural. Caller clamps to floor/natural, keeping this Kirigami-free.
function fitDotSize(available, perLine, pillWidthFactor, spacingFactor) {
    if (available <= 0 || perLine <= 0)
        return Number.POSITIVE_INFINITY;
    var denom = pillWidthFactor + (perLine - 1) * (1 + spacingFactor);
    if (denom <= 0)
        return Number.POSITIVE_INFINITY;
    return available / denom;
}

// Title count a tooltip lists before "…and N other windows": 4, but all 5 when exactly 5 (avoids a
// wasted "…and 1 other window" line). Ported from the stock KDE pager.
function windowListMaximum(count) {
    return count === 5 ? 5 : 4;
}

// HTML-escape a window title for the rich-text tooltip (ported from the stock pager): the markup
// chars and the no-break space, but NOT the ordinary space (it must still wrap). Null title → "".
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

// Normalise a user-entered name before the KWin setDesktopName write (vs sanitizeHtml, which escapes
// markup): trim, reject empty/whitespace → "" (no-op sentinel the QML caller guards on), cap length.
function sanitizeDesktopName(input) {
    var s = toStringOrEmpty(input).trim();
    if (s.length === 0)
        return "";
    return s.length > MAX_DESKTOP_NAME_LENGTH ? s.slice(0, MAX_DESKTOP_NAME_LENGTH) : s;
}

// Tooltip membership: a real window (isWindow) that is on all desktops or whose `desktops` lists uuid.
// Null window / missing `desktops` → false (guards transient model state).
function windowIsOnDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    return !!(window.onAll || (window.desktops && window.desktops.indexOf(uuid) !== -1));
}

// Group a flat window snapshot into per-desktop { visible:[title…], minimized:[title…] }, index-aligned
// with `desktopIds`, in model order. Titles stay RAW — i18n "Untitled" + HTML escaping happen in
// main.qml's formatter, keeping this headless. Transient guards: null windows → empty entries; null ids → [].
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
// desktop — main.qml dispatches the single add/remove these return (the read/write split). See CLAUDE.md.

// Does `window` make a desktop NON-EMPTY for dynamic-workspace purposes? Real window only; UNLIKE
// windowIsOnDesktop, an on-all-desktops or skipPager window does NOT count (it would pin every desktop
// occupied). MINIMIZED windows DO count (still occupy their desktop — GNOME + the KWin scripts agree).
function windowOccupiesDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    if (window.onAll || window.skipPager)
        return false;
    return !!(window.desktops && window.desktops.indexOf(uuid) !== -1);
}

// Reduce a window snapshot to a per-desktop occupancy boolean[], index-aligned with `desktopIds`.
// Same transient guards as groupWindowsByDesktop.
function computeDesktopOccupancy(windows, desktopIds) {
    if (!desktopIds || desktopIds.length === 0)
        return [];
    var wins = windows || [];
    var out = [];
    for (var d = 0; d < desktopIds.length; d++) {
        var uuid = desktopIds[d];
        var occupied = false;
        for (var i = 0; i < wins.length; i++) {
            if (windowOccupiesDesktop(wins[i], uuid)) {
                occupied = true;
                break;
            }
        }
        out.push(occupied);
    }
    return out;
}

// The SINGLE dynamic-workspace action, or null for "leave alone" (one per call, so reactive
// re-triggering converges to one trailing empty): 0 trailing empties → add; >=2 → remove the LAST
// (re-trigger trims the rest); else null. Only the trailing run is managed; middle empties left alone.
// Every transient frame is a no-op (null/empty arrays, or occupancy.length !== desktopIds.length).
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

// Name for an auto-created dynamic desktop: "<base> <number>". `fallback` is the i18n default passed
// in from main.qml (keeps this i18n-free); NEVER empty — KWin silently drops createDesktop on an empty name.
function formatDynamicDesktopName(prefix, number, fallback) {
    var base = sanitizeDesktopName(prefix);
    if (base === "")
        base = sanitizeDesktopName(fallback);
    if (base === "")
        base = "Desktop";
    return base + " " + number;
}

// Elect the single dynamic-workspace "writer" among this plasmashell's pager instances: the ENABLED
// instance with the smallest coordinator token (first-registered wins; -1 when none enabled). Why:
// the desktop SET is global, so without one writer two pagers both create on the same fill → a flash.
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

// Should a TasksModel dataChanged(…, roles) trigger a tooltip rebuild? KWin emits dataChanged for
// high-frequency roles the rebuild never reads — notably IsActive on EVERY focus change — so only a
// change to a relevant role rebuilds. An empty/absent `changedRoles` is Qt's "ALL changed" → rebuild.
function dataChangeAffectsRoles(changedRoles, relevantRoles) {
    if (!changedRoles || changedRoles.length === 0)
        return true;
    for (var i = 0; i < changedRoles.length; i++)
        if (relevantRoles.indexOf(changedRoles[i]) !== -1)
            return true;
    return false;
}

/*
 * KWin DBus call SHAPES. Each builder returns a plain { service, path, iface, member, args }, or null
 * when a robustness guard trips. main.qml maps each arg { t, v } to the DBus.* constructor (t: "s"
 * string, "u" uint32, "i" int32, "v" variant). The exact strings/types matter: a wrong one fails
 * SILENTLY (KWin drops the call, no error) — the most upgrade-fragile thing here, so it goes under
 * `make check`. See CLAUDE.md "KWin DBus call SHAPES".
 */
var KWIN_SERVICE = "org.kde.KWin";
var KWIN_VDM_PATH = "/VirtualDesktopManager";
var KWIN_VDM_IFACE = "org.kde.KWin.VirtualDesktopManager";
var DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

// Shared envelope for the createDesktop/removeDesktop/setDesktopName writes (all on KWIN_VDM_IFACE).
// switchSpec is NOT built through this (different iface/member). Key order is load-bearing — tst_logic
// compares specs via JSON.stringify (insertion-order sensitive).
function vdmCall(member, args) {
    return {
        service: KWIN_SERVICE,
        path: KWIN_VDM_PATH,
        iface: KWIN_VDM_IFACE,
        member: member,
        args: args
    };
}

// Switch the (global) current desktop to `uuid` via the VirtualDesktopManager "current" property.
// null for a falsy uuid (transient). The variant arg wraps a PLAIN string (main.qml's "v" case), never
// a wrapped DBus.string — a gadget-wrapped variant is silently rejected.
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

// Append a new desktop at `position` (createDesktop(uint32, string)). `name` is already i18n'd by
// main.qml; `position|0` coerces a transient undefined/NaN count to 0.
function addSpec(position, name) {
    return vdmCall("createDesktop", [{ t: "u", v: position | 0 }, { t: "s", v: String(name) }]);
}

// Remove the desktop `uuid` (removeDesktop(string)). null for a falsy uuid OR count <= 1 — the
// never-remove-last rule via canRemoveDesktop (one source of truth).
function removeSpec(uuid, count) {
    if (!uuid || !canRemoveDesktop(count))
        return null;
    return vdmCall("removeDesktop", [{ t: "s", v: uuid }]);
}

// Rename `uuid` to `name` (setDesktopName(string, string)). The name runs through sanitizeDesktopName;
// null for a falsy uuid or empty sanitized name, so a blank rename is a tested no-op.
function renameSpec(uuid, name) {
    var clean = sanitizeDesktopName(name);
    if (!uuid || !clean)
        return null;
    return vdmCall("setDesktopName", [{ t: "s", v: uuid }, { t: "s", v: clean }]);
}
