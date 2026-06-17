/*
 * GNOME Workspace Switcher — tst_logic.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
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
            { tag: "many", count: 9, exp: true }
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
            { tag: "many", ids: ["a", "b", "c"], exp: "c" }
        ];
    }
    function test_lastDesktopId(data) {
        compare(Logic.lastDesktopId(data.ids), data.exp, data.tag);
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
            { tag: "threshold-defaults-to-120", acc: 0, d: 120, t: 0, steps: 1, rem: 0 }
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
            { tag: "negative-request-is-auto", req: -5, theme: 200, exp: 200 }
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
            { tag: "rows-undefined-means-one", count: 4, rows: undefined, exp: 4 }
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
            { tag: "size-zero", arr: ["a", "b"], size: 0, exp: [] }
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
            { tag: "negative-returns-dot", count: -1, dot: 10, gap: 5, active: 25, exp: 10 }
        ];
    }
    function test_lineExtent(data) {
        fuzzyCompare(Logic.lineExtent(data.count, data.dot, data.gap, data.active), data.exp, 0.001, data.tag);
    }
}
