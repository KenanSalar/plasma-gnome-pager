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
}
