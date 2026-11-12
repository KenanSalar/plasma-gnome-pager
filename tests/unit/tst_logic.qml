/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * logic.js imported directly, with nothing from Plasma or Kirigami: the cheapest place to pin a
 * decision, so the most exhaustive.
 */
import QtTest
import "../../package/contents/ui/logic.js" as Logic

TestCase {
    id: testCase
    name: "Logic"

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

            // states the caller ignores: an empty list, a current not in it, a current out of range
            { tag: "empty-clamp", cur: -1, count: 0, delta: 1, wrap: false, exp: -1 },
            { tag: "empty-wrap", cur: -1, count: 0, delta: 1, wrap: true, exp: -1 },
            { tag: "unknown-current-clamp", cur: -1, count: 3, delta: 1, wrap: false, exp: -1 },
            { tag: "unknown-current-wrap", cur: -1, count: 3, delta: 1, wrap: true, exp: -1 },
            { tag: "out-of-range-current", cur: 5, count: 3, delta: 1, wrap: false, exp: -1 },
            // The range guards run before the wrap, so an out-of-range current is -1 even with wrap.
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

    function test_lastDesktopId_data() {
        return [
            { tag: "empty", ids: [], exp: "" },
            { tag: "null", ids: null, exp: "" },
            { tag: "single", ids: ["a"], exp: "a" },
            { tag: "many", ids: ["a", "b", "c"], exp: "c" },
            { tag: "undefined", ids: undefined, exp: "" },
            // returned as it is, without coercion to a string
            { tag: "non-string-last", ids: [1, 2, 3], exp: 3 }
        ];
    }
    function test_lastDesktopId(data) {
        compare(Logic.lastDesktopId(data.ids), data.exp, data.tag);
    }

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

            // wheel up: `| 0` truncates toward zero, so step and remainder are both negative
            { tag: "negative-overshoot-carries", acc: 0, d: -200, t: 120, steps: -1, rem: -80 },
            { tag: "negative-double-notch", acc: 0, d: -240, t: 120, steps: -2, rem: 0 },
            { tag: "negative-remainder-feeds-back", acc: -80, d: -60, t: 120, steps: -1, rem: -20 },

            // several notches with a carried remainder, other thresholds, a missing or negative threshold
            // (120 then), and a zero delta that only carries the total forward
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

    function test_dotOpacity_data() {
        var F = Logic.OCCUPANCY.Filled;
        return [
            { tag: "idle", active: false, hovered: false, occupied: false, style: F, exp: 0.45 },
            { tag: "hovered", active: false, hovered: true, occupied: false, style: F, exp: 0.8 },
            { tag: "active-not-hovered", active: true, hovered: false, occupied: false, style: F, exp: 1.0 },
            { tag: "active-and-hovered", active: true, hovered: true, occupied: false, style: F, exp: 1.0 },
            { tag: "occupied-filled", active: false, hovered: false, occupied: true, style: F, exp: 0.7 },
            { tag: "occupied-and-hovered", active: false, hovered: true, occupied: true, style: F, exp: 0.8 },
            { tag: "occupied-and-active", active: true, hovered: false, occupied: true, style: F, exp: 1.0 },
            // InnerDot and Ring keep a dim body; their markers carry the occupied opacity themselves.
            { tag: "occupied-ring-body-stays-dim", active: false, hovered: false, occupied: true, style: Logic.OCCUPANCY.Ring, exp: 0.45 },
            { tag: "occupied-innerdot-body-stays-dim", active: false, hovered: false, occupied: true, style: Logic.OCCUPANCY.InnerDot, exp: 0.45 }
        ];
    }
    function test_dotOpacity(data) {
        fuzzyCompare(Logic.dotOpacity(data.active, data.hovered, data.occupied, data.style, 0.45, 0.8, 0.7), data.exp, 0.001, data.tag);
    }

    function test_dotOpacityCustomRatios() {
        var F = Logic.OCCUPANCY.Filled;
        fuzzyCompare(Logic.dotOpacity(false, false, false, F, 0.2, 0.9, 0.6), 0.2, 0.001, "idle uses the given inactiveOpacity");
        fuzzyCompare(Logic.dotOpacity(false, true, false, F, 0.2, 0.9, 0.6), 0.9, 0.001, "hover uses the given hoverOpacity");
        fuzzyCompare(Logic.dotOpacity(false, false, true, F, 0.2, 0.9, 0.6), 0.6, 0.001, "occupied (Filled) uses occupiedOpacity");
        fuzzyCompare(Logic.dotOpacity(false, true, true, F, 0.2, 0.9, 0.6), 0.9, 0.001, "hover beats occupied");
        fuzzyCompare(Logic.dotOpacity(true, false, false, F, 0.2, 0.9, 0.6), 1.0, 0.001, "active is full strength, ignoring inactiveOpacity");
        fuzzyCompare(Logic.dotOpacity(true, true, true, F, 0.2, 0.9, 0.6), 1.0, 0.001, "active beats hover and occupied");
        fuzzyCompare(Logic.dotOpacity(false, false, true, Logic.OCCUPANCY.Ring, 0.2, 0.9, 0.6), 0.2, 0.001, "Ring body stays dim (the ring overlay carries the opacity)");
        fuzzyCompare(Logic.dotOpacity(false, false, true, Logic.OCCUPANCY.InnerDot, 0.2, 0.9, 0.6), 0.2, 0.001, "InnerDot body stays dim (the inner dot carries the opacity)");
    }

    function test_nextHoveredIndex_data() {
        return [
            { tag: "enter-from-nothing", current: -1, index: 2, hovered: true, exp: 2 },
            { tag: "leave-own-index", current: 2, index: 2, hovered: false, exp: -1 },
            // Qt delivers dot 2's enter before dot 1's leave, so the index already names dot 2 here.
            { tag: "dot-to-dot-enter", current: 1, index: 2, hovered: true, exp: 2 },
            { tag: "dot-to-dot-stale-leave", current: 2, index: 1, hovered: false, exp: 2 },
            // a leave from a dot nobody recorded, as at a teardown after the index was cleared
            { tag: "stale-leave-while-clear", current: -1, index: 3, hovered: false, exp: -1 },
            { tag: "index-zero-enter", current: -1, index: 0, hovered: true, exp: 0 },
            { tag: "index-zero-leave", current: 0, index: 0, hovered: false, exp: -1 }
        ];
    }
    function test_nextHoveredIndex(data) {
        compare(Logic.nextHoveredIndex(data.current, data.index, data.hovered), data.exp, data.tag);
    }

    function test_hoverBackgroundAlpha_data() {
        return [
            { tag: "on-hovered", enabled: true, hovered: true, opacity: 0.12, exp: 0.12 },
            { tag: "on-not-hovered", enabled: true, hovered: false, opacity: 0.12, exp: 0 },
            { tag: "off-hovered", enabled: false, hovered: true, opacity: 0.12, exp: 0 },
            { tag: "off-not-hovered", enabled: false, hovered: false, opacity: 0.12, exp: 0 },
            // a custom opacity comes straight through
            { tag: "custom-opacity", enabled: true, hovered: true, opacity: 0.6, exp: 0.6 },
            // the slider at zero draws nothing, as if switched off
            { tag: "zero-opacity", enabled: true, hovered: true, opacity: 0, exp: 0 }
        ];
    }
    function test_hoverBackgroundAlpha(data) {
        fuzzyCompare(Logic.hoverBackgroundAlpha(data.enabled, data.hovered, data.opacity), data.exp, 0.001, data.tag);
    }

    function test_hoverPadding_data() {
        return [
            { tag: "gnome-length", line: 10, factor: Logic.DEFAULTS.hoverLengthFactor, exp: 10.0 },
            { tag: "gnome-thickness", line: 10, factor: Logic.DEFAULTS.hoverThicknessFactor, exp: 10.0 },
            { tag: "scales-with-the-dot", line: 20, factor: Logic.DEFAULTS.hoverThicknessFactor, exp: 20.0 },
            { tag: "zero-factor-hugs-the-strip", line: 10, factor: 0, exp: 0 },
            { tag: "large-factor", line: 10, factor: 3.0, exp: 30.0 }
        ];
    }
    function test_hoverPadding(data) {
        fuzzyCompare(Logic.hoverPadding(data.line, data.factor), data.exp, 0.001, data.tag);
    }

    // The defaults were matched against GNOME on a real panel: a pill's thickness of clearance a side.
    function test_hoverDefaultsMatchGnomeProportions() {
        var line = 8;
        var height = line + 2 * Logic.hoverPadding(line, Logic.DEFAULTS.hoverThicknessFactor);
        fuzzyCompare(height / line, 3.0, 0.05, "background height is 3 pill thicknesses");
        fuzzyCompare(Logic.hoverPadding(line, Logic.DEFAULTS.hoverLengthFactor), line, 0.001, "the end clearance is one pill thickness");
        compare(Logic.DEFAULTS.hoverThicknessFactor, Logic.DEFAULTS.hoverLengthFactor, "the default clearance is uniform on both axes");
    }

    function test_hoverCrossExtent_data() {
        return [
            // room to spare: the strip and its clearance, not the whole cell
            { tag: "ample-cell", cell: 100, cross: 10, pad: 4.5, exp: 19 },
            // Cell exactly the strip: caps rather than overflowing.
            { tag: "cell-equals-strip", cell: 10, cross: 10, pad: 4.5, exp: 10 },
            // Thin panel: capped at the cell.
            { tag: "thin-cell", cell: 14, cross: 10, pad: 4.5, exp: 14 },
            // No clearance requested: exactly the strip.
            { tag: "zero-padding", cell: 100, cross: 10, pad: 0, exp: 10 }
        ];
    }
    function test_hoverCrossExtent(data) {
        fuzzyCompare(Logic.hoverCrossExtent(data.cell, data.cross, data.pad), data.exp, 0.001, data.tag);
    }

    // Strings stand in for the colours, so each branch shows by name.
    function test_dotColor_data() {
        var F = Logic.OCCUPANCY.Filled;
        return [
            { tag: "active", active: true, occupied: false, style: F, exp: "active" },
            { tag: "empty-inactive", active: false, occupied: false, style: F, exp: "inactive" },
            // Filled colours the body itself
            { tag: "filled-occupied", active: false, occupied: true, style: F, exp: "occupied" },
            // InnerDot and Ring leave the body inactive and draw their marker over it
            { tag: "innerdot-occupied-body", active: false, occupied: true, style: Logic.OCCUPANCY.InnerDot, exp: "inactive" },
            { tag: "ring-occupied-body", active: false, occupied: true, style: Logic.OCCUPANCY.Ring, exp: "inactive" }
        ];
    }
    function test_dotColor(data) {
        compare(Logic.dotColor(data.active, data.occupied, data.style, "active", "inactive", "occupied"), data.exp, data.tag);
    }

    // A stored index has to keep meaning the same style, action or look.
    function test_occupancyConstants() {
        compare(Logic.OCCUPANCY.Filled, 0, "Filled is index 0 (the default)");
        compare(Logic.OCCUPANCY.InnerDot, 1, "InnerDot is index 1");
        compare(Logic.OCCUPANCY.Ring, 2, "Ring is index 2");
    }

    function test_pillClickConstants() {
        compare(Logic.PILL_CLICK_ACTION.None, 0, "None is index 0 (the default)");
        compare(Logic.PILL_CLICK_ACTION.ShowDesktop, 1, "ShowDesktop is index 1");
        compare(Logic.PILL_CLICK_ACTION.Overview, 2, "Overview is index 2");
        compare(Logic.PILL_CLICK_ACTION.Grid, 3, "Grid is index 3");
    }

    function test_dotStyleConstants() {
        compare(Logic.DOT_STYLE.Pill, 0, "Pill is index 0 (the default)");
        compare(Logic.DOT_STYLE.Ring, 1, "Ring (Filled & ring) is index 1");
    }

    function test_isRingStyle() {
        verify(Logic.isRingStyle(Logic.DOT_STYLE.Ring), "Ring style → true");
        verify(!Logic.isRingStyle(Logic.DOT_STYLE.Pill), "Pill style → false");
    }

    // A tiny dot still gets a ring a pixel wide.
    function test_ringThickness() {
        compare(Logic.ringThickness(100), 18, "100 → 18 (0.18×)");
        compare(Logic.ringThickness(16), 3, "16 → 3 (rounded)");
        compare(Logic.ringThickness(2), 1, "2 → 1 (min-1 clamp, not 0)");
        compare(Logic.ringThickness(0), 1, "0 → 1 (min-1 clamp)");
    }

    // Unrounded, unlike ringThickness.
    function test_innerDotDiameter() {
        fuzzyCompare(Logic.innerDotDiameter(100), 45, 0.001, "100 → 45 (0.45×)");
        fuzzyCompare(Logic.innerDotDiameter(16), 7.2, 0.001, "16 → 7.2");
        fuzzyCompare(Logic.innerDotDiameter(0), 0, 0.001, "0 → 0");
    }

    function test_ringOverlayVisible() {
        var pill = Logic.DOT_STYLE.Pill;
        verify(Logic.ringOverlayVisible(false, true, Logic.OCCUPANCY.Ring, pill), "Ring + inactive + occupied → ring overlay");
        verify(!Logic.ringOverlayVisible(false, false, Logic.OCCUPANCY.Ring, pill), "Ring + empty → no overlay");
        verify(!Logic.ringOverlayVisible(true, true, Logic.OCCUPANCY.Ring, pill), "Ring + active → no overlay (it's the pill)");
        verify(!Logic.ringOverlayVisible(false, true, Logic.OCCUPANCY.Filled, pill), "non-Ring style → no ring overlay");
        // In the ring style the body already is one.
        verify(!Logic.ringOverlayVisible(false, true, Logic.OCCUPANCY.Ring, Logic.DOT_STYLE.Ring), "Filled & ring dot-style → ring overlay suppressed");
    }

    function test_innerDotVisible() {
        verify(Logic.innerDotVisible(false, true, Logic.OCCUPANCY.InnerDot), "InnerDot + inactive + occupied → centre dot");
        verify(!Logic.innerDotVisible(false, false, Logic.OCCUPANCY.InnerDot), "InnerDot + empty → no centre dot");
        verify(!Logic.innerDotVisible(true, true, Logic.OCCUPANCY.InnerDot), "InnerDot + active → no centre dot (it's the pill)");
        verify(!Logic.innerDotVisible(false, true, Logic.OCCUPANCY.Ring), "non-InnerDot style → no centre dot");
    }

    function test_dotHasRing() {
        verify(!Logic.dotHasRing(Logic.DOT_STYLE.Pill, false), "Pill style → no ring outline");
        verify(!Logic.dotHasRing(Logic.DOT_STYLE.Pill, true), "Pill style + active → no ring outline");
        verify(Logic.dotHasRing(Logic.DOT_STYLE.Ring, false), "Ring style + non-current → ring outline");
        verify(!Logic.dotHasRing(Logic.DOT_STYLE.Ring, true), "Ring style + current → no outline (filled circle)");
    }

    function test_dotBodyIsHollow_data() {
        var Pill = Logic.DOT_STYLE.Pill, Ring = Logic.DOT_STYLE.Ring;
        var F = Logic.OCCUPANCY.Filled, I = Logic.OCCUPANCY.InnerDot, R = Logic.OCCUPANCY.Ring;
        return [
            // pill style
            { tag: "pill-inactive", style: Pill, active: false, occupied: false, occ: F, exp: false },
            { tag: "pill-active", style: Pill, active: true, occupied: false, occ: F, exp: false },
            { tag: "pill-occupied-filled", style: Pill, active: false, occupied: true, occ: F, exp: false },
            // ring style
            { tag: "ring-active", style: Ring, active: true, occupied: false, occ: F, exp: false }, // current = filled circle
            { tag: "ring-empty", style: Ring, active: false, occupied: false, occ: F, exp: true }, // hollow ring
            { tag: "ring-occupied-filled", style: Ring, active: false, occupied: true, occ: F, exp: false }, // Filled fills the interior (keeps the outline)
            { tag: "ring-occupied-innerdot", style: Ring, active: false, occupied: true, occ: I, exp: true }, // hollow + inner dot
            { tag: "ring-occupied-ring", style: Ring, active: false, occupied: true, occ: R, exp: true } // hollow (overlay suppressed)
        ];
    }
    function test_dotBodyIsHollow(data) {
        compare(Logic.dotBodyIsHollow(data.style, data.active, data.occupied, data.occ), data.exp, data.tag);
    }

    function test_dotBodyFilled() {
        var Pill = Logic.DOT_STYLE.Pill, Ring = Logic.DOT_STYLE.Ring;
        var F = Logic.OCCUPANCY.Filled, I = Logic.OCCUPANCY.InnerDot;
        verify(Logic.dotBodyFilled(Ring, false, true, F), "Ring + non-current + occupied + Filled → ring outline + filled interior");
        verify(!Logic.dotBodyFilled(Ring, false, false, F), "Ring + empty → hollow, not filled");
        verify(!Logic.dotBodyFilled(Ring, false, true, I), "Ring + occupied + InnerDot → hollow (marker is an overlay)");
        verify(!Logic.dotBodyFilled(Ring, true, true, F), "Ring + current → filled circle, but no ring outline → not 'ring filled'");
        verify(!Logic.dotBodyFilled(Pill, false, true, F), "Pill style → never a filled ring");
    }

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
        compare(JSON.stringify(Logic.chunk(data.arr, data.size)), JSON.stringify(data.exp), data.tag);
    }

    function test_arraysShallowEqual_data() {
        var same = [true, false, true];
        var nested = [["a"]];
        return [
            { tag: "identical-bools", a: [true, false, true], b: [true, false, true], exp: true },
            { tag: "identical-strings", a: ["x", "y"], b: ["x", "y"], exp: true },
            { tag: "same-reference", a: same, b: same, exp: true },
            { tag: "both-empty", a: [], b: [], exp: true },
            { tag: "differ-element", a: [true, false], b: [true, true], exp: false },
            { tag: "differ-length-shorter", a: [true], b: [true, false], exp: false },
            { tag: "differ-length-longer", a: [true, false, false], b: [true, false], exp: false },
            { tag: "string-vs-empty", a: ["a"], b: [], exp: false },
            { tag: "null-a", a: null, b: [], exp: false },
            { tag: "null-b", a: [], b: null, exp: false },
            { tag: "both-null-identity", a: null, b: null, exp: true },
            { tag: "undefined-a", a: undefined, b: [true], exp: false },
            // not recursive: nested arrays with equal contents are still different arrays
            { tag: "nested-distinct-refs-unequal", a: [["a"]], b: [["a"]], exp: false },
            { tag: "nested-same-ref-equal", a: nested, b: nested, exp: true },
            // no coercion
            { tag: "no-bool-number-coercion", a: [1], b: [true], exp: false },
            { tag: "no-string-number-coercion", a: ["1"], b: [1], exp: false }
        ];
    }
    function test_arraysShallowEqual(data) {
        compare(Logic.arraysShallowEqual(data.a, data.b), data.exp, data.tag);
    }

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
            // no desktops yet: one dot, not the pill, so the cell keeps a size
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

    // The denominator is pillWidthFactor + (perLine - 1) * (1 + spacingFactor); the caller clamps the result.
    function test_fitDotSize_data() {
        return [
            // exact fit: available == lineExtent(perLine 3) at dot 10 (denom 6.5 -> 65) -> back to 10
            { tag: "exact-fit-multi", avail: 65, perLine: 3, pill: 3.5, spacing: 0.5, exp: 10 },
            // single line: denom == pillWidthFactor (the lone capsule, no gaps)
            { tag: "single-line", avail: 35, perLine: 1, pill: 3.5, spacing: 0.5, exp: 10 },
            // over budget (less room than natural) shrinks the dot below natural
            { tag: "over-budget-shrinks", avail: 32.5, perLine: 3, pill: 3.5, spacing: 0.5, exp: 5 },
            // ample room gives more than natural, which the caller caps
            { tag: "ample-room-exceeds-natural", avail: 130, perLine: 3, pill: 3.5, spacing: 0.5, exp: 20 },
            // wider spacing widens the denom -> smaller fit for the same width
            { tag: "wider-spacing-smaller-fit", avail: 80, perLine: 3, pill: 3.5, spacing: 1.0, exp: 80 / 7.5 },
            // across the lines: a pill factor of 1 and the line count. One line fits the whole thickness.
            { tag: "cross-single-line", avail: 10, perLine: 1, pill: 1, spacing: 0.5, exp: 10 },
            // two lines: 1 + 1 * 1.5 = 2.5, and 25 / 2.5 = 10
            { tag: "cross-two-lines", avail: 25, perLine: 2, pill: 1, spacing: 0.5, exp: 10 }
        ];
    }
    function test_fitDotSize(data) {
        fuzzyCompare(Logic.fitDotSize(data.avail, data.perLine, data.pill, data.spacing), data.exp, 0.001, data.tag);
    }

    // No allocation yet, no slots, or a degenerate denominator.
    function test_fitDotSizeUnbounded_data() {
        return [
            { tag: "zero-perLine", avail: 100, perLine: 0, pill: 3.5, spacing: 0.5 },
            { tag: "negative-perLine", avail: 100, perLine: -2, pill: 3.5, spacing: 0.5 },
            { tag: "zero-available", avail: 0, perLine: 3, pill: 3.5, spacing: 0.5 },
            { tag: "negative-available", avail: -50, perLine: 3, pill: 3.5, spacing: 0.5 },
            { tag: "zero-denominator", avail: 100, perLine: 1, pill: 0, spacing: 0.5 },
            // a negative pill factor makes the denominator negative
            { tag: "negative-denominator", avail: 100, perLine: 1, pill: -1, spacing: 0.5 }
        ];
    }
    function test_fitDotSizeUnbounded(data) {
        verify(!isFinite(Logic.fitDotSize(data.avail, data.perLine, data.pill, data.spacing)), data.tag);
    }

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
            // 0 and false stringify rather than collapse to ""
            { tag: "negative-number", input: -1, exp: "-1" },
            { tag: "nan", input: NaN, exp: "NaN" },
            { tag: "array", input: [1, 2], exp: "1,2" },
            { tag: "object", input: {}, exp: "[object Object]" }
        ];
    }
    function test_toStringOrEmpty(data) {
        compare(Logic.toStringOrEmpty(data.input), data.exp, data.tag);
    }

    // The no-break space ( ) is escaped too; the plain space stays, so a title still wraps.
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
            // not idempotent, so a title has to be escaped exactly once
            { tag: "double-escape-not-idempotent", input: "a &amp; b", exp: "a &amp;amp; b" },
            { tag: "numeric-coerced", input: 42, exp: "42" },
            { tag: "empty-string", input: "", exp: "" }
        ];
    }
    function test_sanitizeHtml(data) {
        compare(Logic.sanitizeHtml(data.input), data.exp, data.tag);
    }

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
            // trimmed before the cap, so the whitespace doesn't count toward it
            { tag: "trim-then-cap", input: "  " + "x".repeat(120) + "  ", exp: "x".repeat(100) }
        ];
    }
    function test_sanitizeDesktopName(data) {
        compare(Logic.sanitizeDesktopName(data.input), data.exp, data.tag);
    }

    // Checked by length, so the test doesn't spell out the capped string.
    function test_sanitizeDesktopNameCapsLength() {
        var long = "x".repeat(150);
        compare(Logic.sanitizeDesktopName(long).length, 100, "over-max-truncated-to-100");
    }

    function test_sanitizeDesktopNameBoundary() {
        var atMax = "y".repeat(100);
        compare(Logic.sanitizeDesktopName(atMax), atMax, "exactly 100 chars is kept verbatim");
        var overMax = "y".repeat(101);
        compare(Logic.sanitizeDesktopName(overMax).length, 100, "101 chars is capped to 100");
    }

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
            // a raw object without isWindow is excluded, even on every desktop
            { tag: "isWindow-missing", window: { onAll: true, desktops: ["a"] }, uuid: "a", exp: false },
            // an empty desktops array is a miss (indexOf → -1), distinct from a missing desktops list.
            { tag: "empty-desktops-array", window: win({ desktops: [] }), uuid: "a", exp: false }
        ];
    }
    function test_windowIsOnDesktop(data) {
        compare(Logic.windowIsOnDesktop(data.window, data.uuid), data.exp, data.tag);
    }

    function test_windowOccupiesDesktop_data() {
        const occ = function (opts) {
            opts = opts || {};
            return {
                isWindow: opts.isWindow !== false, onAll: opts.onAll === true,
                skipPager: opts.skipPager === true, minimized: opts.minimized === true,
                desktops: opts.desktops
            };
        };
        return [
            // a null entry, which computeDesktopOccupancy's tests can't reach
            { tag: "null-window", window: null, uuid: "a", exp: false },
            { tag: "undefined-window", window: undefined, uuid: "a", exp: false },
            // a real window on its desktop occupies it; a miss / empty / missing list does not.
            { tag: "desktops-match", window: occ({ desktops: ["a", "b"] }), uuid: "a", exp: true },
            { tag: "desktops-miss", window: occ({ desktops: ["b"] }), uuid: "a", exp: false },
            { tag: "desktops-undefined", window: occ({}), uuid: "a", exp: false },
            { tag: "empty-desktops-array", window: occ({ desktops: [] }), uuid: "a", exp: false },
            // non-window (launcher/panel) never occupies, even with a matching desktops list.
            { tag: "non-window-excluded", window: occ({ isWindow: false, desktops: ["a"] }), uuid: "a", exp: false },
            // unlike windowIsOnDesktop, a window on every desktop doesn't count
            { tag: "on-all-excluded", window: occ({ onAll: true, desktops: ["a"] }), uuid: "a", exp: false },
            { tag: "on-all-excluded-no-desktops", window: occ({ onAll: true }), uuid: "a", exp: false },
            // skipPager (hidden from the pager) is excluded too.
            { tag: "skip-pager-excluded", window: occ({ skipPager: true, desktops: ["a"] }), uuid: "a", exp: false },
            // a minimised window still counts
            { tag: "minimized-still-counts", window: occ({ minimized: true, desktops: ["a"] }), uuid: "a", exp: true },
            // a raw object without isWindow is excluded, even with a matching list
            { tag: "isWindow-missing", window: { desktops: ["a"] }, uuid: "a", exp: false }
        ];
    }
    function test_windowOccupiesDesktop(data) {
        var result = Logic.windowOccupiesDesktop(data.window, data.uuid);
        compare(result, data.exp, data.tag);
        compare(typeof result, "boolean", data.tag + " (strict boolean)");
    }

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
            // undefined ids, and an empty windows array rather than null
            { tag: "undefined-ids", windows: [w("A", ["a"])], ids: undefined, exp: [] },
            {
                tag: "empty-windows-array", windows: [], ids: ["a", "b"],
                exp: [{ visible: [], minimized: [] }, { visible: [], minimized: [] }]
            },
            // minimised and on every desktop: in every desktop's minimised list
            {
                tag: "on-all-and-minimized", windows: [w("M", [], { onAll: true, minimized: true })], ids: ["a", "b"],
                exp: [{ visible: [], minimized: ["M"] }, { visible: [], minimized: ["M"] }]
            },
            // a window on two desktops appears in both their buckets, but not a third.
            {
                tag: "window-on-multiple-desktops", windows: [w("Multi", ["a", "b"])], ids: ["a", "b", "c"],
                exp: [{ visible: ["Multi"], minimized: [] }, { visible: ["Multi"], minimized: [] }, { visible: [], minimized: [] }]
            },
            // a missing title stays undefined for the aggregator's translated fallback; JSON shows it as null
            {
                tag: "missing-title", windows: [w(undefined, ["a"])], ids: ["a"],
                exp: [{ visible: [undefined], minimized: [] }]
            }
        ];
    }
    function test_groupWindowsByDesktop(data) {
        compare(JSON.stringify(Logic.groupWindowsByDesktop(data.windows, data.ids)), JSON.stringify(data.exp), data.tag);
    }

    function test_computeDesktopOccupancy_data() {
        const occ = function (desktops, opts) {
            opts = opts || {};
            return { isWindow: opts.isWindow !== false, onAll: opts.onAll === true, skipPager: opts.skipPager === true, minimized: opts.minimized === true, desktops: desktops };
        };
        return [
            // transient/degenerate inputs degrade to [] or all-false, never throw.
            { tag: "empty-ids", windows: [occ(["a"])], ids: [], exp: [] },
            { tag: "null-ids", windows: [occ(["a"])], ids: null, exp: [] },
            { tag: "undefined-ids", windows: [occ(["a"])], ids: undefined, exp: [] },
            { tag: "null-windows-all-false", windows: null, ids: ["a", "b"], exp: [false, false] },
            { tag: "empty-windows-all-false", windows: [], ids: ["a", "b"], exp: [false, false] },
            // a window pins exactly its desktop; alignment is by index.
            { tag: "membership-and-alignment", windows: [occ(["a"]), occ(["b"])], ids: ["a", "b"], exp: [true, true] },
            { tag: "not-on-this-desktop", windows: [occ(["b"])], ids: ["a"], exp: [false] },
            { tag: "empty-desktops-array", windows: [occ([])], ids: ["a"], exp: [false] },
            // the three exclusions: on-all (would pin everything), skipPager (hidden), non-window (launcher).
            { tag: "on-all-excluded", windows: [occ([], { onAll: true })], ids: ["a", "b"], exp: [false, false] },
            { tag: "skip-pager-excluded", windows: [occ(["a"], { skipPager: true })], ids: ["a"], exp: [false] },
            { tag: "non-window-excluded", windows: [occ(["a"], { isWindow: false })], ids: ["a"], exp: [false] },
            // the one inclusion that differs from the exclusions: a minimized window still occupies.
            { tag: "minimized-counts", windows: [occ(["a"], { minimized: true })], ids: ["a"], exp: [true] },
            // a window on two desktops pins both, not a third.
            { tag: "window-on-multiple-desktops", windows: [occ(["a", "b"])], ids: ["a", "b", "c"], exp: [true, true, false] },
            // mixed: one visible, one minimized, a trailing empty.
            { tag: "mixed", windows: [occ(["a"]), occ(["b"], { minimized: true })], ids: ["a", "b", "c"], exp: [true, true, false] }
        ];
    }
    function test_computeDesktopOccupancy(data) {
        compare(JSON.stringify(Logic.computeDesktopOccupancy(data.windows, data.ids)), JSON.stringify(data.exp), data.tag);
    }

    function test_windowOccupiesDesktopOnScreen_data() {
        const A = { x: 0, y: 0, width: 1920, height: 1080 };       // monitor 1
        const B = { x: 1920, y: 0, width: 1920, height: 1080 };    // monitor 2 (different origin)
        const Ahidpi = { x: 0, y: 0, width: 3840, height: 2160 };  // same origin as A, larger size (scaling)
        const occ = function (desktops, screen, opts) {
            opts = opts || {};
            return {
                isWindow: opts.isWindow !== false, onAll: opts.onAll === true,
                skipPager: opts.skipPager === true, minimized: opts.minimized === true,
                desktops: desktops, screen: screen
            };
        };
        return [
            // on the desktop and on this output → occupies; on another output → does not
            { tag: "same-screen-occupies", window: occ(["a"], A), uuid: "a", rect: A, exp: true },
            { tag: "other-screen-excluded", window: occ(["a"], B), uuid: "a", rect: A, exp: false },
            // origin matches but size differs (fractional/per-output scaling) → still this screen.
            { tag: "origin-match-different-size", window: occ(["a"], A), uuid: "a", rect: Ahidpi, exp: true },
            // the pager's rect unknown until it's placed → counts everywhere
            { tag: "null-target-rect-global", window: occ(["a"], B), uuid: "a", rect: null, exp: true },
            { tag: "zero-target-rect-global", window: occ(["a"], B), uuid: "a", rect: { x: 0, y: 0, width: 0, height: 0 }, exp: true },
            // unknown own screen (a window with no geometry) → counts everywhere
            { tag: "null-own-screen-counts", window: occ(["a"], null), uuid: "a", rect: A, exp: true },
            { tag: "zero-own-screen-counts", window: occ(["a"], { x: 5, y: 5, width: 0, height: 0 }), uuid: "a", rect: A, exp: true },
            // the desktop predicate still gates: a miss / exclusion is false even on the matching screen.
            { tag: "desktops-miss-on-screen", window: occ(["b"], A), uuid: "a", rect: A, exp: false },
            { tag: "on-all-excluded-on-screen", window: occ(["a"], A, { onAll: true }), uuid: "a", rect: A, exp: false },
            { tag: "skip-pager-excluded-on-screen", window: occ(["a"], A, { skipPager: true }), uuid: "a", rect: A, exp: false },
            { tag: "non-window-excluded-on-screen", window: occ(["a"], A, { isWindow: false }), uuid: "a", rect: A, exp: false },
            // a minimized window still occupies (matches windowOccupiesDesktop), localized to its screen.
            { tag: "minimized-still-counts-on-screen", window: occ(["a"], A, { minimized: true }), uuid: "a", rect: A, exp: true }
        ];
    }
    function test_windowOccupiesDesktopOnScreen(data) {
        var result = Logic.windowOccupiesDesktopOnScreen(data.window, data.uuid, data.rect);
        compare(result, data.exp, data.tag);
        compare(typeof result, "boolean", data.tag + " (strict boolean)");
    }

    function test_computeDesktopOccupancyForScreen_data() {
        const A = { x: 0, y: 0, width: 1920, height: 1080 };
        const B = { x: 1920, y: 0, width: 1920, height: 1080 };
        const Ahidpi = { x: 0, y: 0, width: 3840, height: 2160 };
        const occ = function (desktops, screen) {
            return { isWindow: true, onAll: false, skipPager: false, minimized: false, desktops: desktops, screen: screen };
        };
        return [
            // degenerate inputs degrade safely, like the global variant.
            { tag: "empty-ids", windows: [occ(["a"], A)], ids: [], rect: A, exp: [] },
            // a window on desktop a/monitor A and one on b/monitor B, viewed from each monitor.
            { tag: "from-screen-A", windows: [occ(["a"], A), occ(["b"], B)], ids: ["a", "b"], rect: A, exp: [true, false] },
            { tag: "from-screen-B", windows: [occ(["a"], A), occ(["b"], B)], ids: ["a", "b"], rect: B, exp: [false, true] },
            // origin-match with a different size (scaling) still occupies on this screen.
            { tag: "different-size-origin", windows: [occ(["a"], A)], ids: ["a"], rect: Ahidpi, exp: [true] },
            // a window with no own screen counts on every monitor (errs safe).
            { tag: "unknown-own-screen-everywhere", windows: [occ(["a"], null)], ids: ["a"], rect: B, exp: [true] },
            // index alignment across three desktops: only the matching desktop+screen pins.
            { tag: "index-alignment", windows: [occ(["b"], A)], ids: ["a", "b", "c"], rect: A, exp: [false, true, false] }
        ];
    }
    function test_computeDesktopOccupancyForScreen(data) {
        compare(JSON.stringify(Logic.computeDesktopOccupancyForScreen(data.windows, data.ids, data.rect)), JSON.stringify(data.exp), data.tag);
    }

    // Before the panel is placed, the answer has to be exactly the global one.
    function test_computeDesktopOccupancyForScreenDegradesToGlobal() {
        const A = { x: 0, y: 0, width: 1920, height: 1080 };
        const B = { x: 1920, y: 0, width: 1920, height: 1080 };
        const occ = function (desktops, screen) {
            return { isWindow: true, onAll: false, skipPager: false, minimized: false, desktops: desktops, screen: screen };
        };
        const windows = [occ(["a"], A), occ(["b"], B)];
        const ids = ["a", "b", "c"];
        const global = JSON.stringify(Logic.computeDesktopOccupancy(windows, ids));
        compare(JSON.stringify(Logic.computeDesktopOccupancyForScreen(windows, ids, null)), global, "null screenRect == global");
        compare(JSON.stringify(Logic.computeDesktopOccupancyForScreen(windows, ids, { x: 0, y: 0, width: 0, height: 0 })), global, "zero screenRect == global");
    }

    // A null window passes here; the desktop predicates reject it later.
    function test_windowIsOnActivity_data() {
        const act = function (activities) {
            return { isWindow: true, activities: activities };
        };
        return [
            { tag: "names-activity", window: act(["A"]), activity: "A", exp: true },
            { tag: "other-activity", window: act(["B"]), activity: "A", exp: false },
            { tag: "one-of-several", window: act(["B", "A"]), activity: "A", exp: true },
            { tag: "empty-list-everywhere", window: act([]), activity: "A", exp: true },
            { tag: "missing-list-everywhere", window: { isWindow: true }, activity: "A", exp: true },
            { tag: "null-uuid-everywhere", window: act([Logic.ALL_ACTIVITIES]), activity: "A", exp: true },
            { tag: "unknown-current-empty", window: act(["B"]), activity: "", exp: true },
            { tag: "unknown-current-undefined", window: act(["B"]), activity: undefined, exp: true },
            { tag: "null-window-passes", window: null, activity: "A", exp: true }
        ];
    }
    function test_windowIsOnActivity(data) {
        compare(Logic.windowIsOnActivity(data.window, data.activity), data.exp, data.tag);
    }

    function test_windowsOnActivity() {
        const windows = [
            { title: "a1", activities: ["A"] },
            { title: "b1", activities: ["B"] },
            { title: "everywhere", activities: [] },
            { title: "a2", activities: ["A"] }
        ];
        compare(Logic.windowsOnActivity(windows, "A").map(w => w.title).join(","), "a1,everywhere,a2", "filtered, in order");
        compare(Logic.windowsOnActivity(windows, "").length, windows.length, "unknown current activity keeps all");
        compare(JSON.stringify(Logic.windowsOnActivity(null, "A")), "[]", "null windows");
    }

    // #35: which reduction counts which windows.
    function test_reduceWindowSnapshot_data() {
        const A = { x: 0, y: 0, width: 1920, height: 1080 };
        const B = { x: 1920, y: 0, width: 1920, height: 1080 };
        const win = function (title, desktops, activities, screen) {
            return { title: title, minimized: false, onAll: false, isWindow: true, skipPager: false, desktops: desktops, activities: activities, screen: screen || null };
        };
        const listed = function (titles) {
            return { visible: titles, minimized: [] };
        };
        const allOn = function (activity, screenRect) {
            return { windowList: true, occupancy: true, dynamic: true, screenRect: screenRect || null, activity: activity };
        };
        // The reporter's layout: activity A uses desktops 1-3, the current activity B only desktop 1.
        const reporter = [win("a1", ["d1"], ["A"]), win("a2", ["d2"], ["A"]), win("a3", ["d3"], ["A"]), win("b1", ["d1"], ["B"])];
        const ids = ["d1", "d2", "d3", "d4"];
        return [
            { tag: "features-off-all-empty", windows: reporter, ids: ids,
                opts: { windowList: false, occupancy: false, dynamic: false, screenRect: null, activity: "B" },
                groups: [], occupancy: [], screenOccupancy: [] },
            { tag: "dynamic-spans-all-activities", windows: reporter, ids: ids, opts: allOn("B"),
                groups: [listed(["b1"]), listed([]), listed([]), listed([])],
                occupancy: [true, true, true, false],
                screenOccupancy: [true, false, false, false] },
            // null UUID and an empty list both mean "every activity", so they count in the current views too.
            { tag: "all-activities-window-counts-everywhere",
                windows: [win("pinned", ["d2"], [Logic.ALL_ACTIVITIES]), win("unassigned", ["d3"], [])], ids: ids, opts: allOn("B"),
                groups: [listed([]), listed(["pinned"]), listed(["unassigned"]), listed([])],
                occupancy: [false, true, true, false],
                screenOccupancy: [false, true, true, false] },
            // the screen filter still narrows the indicator; the tooltip and global occupancy ignore screens.
            { tag: "screen-and-activity-compose",
                windows: [win("b-here", ["d1"], ["B"], A), win("b-there", ["d2"], ["B"], B), win("a-here", ["d3"], ["A"], A)],
                ids: ["d1", "d2", "d3"], opts: allOn("B", A),
                groups: [listed(["b-here"]), listed(["b-there"]), listed([])],
                occupancy: [true, true, true],
                screenOccupancy: [true, false, false] },
            // ActivityInfo not ready yet: nothing is filtered, like the model itself.
            { tag: "unknown-current-activity-filters-nothing", windows: reporter, ids: ids, opts: allOn(""),
                groups: [listed(["a1", "b1"]), listed(["a2"]), listed(["a3"]), listed([])],
                occupancy: [true, true, true, false],
                screenOccupancy: [true, true, true, false] }
        ];
    }
    function test_reduceWindowSnapshot(data) {
        const r = Logic.reduceWindowSnapshot(data.windows, data.ids, data.opts);
        compare(JSON.stringify(r.groups), JSON.stringify(data.groups), data.tag + " groups");
        compare(JSON.stringify(r.occupancy), JSON.stringify(data.occupancy), data.tag + " occupancy");
        compare(JSON.stringify(r.screenOccupancy), JSON.stringify(data.screenOccupancy), data.tag + " screenOccupancy");
    }

    // #35 through the plan: counting only activity B removed d4, then d3, moving activity A's window to d2.
    function test_dynamicPlanKeepsOtherActivitiesDesktops() {
        const win = function (desktops, activities) {
            return { isWindow: true, onAll: false, skipPager: false, minimized: false, desktops: desktops, activities: activities, screen: null };
        };
        const windows = [win(["d1"], ["A"]), win(["d2"], ["A"]), win(["d3"], ["A"]), win(["d1"], ["B"])];
        const ids = ["d1", "d2", "d3", "d4"];
        const r = Logic.reduceWindowSnapshot(windows, ids, { windowList: false, occupancy: true, dynamic: true, screenRect: null, activity: "B" });
        compare(Logic.dynamicWorkspacePlan(r.occupancy, ids), null, "no trim while activity A still uses d1-d3");
        compare(JSON.stringify(Logic.dynamicWorkspacePlan(r.screenOccupancy, ids)), JSON.stringify({ kind: "remove", uuid: "d4" }),
            "the current-activity view alone would trim (the #35 bug)");
    }

    function test_dynamicWorkspacePlan_data() {
        return [
            // guards: absent arrays, empty set, or an occupancy snapshot that lags the desktop set.
            { tag: "null-occupancy", occ: null, ids: ["a"], exp: null },
            { tag: "null-ids", occ: [false], ids: null, exp: null },
            { tag: "empty-ids", occ: [], ids: [], exp: null },
            { tag: "length-mismatch", occ: [false], ids: ["a", "b"], exp: null },
            // n==1: keep the single empty (never remove the last); add when it fills.
            { tag: "single-empty-noop", occ: [false], ids: ["a"], exp: null },
            { tag: "single-occupied-add", occ: [true], ids: ["a"], exp: { kind: "add" } },
            // 0 trailing empties -> add (the last desktop is occupied), regardless of a leading empty.
            { tag: "last-occupied-add", occ: [true, true], ids: ["a", "b"], exp: { kind: "add" } },
            { tag: "no-trailing-empty-add", occ: [false, true], ids: ["a", "b"], exp: { kind: "add" } },
            // exactly one trailing empty is the fixpoint -> no-op.
            { tag: "one-trailing-empty-noop", occ: [true, false], ids: ["a", "b"], exp: null },
            // >=2 trailing empties -> remove the last; the next round removes the rest
            { tag: "two-trailing-trim-last", occ: [true, false, false], ids: ["a", "b", "c"], exp: { kind: "remove", uuid: "c" } },
            { tag: "all-empty-trim-last", occ: [false, false], ids: ["a", "b"], exp: { kind: "remove", uuid: "b" } },
            // an empty desktop in the middle is left alone
            { tag: "empty-middle-left-alone", occ: [false, true, false], ids: ["a", "b", "c"], exp: null },
            // a leading empty + a 2-deep trailing run still just trims the tail (not the middle).
            { tag: "leading-empty-trims-tail", occ: [false, true, false, false], ids: ["a", "b", "c", "d"], exp: { kind: "remove", uuid: "d" } }
        ];
    }
    function test_dynamicWorkspacePlan(data) {
        compare(JSON.stringify(Logic.dynamicWorkspacePlan(data.occ, data.ids)), JSON.stringify(data.exp), data.tag);
    }

    function test_formatDynamicDesktopName_data() {
        return [
            { tag: "custom-prefix", prefix: "Workspace", number: 3, fallback: "Desktop", exp: "Workspace 3" },
            { tag: "blank-uses-fallback", prefix: "", number: 2, fallback: "Desktop", exp: "Desktop 2" },
            { tag: "whitespace-uses-fallback", prefix: "   ", number: 5, fallback: "Desktop", exp: "Desktop 5" },
            { tag: "prefix-trimmed", prefix: "  Web  ", number: 4, fallback: "Desktop", exp: "Web 4" },
            // a localized fallback (non-English main.qml i18n) is honoured when the prefix is blank.
            { tag: "localized-fallback", prefix: "", number: 2, fallback: "Bureau", exp: "Bureau 2" },
            // with both blank, the literal "Desktop" keeps the name from being empty
            { tag: "all-blank-last-resort", prefix: "", number: 1, fallback: "", exp: "Desktop 1" }
        ];
    }
    function test_formatDynamicDesktopName(data) {
        compare(Logic.formatDynamicDesktopName(data.prefix, data.number, data.fallback), data.exp, data.tag);
    }
    function test_formatDynamicDesktopNameCapsPrefix() {
        // the prefix is capped at 100 chars (sanitizeDesktopName) before the number is appended.
        var longPrefix = new Array(150).join("a");   // 149 'a's
        compare(Logic.formatDynamicDesktopName(longPrefix, 7, "Desktop"), new Array(101).join("a") + " 7", "prefix capped at 100, then ' 7'");
    }

    // The registry's keys are object keys, so strings the function has to compare as numbers.
    function test_electDynamicWriter_data() {
        return [
            { tag: "null", reg: null, exp: -1 },
            { tag: "empty", reg: {}, exp: -1 },
            { tag: "none-enabled", reg: { "1": false, "2": false }, exp: -1 },
            { tag: "one-enabled", reg: { "1": true }, exp: 1 },
            { tag: "lowest-enabled-wins", reg: { "1": true, "2": true }, exp: 1 },
            { tag: "skip-disabled-lower", reg: { "1": false, "2": true }, exp: 2 },
            { tag: "numeric-min-not-insertion", reg: { "2": true, "1": true }, exp: 1 },
            { tag: "mixed", reg: { "3": false, "1": false, "2": true, "4": true }, exp: 2 }
        ];
    }
    function test_electDynamicWriter(data) {
        compare(Logic.electDynamicWriter(data.reg), data.exp, data.tag);
    }

    // Made-up role numbers; the aggregator passes the real TasksModel ones.
    function test_dataChangeAffectsRoles_data() {
        var relevant = [0, 5, 6, 7, 8];          // e.g. DisplayRole(0) + the four taskmanager roles read
        return [
            { tag: "empty-means-all-rebuilds", changed: [], relevant: relevant, exp: true },
            { tag: "null-rebuilds", changed: null, relevant: relevant, exp: true },
            { tag: "undefined-rebuilds", changed: undefined, relevant: relevant, exp: true },
            { tag: "display-role-rebuilds", changed: [0], relevant: relevant, exp: true },
            { tag: "relevant-role-rebuilds", changed: [6], relevant: relevant, exp: true },
            // a change limited to roles rebuild() never reads (e.g. IsActive on focus) is skipped.
            { tag: "only-irrelevant-skips", changed: [3], relevant: relevant, exp: false },
            { tag: "all-irrelevant-skips", changed: [3, 4, 9], relevant: relevant, exp: false },
            // a relevant role anywhere in the list, even last
            { tag: "mixed-rebuilds", changed: [3, 6], relevant: relevant, exp: true },
            { tag: "relevant-last-rebuilds", changed: [3, 4, 8], relevant: relevant, exp: true },
            // an empty relevant set: nothing is relevant, so only the empty-"all" case still rebuilds.
            { tag: "no-relevant-roles-skips", changed: [0], relevant: [], exp: false },
            { tag: "no-relevant-empty-changed-rebuilds", changed: [], relevant: [], exp: true }
        ];
    }
    function test_dataChangeAffectsRoles(data) {
        compare(Logic.dataChangeAffectsRoles(data.changed, data.relevant), data.exp, data.tag);
    }

    function test_defaults_data() {
        return [
            { tag: "enableScroll", key: "enableScroll", exp: true },
            { tag: "scrollWrap", key: "scrollWrap", exp: false },
            { tag: "invertScroll", key: "invertScroll", exp: false },
            { tag: "pillClickAction", key: "pillClickAction", exp: 0 },
            { tag: "pillClickAnywhere", key: "pillClickAnywhere", exp: true },
            { tag: "showTooltips", key: "showTooltips", exp: true },
            { tag: "showWindowList", key: "showWindowList", exp: true },
            { tag: "enableAddRemove", key: "enableAddRemove", exp: true },
            { tag: "enableRename", key: "enableRename", exp: true },
            { tag: "dynamicWorkspaces", key: "dynamicWorkspaces", exp: false },
            { tag: "dynamicNamePrefix", key: "dynamicNamePrefix", exp: "" },
            { tag: "animationDuration", key: "animationDuration", exp: 0 },
            { tag: "dotStyle", key: "dotStyle", exp: 0 },
            { tag: "singleLine", key: "singleLine", exp: false },
            { tag: "matchDesktopGrid", key: "matchDesktopGrid", exp: false },
            { tag: "dotSize", key: "dotSize", exp: 0 },
            { tag: "pillSize", key: "pillSize", exp: 0 },
            { tag: "spacingFactor", key: "spacingFactor", exp: 0.5 },
            { tag: "pillWidthFactor", key: "pillWidthFactor", exp: 3.5 },
            { tag: "inactiveOpacity", key: "inactiveOpacity", exp: 0.45 },
            { tag: "hoverOpacity", key: "hoverOpacity", exp: 0.8 },
            { tag: "showHoverBackground", key: "showHoverBackground", exp: true },
            { tag: "hoverBackgroundOpacity", key: "hoverBackgroundOpacity", exp: 0.12 },
            { tag: "hoverLengthFactor", key: "hoverLengthFactor", exp: 1.0 },
            { tag: "hoverThicknessFactor", key: "hoverThicknessFactor", exp: 1.0 },
            { tag: "showOccupancy", key: "showOccupancy", exp: false },
            { tag: "occupiedOpacity", key: "occupiedOpacity", exp: 0.7 },
            { tag: "occupancyStyle", key: "occupancyStyle", exp: 0 },
            { tag: "followThemeColors", key: "followThemeColors", exp: true },
            { tag: "activeColor", key: "activeColor", exp: "#3daee9" },
            { tag: "inactiveColor", key: "inactiveColor", exp: "#eff0f1" },
            { tag: "occupiedColor", key: "occupiedColor", exp: "#3daee9" },
            { tag: "hoverBackgroundColor", key: "hoverBackgroundColor", exp: "#eff0f1" },
            { tag: "wheelNotchDelta", key: "wheelNotchDelta", exp: 120 }
        ];
    }
    function test_defaults(data) {
        compare(Logic.DEFAULTS[data.key], data.exp, data.tag);
    }

    // Every pager shares DEFAULTS. A write to a frozen object is ignored, or throws under "use strict".
    function test_defaultsAreFrozen() {
        verify(Object.isFrozen(Logic.DEFAULTS), "Logic.DEFAULTS must be frozen");
        try { Logic.DEFAULTS.dotSize = 999; } catch (e) { /* strict-mode TypeError is expected */ }
        compare(Logic.DEFAULTS.dotSize, 0, "a frozen DEFAULTS ignores writes");
    }

    // An equality, so a key that goes missing fails here too.
    function test_defaultsKeySet() {
        var keys = Object.keys(Logic.DEFAULTS).sort();
        var expected = ["activeColor", "animationDuration", "dotSize", "dotStyle", "dynamicNamePrefix",
                        "dynamicWorkspaces", "enableAddRemove", "enableRename",
                        "enableScroll", "followThemeColors", "hoverBackgroundColor", "hoverBackgroundOpacity",
                        "hoverLengthFactor", "hoverOpacity", "hoverThicknessFactor", "inactiveColor",
                        "inactiveOpacity", "invertScroll", "matchDesktopGrid", "occupancyStyle", "occupiedColor", "occupiedOpacity",
                        "pillClickAction", "pillClickAnywhere", "pillSize", "pillWidthFactor", "scrollWrap",
                        "showHoverBackground", "showOccupancy", "showTooltips",
                        "showWindowList", "singleLine", "spacingFactor", "wheelNotchDelta"].sort();
        compare(keys.length, 34, "DEFAULTS has exactly 34 keys");
        compare(JSON.stringify(keys), JSON.stringify(expected), "the exact DEFAULTS key set is pinned");
    }

    // The schema and its mirror are kept equal by hand, and nothing else checks them.
    function test_mainXmlDefaultsMatchLogicDefaults() {
        // Resolved against this test file.
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "../../package/contents/config/main.xml", false);
        xhr.send();
        var xml = xhr.responseText;
        verify(xml && xml.length > 0, "main.xml is readable");

        // Non-greedy, so each entry pairs with its own <default>; an empty one gives "".
        var re = /<entry\s+name="([^"]+)"\s+type="([^"]+)"\s*>[\s\S]*?<default>([\s\S]*?)<\/default>/g;
        var seen = 0;
        var m;
        while ((m = re.exec(xml)) !== null) {
            var name = m[1], type = m[2], raw = m[3];
            ++seen;
            verify(Logic.DEFAULTS.hasOwnProperty(name), "main.xml entry '" + name + "' exists in Logic.DEFAULTS");
            var expected = Logic.DEFAULTS[name];
            switch (type) {
            case "Bool":
                compare(raw === "true", expected, name + " (Bool) default matches");
                break;
            case "Int":
                compare(parseInt(raw, 10), expected, name + " (Int) default matches");
                break;
            case "Double":
                // parsed and literal floats can differ by a rounding error
                verify(Math.abs(parseFloat(raw) - expected) <= 1e-9, name + " (Double) default matches");
                break;
            case "Color":
                // hex colours, in either case
                compare(raw.toLowerCase(), String(expected).toLowerCase(), name + " (Color) default matches");
                break;
            case "String":
                compare(raw, expected, name + " (String) default matches");
                break;
            default:
                verify(false, "unhandled main.xml entry type '" + type + "' for '" + name + "'");
            }
        }
        // A pattern that missed an entry would skip it in silence; wheelNotchDelta has none.
        compare(seen, Object.keys(Logic.DEFAULTS).length - 1, "every main.xml entry was checked (all but wheelNotchDelta)");
    }

    // KWin drops a call with a wrong string or type without an error, so each spec is pinned by value.
    function test_switchSpec_data() {
        return [
            // the ids can be empty for a frame
            { tag: "empty-uuid-null", uuid: "", exp: null },
            { tag: "undefined-uuid-null", uuid: undefined, exp: null },
            {
                tag: "valid", uuid: "uuid-a",
                exp: {
                    service: "org.kde.KWin", path: "/VirtualDesktopManager",
                    iface: "org.freedesktop.DBus.Properties", member: "Set",
                    // Set(ssv): the interface, "current", and a variant of the plain uuid
                    args: [{ t: "s", v: "org.kde.KWin.VirtualDesktopManager" }, { t: "s", v: "current" }, { t: "v", v: "uuid-a" }]
                }
            }
        ];
    }
    function test_switchSpec(data) {
        compare(JSON.stringify(Logic.switchSpec(data.uuid)), JSON.stringify(data.exp), data.tag);
    }

    function test_addSpec() {
        var exp = {
            service: "org.kde.KWin", path: "/VirtualDesktopManager",
            iface: "org.kde.KWin.VirtualDesktopManager", member: "createDesktop",
            args: [{ t: "u", v: 3 }, { t: "s", v: "New Desktop" }]
        };
        compare(JSON.stringify(Logic.addSpec(3, "New Desktop")), JSON.stringify(exp), "createDesktop(uint32 position, string name)");
    }
    function test_addSpecCoercesArgs() {
        // a count not there yet still reaches the uint32 as an integer, and the name as a string
        compare(Logic.addSpec(undefined, "X").args[0].v, 0, "undefined position coerces to 0");
        compare(Logic.addSpec(2.9, "X").args[0].v, 2, "fractional position truncates via |0");
        compare(Logic.addSpec(0, 42).args[1].v, "42", "name is stringified");
    }

    function test_removeSpec_data() {
        return [
            { tag: "empty-uuid-null", uuid: "", count: 3, exp: null },
            // the last desktop stays
            { tag: "last-desktop-null", uuid: "uuid-a", count: 1, exp: null },
            { tag: "zero-count-null", uuid: "uuid-a", count: 0, exp: null },
            {
                tag: "valid", uuid: "uuid-a", count: 2,
                exp: {
                    service: "org.kde.KWin", path: "/VirtualDesktopManager",
                    iface: "org.kde.KWin.VirtualDesktopManager", member: "removeDesktop",
                    args: [{ t: "s", v: "uuid-a" }]
                }
            }
        ];
    }
    function test_removeSpec(data) {
        compare(JSON.stringify(Logic.removeSpec(data.uuid, data.count)), JSON.stringify(data.exp), data.tag);
    }

    function test_renameSpec_data() {
        return [
            { tag: "empty-uuid-null", uuid: "", name: "Web", exp: null },
            // a blank name renames nothing
            { tag: "empty-name-null", uuid: "uuid-a", name: "", exp: null },
            { tag: "whitespace-name-null", uuid: "uuid-a", name: "   ", exp: null },
            {
                tag: "valid-trims", uuid: "uuid-a", name: "  Web  ",
                exp: {
                    service: "org.kde.KWin", path: "/VirtualDesktopManager",
                    iface: "org.kde.KWin.VirtualDesktopManager", member: "setDesktopName",
                    args: [{ t: "s", v: "uuid-a" }, { t: "s", v: "Web" }]
                }
            }
        ];
    }
    function test_renameSpec(data) {
        compare(JSON.stringify(Logic.renameSpec(data.uuid, data.name)), JSON.stringify(data.exp), data.tag);
    }
    function test_renameSpecCapsLength() {
        // the spec carries the capped name
        var longName = new Array(150).join("a");   // 149 'a's
        compare(Logic.renameSpec("uuid-a", longName).args[1].v.length, 100, "renameSpec caps the name at 100 chars");
    }

    function test_invokeShortcutSpec_data() {
        return [
            { tag: "empty-name-null", name: "", exp: null },
            { tag: "undefined-name-null", name: undefined, exp: null },
            {
                tag: "valid", name: "Overview",
                exp: {
                    service: "org.kde.kglobalaccel", path: "/component/kwin",
                    iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
                    args: [{ t: "s", v: "Overview" }]
                }
            }
        ];
    }
    function test_invokeShortcutSpec(data) {
        compare(JSON.stringify(Logic.invokeShortcutSpec(data.name)), JSON.stringify(data.exp), data.tag);
    }

    function test_pillClickSpec_data() {
        return [
            { tag: "None-null", action: Logic.PILL_CLICK_ACTION.None, exp: null },
            { tag: "unknown-null", action: 99, exp: null },
            {
                tag: "ShowDesktop", action: Logic.PILL_CLICK_ACTION.ShowDesktop,
                exp: {
                    service: "org.kde.kglobalaccel", path: "/component/kwin",
                    iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
                    args: [{ t: "s", v: "Show Desktop" }]
                }
            },
            {
                tag: "Overview", action: Logic.PILL_CLICK_ACTION.Overview,
                exp: {
                    service: "org.kde.kglobalaccel", path: "/component/kwin",
                    iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
                    args: [{ t: "s", v: "Overview" }]
                }
            },
            {
                tag: "Grid", action: Logic.PILL_CLICK_ACTION.Grid,
                exp: {
                    service: "org.kde.kglobalaccel", path: "/component/kwin",
                    iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
                    args: [{ t: "s", v: "Grid View" }]
                }
            }
        ];
    }
    function test_pillClickSpec(data) {
        compare(JSON.stringify(Logic.pillClickSpec(data.action)), JSON.stringify(data.exp), data.tag);
    }

    // The shipped default is the toggle on and the action Nothing, which mustn't swallow clicks.
    function test_pillClickAnywhereActive_data() {
        return [
            { tag: "on-with-action", anywhere: true, action: Logic.PILL_CLICK_ACTION.Overview, exp: true },
            { tag: "on-but-no-action", anywhere: true, action: Logic.PILL_CLICK_ACTION.None, exp: false },
            { tag: "off-with-action", anywhere: false, action: Logic.PILL_CLICK_ACTION.ShowDesktop, exp: false },
            { tag: "off-and-no-action", anywhere: false, action: Logic.PILL_CLICK_ACTION.None, exp: false },
            // an unknown index isn't None, so the target stays on; pillClickSpec makes the click do nothing
            { tag: "unknown-action", anywhere: true, action: 99, exp: true },
            // a setting that reads back undefined for a frame
            { tag: "undefined-toggle", anywhere: undefined, action: Logic.PILL_CLICK_ACTION.Grid, exp: false }
        ];
    }
    function test_pillClickAnywhereActive(data) {
        compare(Logic.pillClickAnywhereActive(data.anywhere, data.action), data.exp, data.tag);
    }
}
