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
 * Coerce a value to a string, mapping a null/undefined to "" (so callers never throw on a
 * transient absent value). Anything else goes through String() unchanged (0 → "0", false →
 * "false"). Shared by the sanitize* functions, which both need this exact "absent → empty,
 * else stringify" rule. NOT used by resolveCurrentDesktop, whose prefer/fallback semantics
 * differ (it excludes "" from the prefer branch and uses truthiness for the global one).
 */
function toStringOrEmpty(value) {
    return (value === undefined || value === null) ? "" : String(value);
}

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
    var t = (threshold > 0) ? threshold : DEFAULTS.wheelNotchDelta;
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
    return toStringOrEmpty(input).replace(/[<>&'"\u00a0]/g, function (c) {
        return table[c];
    });
}

// Cap (chars) on a user-entered desktop name, so an absurd name stays sane in the tooltip/markup.
var MAX_DESKTOP_NAME_LENGTH = 100;

/**
 * Normalise a user-entered desktop name before the KWin `setDesktopName` DBus write (distinct from
 * sanitizeHtml above, which escapes markup): coerce a null/undefined/non-string to "", trim
 * surrounding whitespace, reject an empty/whitespace-only name by returning "" (the same no-op
 * sentinel convention as lastDesktopId), and cap an absurd length so the name stays sane in the
 * tooltip/markup. The QML caller does `if (!clean) return;` before issuing the call.
 */
function sanitizeDesktopName(input) {
    var s = toStringOrEmpty(input).trim();
    if (s.length === 0)
        return "";
    return s.length > MAX_DESKTOP_NAME_LENGTH ? s.slice(0, MAX_DESKTOP_NAME_LENGTH) : s;
}

/**
 * Membership test for groupWindowsByDesktop: does this window belong on the desktop `uuid`?
 * True only for a real window (`isWindow`) that is either on all desktops (`onAll`) or whose
 * `desktops` list contains `uuid`. A null/undefined window or a missing `desktops` list yields
 * false (guards the transient model state). Returns a strict boolean.
 */
function windowIsOnDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    return !!(window.onAll || (window.desktops && window.desktops.indexOf(uuid) !== -1));
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
 * Dynamic workspaces (GNOME-style).
 *
 * GNOME keeps exactly one empty workspace at the end: populate the last one and a new empty appears;
 * empty the others and they collapse away. The functions below are the PURE decision layer for that
 * (no Plasma deps) — main.qml feeds them a window snapshot + the live desktop ids and dispatches the
 * single add/remove they return, letting `vdi` report the resulting state (the read/write split).
 * Default OFF; see DEFAULTS.dynamicWorkspaces / dynamicNamePrefix.
 */

/**
 * Does `window` make a desktop NON-EMPTY for dynamic-workspace purposes? Real window only, and —
 * unlike windowIsOnDesktop (the tooltip's membership) — an on-all-desktops window does NOT count
 * (it would pin every desktop as occupied, so nothing could ever be empty), nor does a window
 * hidden from the pager (`skipPager`, matching the KWin "Dynamic Workspaces" scripts). MINIMIZED
 * windows DO count (a minimized window still occupies its desktop — GNOME + the KWin scripts agree),
 * so there is intentionally no minimized check here. Returns a strict boolean.
 */
function windowOccupiesDesktop(window, uuid) {
    if (!window || !window.isWindow)
        return false;
    if (window.onAll || window.skipPager)
        return false;
    return !!(window.desktops && window.desktops.indexOf(uuid) !== -1);
}

/**
 * Reduce a flat window snapshot to a per-desktop occupancy boolean[], index-aligned with `desktopIds`
 * (parallel to desktopNames / the tooltip array). `windows` elements are the same shape main.qml
 * materialises from TasksModel — { isWindow, onAll, skipPager, minimized, desktops:[uuid…] } (title is
 * unused here). out[i] is true iff some window windowOccupiesDesktop(w, desktopIds[i]). Guards the
 * transient states exactly like groupWindowsByDesktop: null/empty `desktopIds` → [] (desktopIds can be
 * [] for a frame — robustness.md); null/empty `windows` → all-false, one entry per desktop.
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
 * Decide the SINGLE dynamic-workspace action for the current state, or null for "leave it alone".
 * `occupancy` is computeDesktopOccupancy(...) aligned with `desktopIds`.
 *
 * Returns one of:
 *   { kind: "add" }                  — append an empty desktop at the end
 *   { kind: "remove", uuid: <id> }   — remove that desktop (main.qml issues removeSpec)
 *   null                             — no change
 *
 * The rule, computing ONE action per call so reactive re-triggering converges to a stable fixpoint
 * (always exactly one trailing empty):
 *   - 0 trailing empties   → add (the last desktop is occupied)
 *   - >=2 trailing empties → remove the LAST (trims one; re-trigger trims the rest)
 *   - otherwise            → null (one empty desktop is exactly right; never touch the last one)
 *
 * Empty desktops BETWEEN occupied ones are deliberately left alone (only the trailing run is managed).
 * Guards (every transient frame is a no-op): null arrays, an empty desktop set, or a length mismatch
 * between `occupancy` and `desktopIds` (the occupancy snapshot lags a desktop add/remove by a frame)
 * all return null. Removal reuses canRemoveDesktop so the never-remove-last rule is one source of truth.
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
 * Build the name for an auto-created dynamic desktop: a user-chosen base + " " + its number (so a
 * configured prefix "Workspace" with number 3 → "Workspace 3"). `prefix` is the raw config value
 * (DEFAULTS.dynamicNamePrefix, "" by default); `fallback` is the i18n default base ("Desktop") passed
 * IN from main.qml so this file stays i18n-free. Both prefix and fallback are run through
 * sanitizeDesktopName (trim, cap 100, "" if blank); an all-blank case falls back to the literal
 * "Desktop" so the name is NEVER empty — KWin silently drops createDesktop with an empty name.
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
 * Elect the single "writer" instance for dynamic workspaces among all pager instances in this
 * plasmashell. `registry` maps each instance's coordinator token -> its enabled flag (object keys are
 * strings; values are bools). The writer is the ENABLED instance with the smallest token — first-
 * registered wins, deterministic, and stable as instances join/leave. Returns that token as a Number,
 * or -1 when no instance is enabled.
 *
 * Why: the virtual-desktop SET is global (every monitor shows the same desktops), so two pagers (one
 * per panel) both react to the last desktop filling and BOTH create a desktop — which is then trimmed,
 * the visible "flash". Electing exactly one writer makes the management a single global behaviour (and
 * keeps auto-created naming consistent). Pure here; the shared mutable registry lives in coordinator.js.
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
 * Should a TasksModel `dataChanged(topLeft, bottomRight, roles)` trigger a tooltip rebuild? The
 * window-list aggregator (main.qml) reads only a handful of roles (title/desktops/minimised/isWindow),
 * but KWin emits dataChanged for high-frequency roles it never reads — most notably IsActive on EVERY
 * window-focus change (the losing AND gaining window, X11 and Wayland), plus StackingOrder, Geometry,
 * IsDemandingAttention, the icon. Rebuilding on those regroups + reformats to a byte-identical result,
 * pure waste on an always-on widget. `relevantRoles` is the set of role ints the rebuild actually
 * reads (built from the public taskmanager enum in main.qml, which stays the Plasma-aware caller).
 * Returns true (rebuild) when ANY changed role is relevant, OR when `changedRoles` is empty/absent —
 * Qt defines an empty roles list as "ALL roles changed", so that case must always rebuild. Only a
 * change provably limited to irrelevant roles is skipped, so the tooltip output can never go stale.
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
 * KWin DBus call SHAPES.
 *
 * Each builder below returns a plain, dependency-free *description* of a KWin VirtualDesktopManager
 * call — { service, path, iface, member, args } — or `null` when a robustness guard trips (a
 * transient-empty uuid, the never-remove-last rule, an empty rename). main.qml maps each arg
 * { t, v } to the matching DBus.* constructor (t: "s" string, "u" uint32, "i" int32, "v" variant)
 * and issues the async call (see main.qml::dispatch/toDBusArg). Keeping the SHAPES here — the exact
 * service/path/iface/member and per-arg DBus types — is the whole point: a wrong string or arg type
 * fails SILENTLY (KWin drops the call, no error in QML; see CLAUDE.md's DBus gotcha), and it is the
 * most likely thing to break on a Plasma upgrade. Pure here, they go under `make check`
 * (tst_logic.qml) instead of being verifiable only in a live shell. The i18n desktop name for
 * addSpec is passed IN from main.qml so this file stays i18n-free / headless-testable.
 */
var KWIN_SERVICE = "org.kde.KWin";
var KWIN_VDM_PATH = "/VirtualDesktopManager";
var KWIN_VDM_IFACE = "org.kde.KWin.VirtualDesktopManager";
var DBUS_PROPERTIES_IFACE = "org.freedesktop.DBus.Properties";

/**
 * Build a VirtualDesktopManager DBus call spec — the shared { service, path, iface, member, args }
 * envelope for the createDesktop/removeDesktop/setDesktopName writes (all on KWIN_VDM_IFACE), so the
 * only per-call differences are `member` and `args`. switchSpec is intentionally NOT built through
 * this — it targets a different iface/member (Properties.Set). The key order (service, path, iface,
 * member, args) is load-bearing: tst_logic.qml compares specs via JSON.stringify, which is
 * insertion-order sensitive.
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
 * Switch the (global) current desktop to `uuid`, via the VirtualDesktopManager "current" property.
 * Returns null for a falsy uuid (desktopIds/currentDesktop can be transiently empty — robustness.md).
 * The variant arg wraps a PLAIN string (main.qml's "v" case does `new DBus.variant(v)`), never a
 * wrapped DBus.string — a gadget-wrapped variant is silently rejected (CLAUDE.md DBus gotcha).
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
 * already-i18n'd label from main.qml (kept out of this file). `position|0` coerces a transient
 * undefined/NaN count to 0 so the uint32 arg is always a real integer.
 */
function addSpec(position, name) {
    return vdmCall("createDesktop", [{ t: "u", v: position | 0 }, { t: "s", v: String(name) }]);
}

/**
 * Remove the desktop `uuid` (removeDesktop(string id)). Returns null for a falsy uuid OR when
 * `count <= 1` — the never-remove-last rule, reusing canRemoveDesktop so the guard is one source
 * of truth and tested here.
 */
function removeSpec(uuid, count) {
    if (!uuid || !canRemoveDesktop(count))
        return null;
    return vdmCall("removeDesktop", [{ t: "s", v: uuid }]);
}

/**
 * Rename the desktop `uuid` to `name` (setDesktopName(string id, string name)). The name is run
 * through sanitizeDesktopName (trim, reject empty/whitespace, cap length); returns null for a falsy
 * uuid OR an empty sanitized name, so a blank rename is a tested no-op.
 */
function renameSpec(uuid, name) {
    var clean = sanitizeDesktopName(name);
    if (!uuid || !clean)
        return null;
    return vdmCall("setDesktopName", [{ t: "s", v: uuid }, { t: "s", v: clean }]);
}
