/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The widget's decisions as pure functions, free of Plasma, Qt and i18n so tst_logic.qml runs them
 * headless. Every pager in the process shares this one instance, so it holds no mutable state.
 */
.pragma library

/** Each setting's fallback, mirroring `main.xml`'s defaults, which `tst_logic.qml` holds equal. */
var DEFAULTS = Object.freeze({
    enableScroll: true,
    scrollWrap: false,
    invertScroll: false,
    showTooltips: true,
    showWindowList: true,
    enableAddRemove: true,
    enableRename: true,
    dynamicWorkspaces: false,
    dynamicNamePrefix: "",
    pillClickAction: 0,
    pillClickAnywhere: true,
    animationDuration: 0,
    dotStyle: 0,
    singleLine: false,
    matchDesktopGrid: false,
    dotSize: 0,
    pillSize: 0,
    spacingFactor: 0.5,
    pillWidthFactor: 3.5,
    inactiveOpacity: 0.45,
    hoverOpacity: 0.8,
    showHoverBackground: true,
    hoverBackgroundOpacity: 0.12,
    hoverLengthFactor: 1.0,
    hoverThicknessFactor: 1.0,
    showOccupancy: false,
    occupiedOpacity: 0.7,
    occupancyStyle: 0,
    followThemeColors: true,
    activeColor: "#3daee9",
    inactiveColor: "#eff0f1",
    occupiedColor: "#3daee9",
    hoverBackgroundColor: "#eff0f1",
    wheelNotchDelta: 120         // no schema entry: angleDelta units in one wheel notch
});

/** A settings page's field column in grid units, which slider tracks, fields and hints all line up on. */
var CONFIG_FIELD_WIDTH_UNITS = 18;

/** `occupancyStyle`'s indices; `Filled` recolours the dot, the others draw a marker over a dim one. */
var OCCUPANCY = Object.freeze({ Filled: 0, InnerDot: 1, Ring: 2 });

/** `dotStyle`'s indices; `Ring` has no pill, drawing the other desktops as hollow rings. */
var DOT_STYLE = Object.freeze({ Pill: 0, Ring: 1 });

function isRingStyle(dotStyle) {
    return dotStyle === DOT_STYLE.Ring;
}

/** `pillClickAction`'s indices; every action but `None` toggles a KWin shortcut. */
var PILL_CLICK_ACTION = Object.freeze({ None: 0, ShowDesktop: 1, Overview: 2, Grid: 3 });

function toStringOrEmpty(value) {
    return (value === undefined || value === null) ? "" : String(value);
}

/** `currentIndex` moved `delta` steps, clamped or wrapped into range; -1 when it is out of range itself. */
function stepIndex(currentIndex, count, delta, wrap) {
    if (count <= 0)
        return -1;
    if (currentIndex < 0 || currentIndex >= count)
        return -1;

    var i = currentIndex + delta;
    if (wrap)
        return ((i % count) + count) % count;        // % keeps the dividend's sign
    if (i < 0)
        return 0;
    if (i > count - 1)
        return count - 1;
    return i;
}

/** False at the last desktop, which always stays. */
function canRemoveDesktop(count) {
    return count > 1;
}

/** The last UUID in `ids`, or "" for a missing or empty list. */
function lastDesktopId(ids) {
    if (!ids || ids.length === 0)
        return "";
    return ids[ids.length - 1];
}

/** The screen's own current desktop when KWin reports one, else the global current desktop. */
function resolveCurrentDesktop(perScreen, global) {
    if (perScreen !== undefined && perScreen !== null && perScreen !== "")
        return String(perScreen);
    return global ? String(global) : "";
}

/** Takes whole notches out of the running total as `steps`; feeding `remainder` back adds up a touchpad's. */
function accumulateWheel(accumulated, deltaY, threshold) {
    var t = (threshold > 0) ? threshold : DEFAULTS.wheelNotchDelta;
    var total = accumulated + deltaY;
    var steps = (total / t) | 0;                      // truncates toward zero
    return { steps: steps, remainder: total - steps * t };
}

/** Full when current, then hover, then occupied for a `Filled` marker, else dim. */
function dotOpacity(active, hovered, occupied, style, inactiveOpacity, hoverOpacity, occupiedOpacity) {
    if (active)
        return 1.0;
    if (hovered)
        return hoverOpacity;
    if (occupied && style === OCCUPANCY.Filled)
        return occupiedOpacity;
    return inactiveOpacity;
}

/**
 * The hovered dot after one dot reports a change: the entering dot's index, or -1 only when the dot
 * leaving is the one recorded. Qt delivers the next dot's enter before the last one's leave, so
 * clearing on any leave blinks the hover background off between neighbours.
 */
function nextHoveredIndex(current, index, hovered) {
    if (hovered)
        return index;
    return current === index ? -1 : current;
}

/** The hover background's opacity: the configured one while it is on and hovered, else 0. */
function hoverBackgroundAlpha(enabled, hovered, opacity) {
    return enabled && hovered ? opacity : 0;
}

/** One side's clearance, in lines rather than strips, so a grid of several rows keeps the same margin. */
function hoverPadding(lineThickness, factor) {
    return lineThickness * factor;
}

/**
 * The strip grown by `padding` on each side, then capped at the cell. Insetting the cell instead
 * collapses the background onto the strip as soon as the padding outgrows the room.
 */
function hoverCrossExtent(cell, crossThickness, padding) {
    return Math.min(cell, crossThickness + 2 * padding);
}

/** Active when current, occupied for a `Filled` marker, else inactive; the caller resolves the theme. */
function dotColor(active, occupied, style, activeColor, inactiveColor, occupiedColor) {
    if (active)
        return activeColor;
    if (occupied && style === OCCUPANCY.Filled)
        return occupiedColor;
    return inactiveColor;
}

/** The ring's border width for a dot of `dotSize`, shared by the ring style's outline and the `Ring` marker. */
function ringThickness(dotSize) {
    return Math.max(1, Math.round(dotSize * 0.18));
}

function innerDotDiameter(dotSize) {
    return dotSize * 0.45;
}

/** Whether the dot draws the ring outline: every non-current dot in the ring style, occupied or not. */
function dotHasRing(dotStyle, active) {
    return isRingStyle(dotStyle) && !active;
}

/**
 * Whether the dot's interior is transparent: a non-current dot in the ring style, unless a `Filled`
 * marker fills it. Kept apart from `dotHasRing` so a filled dot keeps its outline.
 */
function dotBodyIsHollow(dotStyle, active, occupied, occupancyStyle) {
    if (!isRingStyle(dotStyle))
        return false;
    if (active)
        return false;
    if (occupied && occupancyStyle === OCCUPANCY.Filled)
        return false;
    return true;
}

/** Whether a ring-style dot has both its outline and a filled interior, the `Filled` marker's look. */
function dotBodyFilled(dotStyle, active, occupied, occupancyStyle) {
    return dotHasRing(dotStyle, active) && !dotBodyIsHollow(dotStyle, active, occupied, occupancyStyle);
}

/** Whether an occupied, non-current dot shows the `Ring` marker; in the ring style the body already is one. */
function ringOverlayVisible(active, occupied, style, dotStyle) {
    return style === OCCUPANCY.Ring && !active && occupied && !isRingStyle(dotStyle);
}

function innerDotVisible(active, occupied, style) {
    return style === OCCUPANCY.InnerDot && !active && occupied;
}

/** 0 while animations are reduced (`themeDuration` is 0), else `requested`, else the theme's. */
function effectiveDuration(requested, themeDuration) {
    if (themeDuration <= 0)
        return 0;
    return requested > 0 ? requested : themeDuration;
}

/** Desktops per line as KWin lays out its grid, `ceil(count / rows)`, a missing or zero `rows` taken as 1. */
function gridColumns(count, rows) {
    if (count <= 0)
        return 0;
    var r = (rows && rows > 0) ? rows : 1;
    return Math.ceil(count / r);
}

/** `arr` split into lines of at most `size`, the last one possibly shorter. */
function chunk(arr, size) {
    if (!arr || arr.length === 0 || !size || size < 1)
        return [];
    var out = [];
    for (var i = 0; i < arr.length; i += size)
        out.push(arr.slice(i, i + size));
    return out;
}

/** Element-wise `===`, to compare before assigning a `var`, which notifies on every new array. */
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

/**
 * One line's length: `count` elements with `gap` between them, one `activeExtent` long and the rest
 * `dotSize`. Across the lines, `activeExtent` is the thicker of a dot and the pill.
 */
function lineExtent(count, dotSize, gap, activeExtent) {
    if (count <= 0)
        return dotSize;
    return activeExtent + (count - 1) * (dotSize + gap);
}

/** `lineExtent` inverted: the dot size a full line fills `available` at; Infinity with nothing to fit. */
function fitDotSize(available, perLine, pillWidthFactor, spacingFactor) {
    if (available <= 0 || perLine <= 0)
        return Number.POSITIVE_INFINITY;
    var denom = pillWidthFactor + (perLine - 1) * (1 + spacingFactor);
    if (denom <= 0)
        return Number.POSITIVE_INFINITY;
    return available / denom;
}

/** Titles listed before "…and N other windows": 4, or all 5 when there are 5, as the stock pager does. */
function windowListMaximum(count) {
    return count === 5 ? 5 : 4;
}

/** Escapes a title for rich text, the no-break space too but not the plain space, which has to wrap. */
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

/** In characters, so a pasted wall of text stays readable in the tooltip. */
var MAX_DESKTOP_NAME_LENGTH = 100;

/** A typed name trimmed and capped, or "" for a blank one, which every caller treats as no change. */
function sanitizeDesktopName(input) {
    var s = toStringOrEmpty(input).trim();
    if (s.length === 0)
        return "";
    return s.length > MAX_DESKTOP_NAME_LENGTH ? s.slice(0, MAX_DESKTOP_NAME_LENGTH) : s;
}

function windowListsDesktop(window, uuid) {
    return !!(window.desktops && window.desktops.indexOf(uuid) !== -1);
}

/** Whether the tooltip lists `window` under `uuid`: a real window on that desktop or on all of them. */
function windowIsOnDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    return !!(window.onAll || windowListsDesktop(window, uuid));
}

/** Each desktop's raw window titles, visible and minimised, index-aligned with `desktopIds`. */
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

/**
 * Whether `window` keeps `uuid` from counting as empty. Unlike in the tooltip, a window on every
 * desktop or hidden from pagers doesn't count, or no desktop could ever be empty; a minimised one does.
 */
function windowOccupiesDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    if (window.onAll || window.skipPager)
        return false;
    return windowListsDesktop(window, uuid);
}

/** One bool per desktop in `desktopIds`, true when any window `occupies(window, uuid)`. */
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

/** Occupancy counting the windows on every screen. */
function computeDesktopOccupancy(windows, desktopIds) {
    return foldDesktopOccupancy(windows, desktopIds, windowOccupiesDesktop);
}

/** Whether `r` is a rect with a size; a missing or empty one means the screen is unknown. */
function isValidScreenRect(r) {
    return !!r && r.width > 0 && r.height > 0;
}

/**
 * `windowOccupiesDesktop`, limited to windows on the screen at `screenRect`. Screens are matched by
 * their top-left corner, since the two sources disagree on size under per-output scaling. An unknown
 * rect on either side counts the window, so an unknown screen hides nothing.
 */
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

/** Occupancy counting only the screen at `screenRect`, or every screen while that rect is unknown. */
function computeDesktopOccupancyForScreen(windows, desktopIds, screenRect) {
    if (!isValidScreenRect(screenRect))
        return computeDesktopOccupancy(windows, desktopIds);
    return foldDesktopOccupancy(windows, desktopIds, function (w, uuid) {
        return windowOccupiesDesktopOnScreen(w, uuid, screenRect);
    });
}

/** The null UUID that puts a window on every activity (libtaskmanager's `NULL_UUID`). */
var ALL_ACTIVITIES = "00000000-0000-0000-0000-000000000000";

/** `TasksModel`'s rule: no activity filters nothing, and an empty list or `ALL_ACTIVITIES` is every one. */
function windowIsOnActivity(window, activity) {
    if (!activity)
        return true;
    var activities = window ? window.activities : null;
    if (!activities || activities.length === 0)
        return true;
    return activities.indexOf(activity) !== -1 || activities.indexOf(ALL_ACTIVITIES) !== -1;
}

function windowsOnActivity(windows, activity) {
    return (windows || []).filter(function (w) {
        return windowIsOnActivity(w, activity);
    });
}

/**
 * The aggregator's three reductions of one window snapshot, each `[]` unless `opts` turns its consumer
 * on. Dynamic workspaces count every activity, since KWin's desktops are shared by all of them (#35);
 * the tooltip and the markers show only the current one.
 * @param opts - `{ windowList, occupancy, dynamic, screenRect, activity }`
 */
function reduceWindowSnapshot(windows, desktopIds, opts) {
    var current = windowsOnActivity(windows, opts.activity);
    return {
        groups: opts.windowList ? groupWindowsByDesktop(current, desktopIds) : [],
        occupancy: opts.dynamic ? computeDesktopOccupancy(windows, desktopIds) : [],
        screenOccupancy: opts.occupancy ? computeDesktopOccupancyForScreen(current, desktopIds, opts.screenRect) : []
    };
}

/**
 * The one change that moves toward a single empty desktop at the end: `{ kind: "add" }`, the last
 * desktop's `{ kind: "remove", uuid }`, or null. Also null while the two arrays differ in length, as
 * they do for a frame after the set changes.
 */
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

/** "<prefix> <number>", never with an empty prefix: KWin drops a `createDesktop` with an empty name. */
function formatDynamicDesktopName(prefix, number, fallback) {
    var base = sanitizeDesktopName(prefix);
    if (base === "")
        base = sanitizeDesktopName(fallback);
    if (base === "")
        base = "Desktop";
    return base + " " + number;
}

/** The smallest token `registry` maps to true, or -1 when none does. */
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

/** Whether a `dataChanged` touched one of `relevantRoles`; an empty `changedRoles` is Qt's "every role". */
function dataChangeAffectsRoles(changedRoles, relevantRoles) {
    if (!changedRoles || changedRoles.length === 0)
        return true;
    for (var i = 0; i < changedRoles.length; i++)
        if (relevantRoles.indexOf(changedRoles[i]) !== -1)
            return true;
    return false;
}

// The write specs: `{ service, path, iface, member, args }`, each argument a `{ t, v }` keyed by its DBus
// signature letter. KWin drops a wrong one without an error, so tst_logic.qml pins each as JSON.
var KWIN_SERVICE = "org.kde.KWin";
var KWIN_VDM_PATH = "/VirtualDesktopManager";
var KWIN_VDM_IFACE = "org.kde.KWin.VirtualDesktopManager";
var DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

// kglobalaccel toggles a KWin shortcut by name, where an effect's own DBus path carries a version
// suffix (`/org/kde/KWin/Effect/Overview/<ver>`) that moves between KWin releases.
var KGLOBALACCEL_SERVICE = "org.kde.kglobalaccel";
var KGLOBALACCEL_KWIN_PATH = "/component/kwin";
var KGLOBALACCEL_COMPONENT_IFACE = "org.kde.kglobalaccel.Component";

function vdmCall(member, args) {
    return {
        service: KWIN_SERVICE,
        path: KWIN_VDM_PATH,
        iface: KWIN_VDM_IFACE,
        member: member,
        args: args
    };
}

/** Sets KWin's global current desktop through its `current` property; null for an empty UUID. */
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

/** Creates a desktop at `position`, where `| 0` turns a count still undefined into 0. */
function addSpec(position, name) {
    return vdmCall("createDesktop", [{ t: "u", v: position | 0 }, { t: "s", v: String(name) }]);
}

/** Removes `uuid`; null for an empty UUID or the last desktop. */
function removeSpec(uuid, count) {
    if (!uuid || !canRemoveDesktop(count))
        return null;
    return vdmCall("removeDesktop", [{ t: "s", v: uuid }]);
}

/** Renames `uuid` to the sanitized `name`; null for an empty UUID or a blank name. */
function renameSpec(uuid, name) {
    var clean = sanitizeDesktopName(name);
    if (!uuid || !clean)
        return null;
    return vdmCall("setDesktopName", [{ t: "s", v: uuid }, { t: "s", v: clean }]);
}

/** Toggles the KWin global shortcut whose unique name is `name`; null for an empty name. */
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

/** Null for `None`. The names are KWin's untranslated DBus identifiers, and its grid is "Grid View". */
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

/** Asked for and an action set; otherwise the default would swallow every left click for nothing. */
function pillClickAnywhereActive(anywhere, action) {
    return !!anywhere && action !== PILL_CLICK_ACTION.None;
}
