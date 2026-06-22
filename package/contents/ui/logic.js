/*
 * Plasma Gnome Pager — logic.js
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Pure, dependency-free branching logic shared by the QML components. No Plasma/Kirigami/Qt deps, so
 * tst_logic.qml exercises every branch on bare qt6 + qttest with no Plasma session; the QML side
 * stays a thin caller. `.pragma library` shares one stateless instance across importers and forbids
 * QML ids/context — the constraint that keeps this file pure.
 */
.pragma library

/**
 * Single source of truth for the QML-side config defaults, each mirroring a main.xml <default>. Used
 * as the `?? Logic.DEFAULTS.<key>` fallback when a key reads back undefined (freshly-added schema,
 * removed/re-added widget), so the literal isn't written three times and can't drift. Theme/HiDPI
 * render fallbacks (the auto dotSize, the theme colours) live in the components instead, being
 * intentionally different from the hex schema defaults. `wheelNotchDelta` is a shared constant with
 * no main.xml entry; dotSize/animationDuration 0 are the "auto" sentinels. Object.freeze keeps the
 * shared instance immutable.
 */
var DEFAULTS = Object.freeze({
    // Behaviour (General group)
    enableScroll: true,
    scrollWrap: false,
    invertScroll: false,         // wheel up → next desktop instead of previous
    showTooltips: true,
    showWindowList: true,        // list the windows open on a desktop in its tooltip
    enableAddRemove: true,
    enableRename: true,          // offer "Rename Current Desktop…" in the right-click menu
    dynamicWorkspaces: false,    // GNOME-style: auto-keep exactly one empty trailing desktop
    dynamicNamePrefix: "",       // base name for auto-created desktops ("" = the i18n default "Desktop")
    animationDuration: 0,        // ms; 0 = follow the theme (Kirigami.Units.longDuration)
    // Appearance group
    dotSize: 0,                  // px; 0 = auto (HiDPI themed size, resolved in the indicator)
    pillSize: 0,                 // px; active-pill thickness, 0 = auto (matches the dot size). Sized
                                 // independently of dotSize; pill length = pillSize * pillWidthFactor
    spacingFactor: 0.5,
    pillWidthFactor: 3.5,        // pill length as a multiple of the pill thickness (its aspect ratio)
    inactiveOpacity: 0.45,
    hoverOpacity: 0.8,
    followThemeColors: true,
    activeColor: "#3daee9",      // Breeze highlight; used only when followThemeColors is false
    inactiveColor: "#eff0f1",    // Breeze text; used only when followThemeColors is false
    // Interaction (non-config shared constant; no main.xml entry)
    wheelNotchDelta: 120         // QWheelEvent angleDelta units per mouse notch
});

/**
 * Coerce to string, mapping null/undefined to "" (callers never throw on a transient absent value);
 * everything else through String() unchanged (0 → "0", false → "false"). Shared by the sanitize*
 * functions. NOT used by resolveCurrentDesktop, whose prefer/fallback semantics differ.
 */
function toStringOrEmpty(value) {
    return (value === undefined || value === null) ? "" : String(value);
}

/**
 * Step the active index by delta (+1 next, -1 previous). Returns the new index in [0, count-1], or
 * -1 for states the caller must ignore (empty list, or an out-of-range currentIndex during a
 * transient add/remove). wrap=false clamps at the ends; true wraps with a true modulo.
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
 * Resolve the current desktop for one screen (Plasma 6.7 per-output desktops). `perScreen` is
 * VirtualDesktopInfo.currentDesktopByScreenName(name) — undefined/null/"" when there is no per-screen
 * info (unknown screen, feature off, older Plasma without the API); `global` is the global
 * currentDesktop. Prefer the per-screen value, else fall back to global, so it degrades to
 * single-desktop behaviour whenever per-screen data is missing.
 */
function resolveCurrentDesktop(perScreen, global) {
    if (perScreen !== undefined && perScreen !== null && perScreen !== "")
        return String(perScreen);
    return global ? String(global) : "";
}

/**
 * Accumulate hi-res/touchpad wheel deltas and emit whole notches as integer steps (a mouse wheel
 * reports ±120 per notch; touchpads report sub-notch deltas that must sum to a notch first). Returns
 * { steps, remainder } — feed `remainder` back as `accumulated` next event so sub-notch motion is
 * not lost.
 */
function accumulateWheel(accumulated, deltaY, threshold) {
    var t = (threshold > 0) ? threshold : DEFAULTS.wheelNotchDelta;
    var total = accumulated + deltaY;
    var steps = (total / t) | 0;                      // truncate toward zero
    return { steps: steps, remainder: total - steps * t };
}

/**
 * Opacity for a dot/capsule: the active capsule is full strength (1.0); inactive dots dim to
 * inactiveOpacity and brighten to hoverOpacity on hover (so hovering the active capsule does nothing).
 */
function dotOpacity(active, hovered, inactiveOpacity, hoverOpacity) {
    if (active)
        return 1.0;
    return hovered ? hoverOpacity : inactiveOpacity;
}

/**
 * Colour for a dot/capsule: follow the scheme (the theme args) when followTheme, else the user's
 * custom colours. The caller passes the live Kirigami.Theme colours in so the binding re-evaluates
 * on a colour-scheme change.
 */
function dotColor(active, followTheme, themeActive, themeInactive, customActive, customInactive) {
    if (followTheme)
        return active ? themeActive : themeInactive;
    return active ? customActive : customInactive;
}

/**
 * Resolve the morph duration. `requested` is the user's value (0 = auto); `themeDuration` is
 * Kirigami.Units.longDuration (0 when "reduce animations" is on). Reduce-animations always wins
 * (returns 0); otherwise the requested override, else the themed default (requested <= 0).
 */
function effectiveDuration(requested, themeDuration) {
    if (themeDuration <= 0)
        return 0;                                     // reduce-animations wins
    return requested > 0 ? requested : themeDuration; // override, else themed default
}

/**
 * Desktops per line for `rows` rows — mirrors KWin's grid: columns = ceil(count / rows). 0 for an
 * empty set; a missing/<1 `rows` is treated as 1 (a single line — the default layout).
 */
function gridColumns(count, rows) {
    if (count <= 0)
        return 0;
    var r = (rows && rows > 0) ? rows : 1;
    return Math.ceil(count / r);
}

/**
 * Split `arr` into consecutive chunks of at most `size` — the row-major grid lines (the last may be
 * shorter). [] for a null/empty input or a `size` < 1 (the transient no-desktops state), so a
 * Repeater over it is simply empty.
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
 * Shallow element-wise equality for arrays of primitives. Lets a caller skip a `var` reassignment
 * whose contents are byte-identical: a QML var/object property notifies on EVERY reassignment to a
 * fresh reference (there is no contents compare), so the aggregator keeps the OLD reference when
 * contents match to avoid waking downstream bindings on an unchanged occupancy/tooltip snapshot.
 * Identity/null/length-guarded; flat compare (does not recurse into nested arrays).
 */
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
 * Total extent of one reflow line: `count` slots end to end with a uniform `gap`, exactly ONE slot
 * the active capsule (`activeExtent`), the rest dots (`dotSize`). Position-independent (only that one
 * slot is the capsule). Returns a single `dotSize` for count <= 0 (the transient no-desktops
 * fallback). The cross axis carries no capsule, so callers pass activeExtent == dotSize there. Used
 * for both the major-axis strip length and the cross thickness.
 */
function lineExtent(count, dotSize, gap, activeExtent) {
    if (count <= 0)
        return dotSize;
    return activeExtent + (count - 1) * (dotSize + gap);
}

/**
 * Dot size that makes ONE full line exactly fill `available` on the major axis — the algebraic
 * inverse of lineExtent: a line measures dotSize · (pillWidthFactor + (perLine-1)·(1 +
 * spacingFactor)), so the fit is available / that denominator. Returns POSITIVE_INFINITY when there
 * is nothing to fit (non-positive `available` before layout, perLine <= 0, or a non-positive
 * denominator) so the caller's min(naturalDotSize, fit) keeps the natural size. The caller clamps to
 * a legibility floor and the natural size, keeping this Kirigami-free. Used to shrink the dots/pill
 * to a crowded panel instead of overflowing onto the neighbours.
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
 * How many window titles a tooltip lists before "…and N other windows": show 4, but show all 5 when
 * there are exactly 5 (since "…and 1 other window" would waste a line). Ported from the stock KDE pager.
 */
function windowListMaximum(count) {
    return count === 5 ? 5 : 4;
}

/**
 * HTML-escape a window title for the rich-text tooltip (ported from the stock pager): `<`, `>`, `&`,
 * quotes and the no-break space must be entity-encoded or they corrupt the <ul><li> markup. The
 * ordinary space is NOT escaped (it must still wrap). Coerces a transient null/undefined title to "".
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
    return toStringOrEmpty(input).replace(/[<>&'"\u00a0]/g, function (c) {
        return table[c];
    });
}

// Cap (chars) on a user-entered desktop name, so an absurd name stays sane in the tooltip/markup.
var MAX_DESKTOP_NAME_LENGTH = 100;

/**
 * Normalise a user-entered desktop name before the KWin setDesktopName write (distinct from
 * sanitizeHtml, which escapes markup): coerce to string, trim, reject an empty/whitespace-only name
 * by returning "" (the no-op sentinel), and cap length. The QML caller does `if (!clean) return;`
 * before issuing the call.
 */
function sanitizeDesktopName(input) {
    var s = toStringOrEmpty(input).trim();
    if (s.length === 0)
        return "";
    return s.length > MAX_DESKTOP_NAME_LENGTH ? s.slice(0, MAX_DESKTOP_NAME_LENGTH) : s;
}

/**
 * Tooltip membership: does this window belong on desktop `uuid`? True only for a real window
 * (`isWindow`) that is either on all desktops or whose `desktops` list contains uuid. A null window
 * or a missing `desktops` list yields false (guards the transient model state). Strict boolean.
 */
function windowIsOnDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    return !!(window.onAll || (window.desktops && window.desktops.indexOf(uuid) !== -1));
}

/**
 * Group a flat window snapshot into per-desktop title lists, index-aligned with `desktopIds`. Each
 * element is { title, minimized, onAll, isWindow, desktops:[uuid…] }. Per desktop returns { visible:
 * [title…], minimized:[title…] } in model order; minimized windows go in their own bucket (the stock
 * pager lists them under a separate header). Titles stay RAW — the i18n "Untitled" substitution and
 * HTML escaping happen in main.qml's formatter, so this stays pure/headless-testable. Guards
 * transient state: null/empty windows → one empty entry per desktop; null/empty desktopIds → [].
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

/*
 * Dynamic workspaces (GNOME-style). Keep exactly one empty desktop at the end: populate the last and
 * a new empty appears; empty the others and they collapse. The functions below are the PURE decision
 * layer — main.qml feeds them a window snapshot + the live ids and dispatches the single add/remove
 * they return, letting `vdi` report the resulting state (the read/write split). Default OFF.
 */

/**
 * Does `window` make a desktop NON-EMPTY for dynamic-workspace purposes? Real window only, and —
 * unlike windowIsOnDesktop — an on-all-desktops window does NOT count (it would pin every desktop as
 * occupied, so nothing could ever be empty), nor does a `skipPager` window. MINIMIZED windows DO
 * count (a minimized window still occupies its desktop — GNOME + the KWin scripts agree), so there is
 * intentionally no minimized check. Strict boolean.
 */
function windowOccupiesDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    if (window.onAll || window.skipPager)
        return false;
    return !!(window.desktops && window.desktops.indexOf(uuid) !== -1);
}

/**
 * Reduce a flat window snapshot to a per-desktop occupancy boolean[], index-aligned with `desktopIds`:
 * out[i] is true iff some window windowOccupiesDesktop(w, desktopIds[i]). Guards transient state like
 * groupWindowsByDesktop: null/empty desktopIds → []; null/empty windows → all-false, one per desktop.
 */
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

/**
 * Decide the SINGLE dynamic-workspace action, or null for "leave it alone". `occupancy` is
 * computeDesktopOccupancy(...) aligned with `desktopIds`. Returns { kind:"add" } / { kind:"remove",
 * uuid } / null. The rule (one action per call, so reactive re-triggering converges to exactly one
 * trailing empty):
 *   - 0 trailing empties   → add (the last desktop is occupied)
 *   - >=2 trailing empties → remove the LAST (re-trigger trims the rest)
 *   - otherwise            → null (one trailing empty is right; never touch the last desktop)
 * Only the trailing run is managed — empty MIDDLE desktops are left alone. Every transient frame is a
 * no-op: null arrays, an empty set, or occupancy.length !== desktopIds.length (occupancy lags a
 * desktop add/remove by a frame). Removal reuses canRemoveDesktop (one source of truth).
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
        return { kind: "add" };                                  // last desktop occupied → grow
    if (trailing >= 2 && canRemoveDesktop(n))
        return { kind: "remove", uuid: desktopIds[n - 1] };      // too many trailing empties → trim tail
    return null;
}

/**
 * Build the name for an auto-created dynamic desktop: base + " " + number (prefix "Workspace" + 3 →
 * "Workspace 3"). `prefix` is the raw config value; `fallback` is the i18n default base passed IN
 * from main.qml so this stays i18n-free. Both run through sanitizeDesktopName; an all-blank case
 * falls back to the literal "Desktop" so the name is NEVER empty — KWin silently drops createDesktop
 * with an empty name.
 */
function formatDynamicDesktopName(prefix, number, fallback) {
    var base = sanitizeDesktopName(prefix);
    if (base === "")
        base = sanitizeDesktopName(fallback);
    if (base === "")
        base = "Desktop";
    return base + " " + number;
}

/**
 * Elect the single dynamic-workspace "writer" among all pager instances in this plasmashell.
 * `registry` maps each instance's coordinator token → its enabled flag. The writer is the ENABLED
 * instance with the smallest token (first-registered wins; deterministic and stable as instances
 * join/leave). Returns that token as a Number, or -1 when none is enabled. Why: the desktop SET is
 * global, so without a single writer two pagers both create a desktop on the same fill → trim → a
 * visible flash. The shared mutable registry lives in coordinator.js.
 */
function electDynamicWriter(registry) {
    if (!registry)
        return -1;
    var winner = -1;
    for (var token in registry) {
        if (!registry[token])
            continue;                            // the feature is off on that instance
        var t = Number(token);
        if (winner === -1 || t < winner)
            winner = t;
    }
    return winner;
}

/**
 * Should a TasksModel dataChanged(…, roles) trigger a tooltip rebuild? The aggregator reads only a
 * few roles (title/desktops/minimised/isWindow), but KWin emits dataChanged for high-frequency roles
 * it never reads — most notably IsActive on EVERY window-focus change — and rebuilding on those is
 * pure waste on an always-on widget. `relevantRoles` is the set the rebuild actually reads. Returns
 * true when any changed role is relevant, OR when `changedRoles` is empty/absent (Qt defines an empty
 * roles list as "ALL roles changed", so that case must always rebuild). Only a change provably
 * limited to irrelevant roles is skipped, so the tooltip output can never go stale.
 */
function dataChangeAffectsRoles(changedRoles, relevantRoles) {
    if (!changedRoles || changedRoles.length === 0)
        return true;                                 // Qt: empty roles == ALL roles changed -> rebuild
    for (var i = 0; i < changedRoles.length; i++)
        if (relevantRoles.indexOf(changedRoles[i]) !== -1)
            return true;                             // a role the rebuild reads changed
    return false;                                    // only roles rebuild() never reads -> skip
}

/*
 * KWin DBus call SHAPES. Each builder returns a plain { service, path, iface, member, args }
 * description of a VirtualDesktopManager call, or null when a robustness guard trips (a
 * transient-empty uuid, never-remove-last, an empty rename). main.qml maps each arg { t, v } to the
 * matching DBus.* constructor (t: "s" string, "u" uint32, "i" int32, "v" variant) and issues the
 * async call. Keeping the exact strings/types here is the point: a wrong one fails SILENTLY (KWin
 * drops the call, no error in QML) and is the most likely thing to break on a Plasma upgrade — so
 * they go under `make check` instead of being verifiable only in a live shell. The i18n desktop name
 * for addSpec is passed IN from main.qml so this stays i18n-free.
 */
var KWIN_SERVICE = "org.kde.KWin";
var KWIN_VDM_PATH = "/VirtualDesktopManager";
var KWIN_VDM_IFACE = "org.kde.KWin.VirtualDesktopManager";
var DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

/**
 * The shared { service, path, iface, member, args } envelope for the createDesktop/removeDesktop/
 * setDesktopName writes (all on KWIN_VDM_IFACE), so the only per-call differences are `member` and
 * `args`. switchSpec is intentionally NOT built through this (different iface/member: Properties.Set).
 * The key order is load-bearing: tst_logic compares specs via JSON.stringify (insertion-order sensitive).
 */
function vdmCall(member, args) {
    return {
        service: KWIN_SERVICE,
        path: KWIN_VDM_PATH,
        iface: KWIN_VDM_IFACE,
        member: member,
        args: args
    };
}

/**
 * Switch the (global) current desktop to `uuid` via the VirtualDesktopManager "current" property.
 * null for a falsy uuid (desktopIds/currentDesktop can be transiently empty). The variant arg wraps a
 * PLAIN string (main.qml's "v" case does new DBus.variant(v)), never a wrapped DBus.string — a
 * gadget-wrapped variant is silently rejected.
 */
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

/**
 * Append a new desktop at `position` (createDesktop(uint32 position, string name)). `name` is the
 * already-i18n'd label from main.qml. `position|0` coerces a transient undefined/NaN count to 0.
 */
function addSpec(position, name) {
    return vdmCall("createDesktop", [{ t: "u", v: position | 0 }, { t: "s", v: String(name) }]);
}

/**
 * Remove the desktop `uuid` (removeDesktop(string id)). null for a falsy uuid OR when count <= 1 —
 * the never-remove-last rule, reusing canRemoveDesktop so the guard is one source of truth.
 */
function removeSpec(uuid, count) {
    if (!uuid || !canRemoveDesktop(count))
        return null;
    return vdmCall("removeDesktop", [{ t: "s", v: uuid }]);
}

/**
 * Rename the desktop `uuid` to `name` (setDesktopName(string id, string name)). The name is run
 * through sanitizeDesktopName (trim, reject empty/whitespace, cap length); null for a falsy uuid OR
 * an empty sanitized name, so a blank rename is a tested no-op.
 */
function renameSpec(uuid, name) {
    var clean = sanitizeDesktopName(name);
    if (!uuid || !clean)
        return null;
    return vdmCall("setDesktopName", [{ t: "s", v: uuid }, { t: "s", v: clean }]);
}
