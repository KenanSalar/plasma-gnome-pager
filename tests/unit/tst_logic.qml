/*
 * Plasma Gnome Pager — tst_logic.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT tests for the pure-JS logic tier (package/contents/ui/logic.js). This file imports
 * the `.js` directly and has NO Plasma/Kirigami dependency, so it runs on a bare qt6 +
 * qttest with no Plasma session — the cheapest, most exhaustive tier for branching logic
 * (clamp/wrap, wheel accumulation, never-remove-last, hover-suppress). The QML callers
 * (WorkspaceDot / WorkspaceIndicator / main.qml) stay thin wrappers around these functions.
 *
 * Run with `make check-unit` (or `make check`).
 */
import QtTest
import "../../package/contents/ui/logic.js" as Logic

TestCase {
    id: testCase
    name: "Logic"

    // --- stepIndex: clamp vs wrap, and the -1 "ignore me" states --------------------
    function test_stepIndex_data() {
        return [
            // wrap across the ends, in both directions and by more than one
            { tag: "wrap-forward-over-end", cur: 2, count: 3, delta: 1, wrap: true, exp: 0 },
            { tag: "wrap-backward-over-start", cur: 0, count: 3, delta: -1, wrap: true, exp: 2 },
            { tag: "wrap-forward-multi", cur: 0, count: 3, delta: 4, wrap: true, exp: 1 },
            { tag: "wrap-backward-multi", cur: 0, count: 3, delta: -4, wrap: true, exp: 2 },

            // clamp at the ends (scrolling past the edge is a no-op step)
            { tag: "clamp-high", cur: 2, count: 3, delta: 1, wrap: false, exp: 2 },
            { tag: "clamp-low", cur: 0, count: 3, delta: -1, wrap: false, exp: 0 },
            { tag: "clamp-high-multi", cur: 1, count: 3, delta: 5, wrap: false, exp: 2 },

            // a normal mid-range step
            { tag: "mid-step", cur: 0, count: 3, delta: 1, wrap: false, exp: 1 },

            // a single desktop: every step stays put, wrap or not
            { tag: "single-clamp-up", cur: 0, count: 1, delta: 1, wrap: false, exp: 0 },
            { tag: "single-wrap-up", cur: 0, count: 1, delta: 1, wrap: true, exp: 0 },
            { tag: "single-wrap-down", cur: 0, count: 1, delta: -1, wrap: true, exp: 0 },

            // states the caller must ignore: empty list, unknown/transient current, OOB current
            { tag: "empty-clamp", cur: -1, count: 0, delta: 1, wrap: false, exp: -1 },
            { tag: "empty-wrap", cur: -1, count: 0, delta: 1, wrap: true, exp: -1 },
            { tag: "unknown-current-clamp", cur: -1, count: 3, delta: 1, wrap: false, exp: -1 },
            { tag: "unknown-current-wrap", cur: -1, count: 3, delta: 1, wrap: true, exp: -1 },
            { tag: "out-of-range-current", cur: 5, count: 3, delta: 1, wrap: false, exp: -1 },
            // the count/current guards run BEFORE the wrap branch, so an out-of-range current is -1
            // even with wrap on; a negative count is the empty-list guard.
            { tag: "out-of-range-current-wrap", cur: 5, count: 3, delta: 1, wrap: true, exp: -1 },
            { tag: "negative-count", cur: 0, count: -2, delta: 1, wrap: false, exp: -1 },

            // delta 0 is a no-op that returns the current index (not -1)
            { tag: "delta-zero-clamp", cur: 1, count: 3, delta: 0, wrap: false, exp: 1 },
            { tag: "delta-zero-wrap", cur: 1, count: 3, delta: 0, wrap: true, exp: 1 }
        ];
    }
    function test_stepIndex(data) {
        compare(Logic.stepIndex(data.cur, data.count, data.delta, data.wrap), data.exp, data.tag);
    }

    // --- canRemoveDesktop: never remove the last one --------------------------------
    function test_canRemoveDesktop_data() {
        return [
            { tag: "zero", count: 0, exp: false },
            { tag: "one", count: 1, exp: false },
            { tag: "two", count: 2, exp: true },
            { tag: "many", count: 9, exp: true },
            { tag: "negative", count: -1, exp: false }
        ];
    }
    function test_canRemoveDesktop(data) {
        compare(Logic.canRemoveDesktop(data.count), data.exp, data.tag);
    }

    // --- lastDesktopId: guard null/empty, else the last UUID ------------------------
    function test_lastDesktopId_data() {
        return [
            { tag: "empty", ids: [], exp: "" },
            { tag: "null", ids: null, exp: "" },
            { tag: "single", ids: ["a"], exp: "a" },
            { tag: "many", ids: ["a", "b", "c"], exp: "c" },
            { tag: "undefined", ids: undefined, exp: "" },
            // the last element is returned RAW (no string coercion), so a non-string id comes back as-is.
            { tag: "non-string-last", ids: [1, 2, 3], exp: 3 }
        ];
    }
    function test_lastDesktopId(data) {
        compare(Logic.lastDesktopId(data.ids), data.exp, data.tag);
    }

    // --- resolveCurrentDesktop: per-screen current, else the global current ----------
    // Plasma 6.7 per-output desktops: prefer the per-screen value when present; fall back to the
    // global current when it's missing — undefined/null (no per-screen API or unknown screen) or ""
    // (transient). Both empty -> "" (the no-source state the indicator treats as no capsule).
    function test_resolveCurrentDesktop_data() {
        return [
            { tag: "per-screen-wins", perScreen: "uuid-screen", global: "uuid-global", exp: "uuid-screen" },
            { tag: "undefined-falls-back", perScreen: undefined, global: "uuid-global", exp: "uuid-global" },
            { tag: "null-falls-back", perScreen: null, global: "uuid-global", exp: "uuid-global" },
            { tag: "empty-falls-back", perScreen: "", global: "uuid-global", exp: "uuid-global" },
            { tag: "both-empty", perScreen: undefined, global: "", exp: "" },
            { tag: "per-screen-no-global", perScreen: "uuid-screen", global: "", exp: "uuid-screen" },
            { tag: "global-undefined", perScreen: undefined, global: undefined, exp: "" },
            { tag: "global-null", perScreen: undefined, global: null, exp: "" },
            // a present (non-undefined/null/"") perScreen is coerced through String(), even a number.
            { tag: "per-screen-number-coerced", perScreen: 42, global: "uuid-global", exp: "42" }
        ];
    }
    function test_resolveCurrentDesktop(data) {
        compare(Logic.resolveCurrentDesktop(data.perScreen, data.global), data.exp, data.tag);
    }

    // --- accumulateWheel: whole notches step, sub-notch motion carries --------------
    function test_accumulateWheel_data() {
        return [
            { tag: "full-notch-down", acc: 0, d: 120, t: 120, steps: 1, rem: 0 },
            { tag: "full-notch-up", acc: 0, d: -120, t: 120, steps: -1, rem: 0 },
            { tag: "half-notch-carries", acc: 0, d: 60, t: 120, steps: 0, rem: 60 },
            { tag: "two-halves-make-a-notch", acc: 60, d: 60, t: 120, steps: 1, rem: 0 },
            { tag: "touchpad-sub-notch", acc: 0, d: 40, t: 120, steps: 0, rem: 40 },
            { tag: "overshoot-carries-remainder", acc: 0, d: 200, t: 120, steps: 1, rem: 80 },
            { tag: "double-notch", acc: 0, d: 240, t: 120, steps: 2, rem: 0 },
            { tag: "threshold-defaults-to-120", acc: 0, d: 120, t: 0, steps: 1, rem: 0 },

            // negative deltas (wheel up / upward touchpad): (total / t) | 0 truncates TOWARD
            // zero, so the step and the carried remainder are both negative — the path the
            // indicator relies on for upward scroll (only positive overshoot was covered before).
            { tag: "negative-overshoot-carries", acc: 0, d: -200, t: 120, steps: -1, rem: -80 },
            { tag: "negative-double-notch", acc: 0, d: -240, t: 120, steps: -2, rem: 0 },
            { tag: "negative-remainder-feeds-back", acc: -80, d: -60, t: 120, steps: -1, rem: -20 },

            // exhaustive: multiple notches in one delta WITH a carried remainder; a non-120 threshold;
            // an absent/negative threshold (both default back to 120); and a zero delta (a no-op that
            // simply carries the running accumulator forward).
            { tag: "two-notches-with-remainder", acc: 0, d: 280, t: 120, steps: 2, rem: 40 },
            { tag: "three-notches", acc: 0, d: 360, t: 120, steps: 3, rem: 0 },
            { tag: "three-notches-with-remainder", acc: 0, d: 400, t: 120, steps: 3, rem: 40 },
            { tag: "non-default-threshold", acc: 0, d: 240, t: 240, steps: 1, rem: 0 },
            { tag: "negative-threshold-defaults-120", acc: 0, d: 120, t: -50, steps: 1, rem: 0 },
            { tag: "undefined-threshold-defaults-120", acc: 0, d: 120, t: undefined, steps: 1, rem: 0 },
            { tag: "delta-zero-noop", acc: 50, d: 0, t: 120, steps: 0, rem: 50 }
        ];
    }
    function test_accumulateWheel(data) {
        const r = Logic.accumulateWheel(data.acc, data.d, data.t);
        compare(r.steps, data.steps, data.tag + " steps");
        fuzzyCompare(r.remainder, data.rem, 0.001, data.tag + " remainder");
    }

    // --- dotOpacity: active is full strength; hover brightens inactive only ---------
    function test_dotOpacity_data() {
        return [
            { tag: "idle", active: false, hovered: false, exp: 0.45 },
            { tag: "hovered", active: false, hovered: true, exp: 0.8 },
            { tag: "active-not-hovered", active: true, hovered: false, exp: 1.0 },
            { tag: "active-and-hovered", active: true, hovered: true, exp: 1.0 }
        ];
    }
    function test_dotOpacity(data) {
        fuzzyCompare(Logic.dotOpacity(data.active, data.hovered, 0.45, 0.8), data.exp, 0.001, data.tag);
    }

    // The opacities are parameters, not constants: a non-default inactive/hover pair flows through
    // for the inactive states, while the active capsule is always 1.0 regardless of either argument.
    function test_dotOpacityCustomRatios() {
        fuzzyCompare(Logic.dotOpacity(false, false, 0.2, 0.9), 0.2, 0.001, "idle uses the given inactiveOpacity");
        fuzzyCompare(Logic.dotOpacity(false, true, 0.2, 0.9), 0.9, 0.001, "hover uses the given hoverOpacity");
        fuzzyCompare(Logic.dotOpacity(true, false, 0.2, 0.9), 1.0, 0.001, "active is full strength, ignoring inactiveOpacity");
        fuzzyCompare(Logic.dotOpacity(true, true, 0.2, 0.9), 1.0, 0.001, "active+hover is full strength, ignoring hoverOpacity");
    }

    // --- dotColor: follow the theme, or use custom colours (the 2×2 branch) ---------
    // Distinct string sentinels stand in for the four colours so each branch is identifiable.
    function test_dotColor_data() {
        return [
            { tag: "theme-active", active: true, follow: true, exp: "themeActive" },
            { tag: "theme-inactive", active: false, follow: true, exp: "themeInactive" },
            { tag: "custom-active", active: true, follow: false, exp: "customActive" },
            { tag: "custom-inactive", active: false, follow: false, exp: "customInactive" }
        ];
    }
    function test_dotColor(data) {
        compare(Logic.dotColor(data.active, data.follow, "themeActive", "themeInactive", "customActive", "customInactive"), data.exp, data.tag);
    }

    // --- effectiveDuration: override vs themed default, reduce-animations always wins ---
    function test_effectiveDuration_data() {
        return [
            { tag: "auto-uses-theme", req: 0, theme: 200, exp: 200 },
            { tag: "override-wins", req: 250, theme: 200, exp: 250 },
            { tag: "reduce-animations-beats-override", req: 250, theme: 0, exp: 0 },
            { tag: "reduce-animations-and-auto", req: 0, theme: 0, exp: 0 },
            { tag: "negative-theme-is-off", req: 250, theme: -1, exp: 0 },
            { tag: "negative-request-is-auto", req: -5, theme: 200, exp: 200 },
            { tag: "request-equals-theme", req: 200, theme: 200, exp: 200 }
        ];
    }
    function test_effectiveDuration(data) {
        compare(Logic.effectiveDuration(data.req, data.theme), data.exp, data.tag);
    }

    // --- gridColumns: KWin-style desktops-per-line = ceil(count / rows) -------------
    function test_gridColumns_data() {
        return [
            { tag: "empty", count: 0, rows: 2, exp: 0 },
            { tag: "single-row", count: 4, rows: 1, exp: 4 },
            { tag: "two-rows-even", count: 4, rows: 2, exp: 2 },
            { tag: "two-rows-odd", count: 5, rows: 2, exp: 3 },
            { tag: "three-into-two-rows", count: 3, rows: 2, exp: 2 },
            { tag: "more-rows-than-desktops", count: 4, rows: 3, exp: 2 },
            { tag: "rows-zero-means-one", count: 4, rows: 0, exp: 4 },
            { tag: "rows-undefined-means-one", count: 4, rows: undefined, exp: 4 },
            { tag: "rows-null-means-one", count: 4, rows: null, exp: 4 },
            { tag: "negative-rows-means-one", count: 4, rows: -2, exp: 4 },
            { tag: "negative-count", count: -3, rows: 2, exp: 0 },
            { tag: "single-desktop", count: 1, rows: 1, exp: 1 }
        ];
    }
    function test_gridColumns(data) {
        compare(Logic.gridColumns(data.count, data.rows), data.exp, data.tag);
    }

    // --- chunk: row-major lines of at most `size`; transient inputs give [] ----------
    function test_chunk_data() {
        return [
            { tag: "even", arr: ["a", "b", "c", "d"], size: 2, exp: [["a", "b"], ["c", "d"]] },
            { tag: "uneven-last-short", arr: ["a", "b", "c"], size: 2, exp: [["a", "b"], ["c"]] },
            { tag: "size-bigger-than-arr", arr: ["a", "b"], size: 5, exp: [["a", "b"]] },
            { tag: "three-wide", arr: ["a", "b", "c", "d", "e"], size: 3, exp: [["a", "b", "c"], ["d", "e"]] },
            { tag: "empty", arr: [], size: 2, exp: [] },
            { tag: "null", arr: null, size: 2, exp: [] },
            { tag: "size-zero", arr: ["a", "b"], size: 0, exp: [] },
            { tag: "negative-size", arr: ["a", "b"], size: -1, exp: [] },
            { tag: "size-undefined", arr: ["a", "b"], size: undefined, exp: [] },
            { tag: "size-null", arr: ["a", "b"], size: null, exp: [] },
            { tag: "arr-undefined", arr: undefined, size: 2, exp: [] },
            { tag: "size-one", arr: ["a", "b", "c"], size: 1, exp: [["a"], ["b"], ["c"]] }
        ];
    }
    function test_chunk(data) {
        // JSON-compare so the nested arrays are checked by value, not identity.
        compare(JSON.stringify(Logic.chunk(data.arr, data.size)), JSON.stringify(data.exp), data.tag);
    }

    // --- lineExtent: one capsule + the rest dots, uniform gaps; transient -> one dot ---
    // Two callers: the major axis passes the pill as activeExtent (a real capsule); the cross
    // axis passes dotSize (the all-dots degenerate case, n*dot + (n-1)*gap).
    function test_lineExtent_data() {
        return [
            // major axis: one capsule (25) + the rest dots (10) with gaps (5)
            { tag: "capsule-line", count: 3, dot: 10, gap: 5, active: 25, exp: 55 },
            // cross axis / all-dots: activeExtent == dotSize -> n*dot + (n-1)*gap
            { tag: "all-dots", count: 2, dot: 10, gap: 5, active: 10, exp: 25 },
            { tag: "all-dots-three", count: 3, dot: 10, gap: 5, active: 10, exp: 40 },
            // a single slot is just that slot (no gaps) — capsule or dot
            { tag: "single-capsule", count: 1, dot: 10, gap: 5, active: 25, exp: 25 },
            { tag: "single-dot", count: 1, dot: 10, gap: 5, active: 10, exp: 10 },
            // transient no-desktops: returns ONE dotSize (NOT activeExtent), so the cell holds
            { tag: "zero-returns-dot", count: 0, dot: 10, gap: 5, active: 25, exp: 10 },
            { tag: "negative-returns-dot", count: -1, dot: 10, gap: 5, active: 25, exp: 10 },
            // gap 0 is a valid (tight) config: one capsule + the rest dots with no spacing.
            { tag: "no-gap-line", count: 3, dot: 10, gap: 0, active: 25, exp: 45 },
            { tag: "five-dots", count: 5, dot: 10, gap: 5, active: 10, exp: 70 }
        ];
    }
    function test_lineExtent(data) {
        fuzzyCompare(Logic.lineExtent(data.count, data.dot, data.gap, data.active), data.exp, 0.001, data.tag);
    }

    // --- fitDotSize: invert lineExtent so one full line fills the allocated major length ---
    // denom = pillWidthFactor + (perLine-1)*(1+spacingFactor); fitDotSize = available / denom. The
    // indicator clamps the result to <= naturalDotSize (and >= a floor), so "ample-room" returning
    // more than natural is fine — the caller caps it.
    function test_fitDotSize_data() {
        return [
            // exact fit: available == lineExtent(perLine 3) at dot 10 (denom 6.5 -> 65) -> back to 10
            { tag: "exact-fit-multi", avail: 65, perLine: 3, pill: 3.5, spacing: 0.5, exp: 10 },
            // single line: denom == pillWidthFactor (the lone capsule, no gaps)
            { tag: "single-line", avail: 35, perLine: 1, pill: 3.5, spacing: 0.5, exp: 10 },
            // over budget (less room than natural) shrinks the dot below natural
            { tag: "over-budget-shrinks", avail: 32.5, perLine: 3, pill: 3.5, spacing: 0.5, exp: 5 },
            // ample room returns MORE than natural (the caller caps it at naturalDotSize)
            { tag: "ample-room-exceeds-natural", avail: 130, perLine: 3, pill: 3.5, spacing: 0.5, exp: 20 },
            // wider spacing widens the denom -> smaller fit for the same width
            { tag: "wider-spacing-smaller-fit", avail: 80, perLine: 3, pill: 3.5, spacing: 1.0, exp: 80 / 7.5 },
            // CROSS-axis usage (no capsule -> pill factor 1, count = lineCount): the exact inverse of
            // naturalCrossThickness. Single line: denom == 1, so the fit is the whole thickness.
            { tag: "cross-single-line", avail: 10, perLine: 1, pill: 1, spacing: 0.5, exp: 10 },
            // Cross, two lines: denom == 1 + (2-1)*(1+0.5) == 2.5, so 25 / 2.5 -> 10.
            { tag: "cross-two-lines", avail: 25, perLine: 2, pill: 1, spacing: 0.5, exp: 10 }
        ];
    }
    function test_fitDotSize(data) {
        fuzzyCompare(Logic.fitDotSize(data.avail, data.perLine, data.pill, data.spacing), data.exp, 0.001, data.tag);
    }

    // Nothing to fit -> an unbounded (non-finite) result, so the caller's min(natural, fit) keeps the
    // natural size: a non-positive available (the pre-layout frame), no slots, or a degenerate denom.
    function test_fitDotSizeUnbounded_data() {
        return [
            { tag: "zero-perLine", avail: 100, perLine: 0, pill: 3.5, spacing: 0.5 },
            { tag: "negative-perLine", avail: 100, perLine: -2, pill: 3.5, spacing: 0.5 },
            { tag: "zero-available", avail: 0, perLine: 3, pill: 3.5, spacing: 0.5 },
            { tag: "negative-available", avail: -50, perLine: 3, pill: 3.5, spacing: 0.5 },
            { tag: "zero-denominator", avail: 100, perLine: 1, pill: 0, spacing: 0.5 },
            // the denom <= 0 guard also covers a strictly NEGATIVE denominator (a negative pill factor).
            { tag: "negative-denominator", avail: 100, perLine: 1, pill: -1, spacing: 0.5 }
        ];
    }
    function test_fitDotSizeUnbounded(data) {
        verify(!isFinite(Logic.fitDotSize(data.avail, data.perLine, data.pill, data.spacing)), data.tag);
    }

    // --- windowListMaximum: stock pager rule — show 4, but all 5 when exactly 5 --------
    function test_windowListMaximum_data() {
        return [
            { tag: "zero", count: 0, exp: 4 },
            { tag: "one", count: 1, exp: 4 },
            { tag: "four", count: 4, exp: 4 },
            { tag: "exactly-five-shows-all", count: 5, exp: 5 },
            { tag: "six", count: 6, exp: 4 },
            { tag: "many", count: 12, exp: 4 },
            { tag: "negative", count: -3, exp: 4 }
        ];
    }
    function test_windowListMaximum(data) {
        compare(Logic.windowListMaximum(data.count), data.exp, data.tag);
    }

    // --- toStringOrEmpty: null/undefined -> "", everything else through String() -------
    // Shared by the sanitize* functions: only null/undefined map to "" — 0/false stringify
    // ("0"/"false"), they are NOT collapsed to the empty string.
    function test_toStringOrEmpty_data() {
        return [
            { tag: "string", input: "hi", exp: "hi" },
            { tag: "empty-string-kept", input: "", exp: "" },
            { tag: "null", input: null, exp: "" },
            { tag: "undefined", input: undefined, exp: "" },
            { tag: "zero", input: 0, exp: "0" },
            { tag: "number", input: 42, exp: "42" },
            { tag: "false", input: false, exp: "false" },
            { tag: "true", input: true, exp: "true" },
            // only null/undefined map to ""; everything else goes through String() verbatim.
            { tag: "negative-number", input: -1, exp: "-1" },
            { tag: "nan", input: NaN, exp: "NaN" },
            { tag: "array", input: [1, 2], exp: "1,2" },
            { tag: "object", input: {}, exp: "[object Object]" }
        ];
    }
    function test_toStringOrEmpty(data) {
        compare(Logic.toStringOrEmpty(data.input), data.exp, data.tag);
    }

    // --- sanitizeHtml: entity-escape titles for the rich-text tooltip ------------------
    // Escapes the markup-sensitive chars and the no-break space ( ) — but NOT the ordinary
    // space (it must still wrap). Non-strings coerce to "" so the caller never throws.
    function test_sanitizeHtml_data() {
        return [
            { tag: "plain", input: "Firefox", exp: "Firefox" },
            { tag: "ordinary-space-kept", input: "New Tab", exp: "New Tab" },
            { tag: "angles", input: "a<b>c", exp: "a&lt;b&gt;c" },
            { tag: "ampersand", input: "Tom & Jerry", exp: "Tom &amp; Jerry" },
            { tag: "double-quote", input: "say \"hi\"", exp: "say &quot;hi&quot;" },
            { tag: "apostrophe", input: "it's", exp: "it&apos;s" },
            { tag: "nbsp-escaped", input: "a b", exp: "a&nbsp;b" },
            { tag: "null-coerced", input: null, exp: "" },
            { tag: "undefined-coerced", input: undefined, exp: "" },
            // several specials at once exercises the global regex; ordinary spaces still survive.
            { tag: "combined-multi-special", input: "<a href='x'>& ", exp: "&lt;a href=&apos;x&apos;&gt;&amp;&nbsp;" },
            // NOT idempotent: an already-escaped entity re-escapes its & (titles are escaped exactly once).
            { tag: "double-escape-not-idempotent", input: "a &amp; b", exp: "a &amp;amp; b" },
            { tag: "numeric-coerced", input: 42, exp: "42" },
            { tag: "empty-string", input: "", exp: "" }
        ];
    }
    function test_sanitizeHtml(data) {
        compare(Logic.sanitizeHtml(data.input), data.exp, data.tag);
    }

    // --- sanitizeDesktopName: normalise a user-entered name before the setDesktopName write -----
    // Trims, keeps internal spaces, rejects empty/whitespace-only as "" (the no-op sentinel), coerces
    // non-strings, and caps an absurd length. (Distinct from sanitizeHtml, which escapes markup.)
    function test_sanitizeDesktopName_data() {
        return [
            { tag: "plain", input: "Web", exp: "Web" },
            { tag: "internal-spaces-kept", input: "My Code", exp: "My Code" },
            { tag: "trims-leading-trailing", input: "  Web  ", exp: "Web" },
            { tag: "tab-newline-trimmed", input: "\tWeb\n", exp: "Web" },
            { tag: "empty-rejected", input: "", exp: "" },
            { tag: "whitespace-only-rejected", input: "   ", exp: "" },
            { tag: "null-coerced", input: null, exp: "" },
            { tag: "undefined-coerced", input: undefined, exp: "" },
            { tag: "number-coerced", input: 42, exp: "42" },
            // trim runs BEFORE the length cap: surrounding whitespace is stripped, then the 120-char
            // body is capped to 100.
            { tag: "trim-then-cap", input: "  " + "x".repeat(120) + "  ", exp: "x".repeat(100) }
        ];
    }
    function test_sanitizeDesktopName(data) {
        compare(Logic.sanitizeDesktopName(data.input), data.exp, data.tag);
    }

    // A 150-char name is capped at the 100-char maximum (checked by length so the test doesn't hardcode
    // the cap string). Kept separate from the table above because it asserts length, not equality.
    function test_sanitizeDesktopNameCapsLength() {
        var long = "x".repeat(150);
        compare(Logic.sanitizeDesktopName(long).length, 100, "over-max-truncated-to-100");
    }

    // The exact cap boundary: a name of exactly the 100-char maximum is kept verbatim; one over (101)
    // is truncated back to 100. (Length-based so it doesn't hardcode the cap string, like the test above.)
    function test_sanitizeDesktopNameBoundary() {
        var atMax = "y".repeat(100);
        compare(Logic.sanitizeDesktopName(atMax), atMax, "exactly 100 chars is kept verbatim");
        var overMax = "y".repeat(101);
        compare(Logic.sanitizeDesktopName(overMax).length, 100, "101 chars is capped to 100");
    }

    // --- windowIsOnDesktop: per-window membership predicate (used by groupWindowsByDesktop) ----
    // True for a real window that is onAll or whose `desktops` list holds the uuid; false for a
    // non-window, a miss, a missing `desktops`, or a null window. Returns a strict boolean.
    function test_windowIsOnDesktop_data() {
        const win = function (opts) {
            opts = opts || {};
            return { isWindow: opts.isWindow !== false, onAll: opts.onAll === true, desktops: opts.desktops };
        };
        return [
            { tag: "on-all", window: win({ onAll: true }), uuid: "a", exp: true },
            { tag: "on-all-ignores-desktops", window: win({ onAll: true, desktops: ["b"] }), uuid: "a", exp: true },
            { tag: "desktops-match", window: win({ desktops: ["a", "b"] }), uuid: "a", exp: true },
            { tag: "desktops-miss", window: win({ desktops: ["b"] }), uuid: "a", exp: false },
            { tag: "desktops-undefined", window: win({}), uuid: "a", exp: false },
            { tag: "non-window-excluded", window: win({ isWindow: false, desktops: ["a"] }), uuid: "a", exp: false },
            { tag: "null-window", window: null, uuid: "a", exp: false },
            { tag: "undefined-window", window: undefined, uuid: "a", exp: false },
            // isWindow entirely missing (a raw object, not via win()) is falsy → excluded, even with onAll.
            { tag: "isWindow-missing", window: { onAll: true, desktops: ["a"] }, uuid: "a", exp: false },
            // an empty desktops array is a miss (indexOf → -1), distinct from a missing desktops list.
            { tag: "empty-desktops-array", window: win({ desktops: [] }), uuid: "a", exp: false }
        ];
    }
    function test_windowIsOnDesktop(data) {
        compare(Logic.windowIsOnDesktop(data.window, data.uuid), data.exp, data.tag);
    }

    // --- groupWindowsByDesktop: per-desktop visible/minimized title lists --------------
    // Index-aligned with desktopIds. A window belongs to a desktop when it is a real window AND
    // (it is on all desktops OR its `desktops` list holds that id); minimized windows bucket apart;
    // model order is preserved; transient null/empty inputs degrade safely.
    function test_groupWindowsByDesktop_data() {
        const w = function (title, desktops, opts) {
            opts = opts || {};
            return { title: title, desktops: desktops, isWindow: opts.isWindow !== false, minimized: opts.minimized === true, onAll: opts.onAll === true };
        };
        return [
            { tag: "empty-ids", windows: [w("A", ["a"])], ids: [], exp: [] },
            { tag: "null-ids", windows: [w("A", ["a"])], ids: null, exp: [] },
            {
                tag: "null-windows-empty-entries", windows: null, ids: ["a", "b"],
                exp: [{ visible: [], minimized: [] }, { visible: [], minimized: [] }]
            },
            {
                tag: "membership-and-alignment", windows: [w("A", ["a"]), w("B", ["b"])], ids: ["a", "b"],
                exp: [{ visible: ["A"], minimized: [] }, { visible: ["B"], minimized: [] }]
            },
            {
                tag: "on-all-appears-everywhere", windows: [w("All", [], { onAll: true })], ids: ["a", "b"],
                exp: [{ visible: ["All"], minimized: [] }, { visible: ["All"], minimized: [] }]
            },
            {
                tag: "minimized-bucket", windows: [w("M", ["a"], { minimized: true })], ids: ["a"],
                exp: [{ visible: [], minimized: ["M"] }]
            },
            {
                tag: "non-window-excluded", windows: [w("Launcher", ["a"], { isWindow: false })], ids: ["a"],
                exp: [{ visible: [], minimized: [] }]
            },
            {
                tag: "not-on-this-desktop", windows: [w("X", ["b"])], ids: ["a"],
                exp: [{ visible: [], minimized: [] }]
            },
            {
                tag: "order-preserved", windows: [w("A", ["a"]), w("B", ["a"]), w("C", ["a"], { minimized: true })], ids: ["a"],
                exp: [{ visible: ["A", "B"], minimized: ["C"] }]
            },
            // undefined ids (distinct from null) and an empty windows ARRAY (distinct from null windows).
            { tag: "undefined-ids", windows: [w("A", ["a"])], ids: undefined, exp: [] },
            {
                tag: "empty-windows-array", windows: [], ids: ["a", "b"],
                exp: [{ visible: [], minimized: [] }, { visible: [], minimized: [] }]
            },
            // an onAll AND minimized window lands in the minimized bucket of EVERY desktop.
            {
                tag: "on-all-and-minimized", windows: [w("M", [], { onAll: true, minimized: true })], ids: ["a", "b"],
                exp: [{ visible: [], minimized: ["M"] }, { visible: [], minimized: ["M"] }]
            },
            // a window on two desktops appears in both their buckets, but not a third.
            {
                tag: "window-on-multiple-desktops", windows: [w("Multi", ["a", "b"])], ids: ["a", "b", "c"],
                exp: [{ visible: ["Multi"], minimized: [] }, { visible: ["Multi"], minimized: [] }, { visible: [], minimized: [] }]
            },
            // titles are kept RAW: a title-less window pushes undefined (the i18n "Untitled" fallback is
            // main.qml's job). JSON-compare renders undefined as null on both sides, so this pins the shape.
            {
                tag: "missing-title", windows: [w(undefined, ["a"])], ids: ["a"],
                exp: [{ visible: [undefined], minimized: [] }]
            }
        ];
    }
    function test_groupWindowsByDesktop(data) {
        // JSON-compare so the nested {visible, minimized} arrays are checked by value, not identity.
        compare(JSON.stringify(Logic.groupWindowsByDesktop(data.windows, data.ids)), JSON.stringify(data.exp), data.tag);
    }

    // --- DEFAULTS: the single source of truth for the QML-side config defaults --------
    // A change-detector + contract doc: every value mirrors a contents/config/main.xml <default>
    // and is referenced by main.qml's `?? Logic.DEFAULTS.X` and the component property defaults,
    // so accidental drift here (or a missing key) fails loudly instead of silently desyncing.
    function test_defaults_data() {
        return [
            { tag: "enableScroll", key: "enableScroll", exp: true },
            { tag: "scrollWrap", key: "scrollWrap", exp: false },
            { tag: "showTooltips", key: "showTooltips", exp: true },
            { tag: "showWindowList", key: "showWindowList", exp: true },
            { tag: "enableAddRemove", key: "enableAddRemove", exp: true },
            { tag: "enableRename", key: "enableRename", exp: true },
            { tag: "animationDuration", key: "animationDuration", exp: 0 },
            { tag: "dotSize", key: "dotSize", exp: 0 },
            { tag: "pillSize", key: "pillSize", exp: 0 },
            { tag: "spacingFactor", key: "spacingFactor", exp: 0.5 },
            { tag: "pillWidthFactor", key: "pillWidthFactor", exp: 3.5 },
            { tag: "inactiveOpacity", key: "inactiveOpacity", exp: 0.45 },
            { tag: "hoverOpacity", key: "hoverOpacity", exp: 0.8 },
            { tag: "followThemeColors", key: "followThemeColors", exp: true },
            { tag: "activeColor", key: "activeColor", exp: "#3daee9" },
            { tag: "inactiveColor", key: "inactiveColor", exp: "#eff0f1" },
            { tag: "wheelNotchDelta", key: "wheelNotchDelta", exp: 120 }
        ];
    }
    function test_defaults(data) {
        compare(Logic.DEFAULTS[data.key], data.exp, data.tag);
    }

    // DEFAULTS is shared (.pragma library) and must stay immutable — a stray write would corrupt
    // every importer for the session. Object.freeze makes the assignment a no-op (silent in
    // non-strict JS, a TypeError under "use strict"); tolerate either so the test asserts the
    // value stays put, not which JS mode the engine happens to run.
    function test_defaultsAreFrozen() {
        verify(Object.isFrozen(Logic.DEFAULTS), "Logic.DEFAULTS must be frozen");
        try { Logic.DEFAULTS.dotSize = 999; } catch (e) { /* strict-mode TypeError is expected */ }
        compare(Logic.DEFAULTS.dotSize, 0, "a frozen DEFAULTS ignores writes");
    }

    // The exact key SET is pinned (test_defaults above only checks values, so it can't catch an ADDED
    // or REMOVED key). A new config key must be added here and to main.xml together, or this fails.
    function test_defaultsKeySet() {
        var keys = Object.keys(Logic.DEFAULTS).sort();
        var expected = ["activeColor", "animationDuration", "dotSize", "enableAddRemove", "enableRename",
                        "enableScroll", "followThemeColors", "hoverOpacity", "inactiveColor",
                        "inactiveOpacity", "pillSize", "pillWidthFactor", "scrollWrap", "showTooltips",
                        "showWindowList", "spacingFactor", "wheelNotchDelta"].sort();
        compare(keys.length, 17, "DEFAULTS has exactly 17 keys");
        compare(JSON.stringify(keys), JSON.stringify(expected), "the exact DEFAULTS key set is pinned");
    }
}
