/*
 * Plasma Gnome Pager — tst_logic.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT tests for the pure-JS logic tier (package/contents/ui/logic.js), imported directly with NO
 * Plasma/Kirigami dependency — the cheapest, most exhaustive tier for the branching logic (clamp/wrap,
 * wheel accumulation, never-remove-last, …). Run with `make check-unit`.
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
            // the count/current guards run BEFORE the wrap branch, so OOB current is -1 even with wrap.
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

    // resolveCurrentDesktop: prefer the per-screen value (Plasma 6.7), else fall back to the global
    // current when it's missing (undefined/null/"" ). Both empty → "" (the no-source state).
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

            // negative deltas (wheel up): (total / t) | 0 truncates TOWARD zero, so step and remainder are
            // both negative — the upward-scroll path.
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

    // --- dotOpacity: active > hover > occupied-marker(Filled/Ring) > dim (empty, or the InnerDot body) ---
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
            // InnerDot and Ring keep a DIM body — their markers are overlays that carry occupiedOpacity themselves.
            { tag: "occupied-ring-body-stays-dim", active: false, hovered: false, occupied: true, style: Logic.OCCUPANCY.Ring, exp: 0.45 },
            { tag: "occupied-innerdot-body-stays-dim", active: false, hovered: false, occupied: true, style: Logic.OCCUPANCY.InnerDot, exp: 0.45 }
        ];
    }
    function test_dotOpacity(data) {
        fuzzyCompare(Logic.dotOpacity(data.active, data.hovered, data.occupied, data.style, 0.45, 0.8, 0.7), data.exp, 0.001, data.tag);
    }

    // The opacities are parameters, not constants: a non-default inactive/hover/occupied triple flows
    // through, and the tier order holds (active > hover > occupied-marker > dim).
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

    // --- dotColor: resolves the dot BODY colour from three pre-resolved colours (active / inactive / occupied) ---
    // Distinct string sentinels stand in for the colours so each branch is identifiable.
    function test_dotColor_data() {
        var F = Logic.OCCUPANCY.Filled;
        return [
            { tag: "active", active: true, occupied: false, style: F, exp: "active" },
            { tag: "empty-inactive", active: false, occupied: false, style: F, exp: "inactive" },
            // Filled: the occupied dot BODY takes the occupied colour.
            { tag: "filled-occupied", active: false, occupied: true, style: F, exp: "occupied" },
            // InnerDot / Ring: the BODY stays the inactive colour (the marker is the inner dot / the border).
            { tag: "innerdot-occupied-body", active: false, occupied: true, style: Logic.OCCUPANCY.InnerDot, exp: "inactive" },
            { tag: "ring-occupied-body", active: false, occupied: true, style: Logic.OCCUPANCY.Ring, exp: "inactive" }
        ];
    }
    function test_dotColor(data) {
        compare(Logic.dotColor(data.active, data.occupied, data.style, "active", "inactive", "occupied"), data.exp, data.tag);
    }

    // --- occupancy styles: the shape predicates + the index mapping (mirrors main.xml / the combo order) ---
    function test_occupancyConstants() {
        compare(Logic.OCCUPANCY.Filled, 0, "Filled is index 0 (the default)");
        compare(Logic.OCCUPANCY.InnerDot, 1, "InnerDot is index 1");
        compare(Logic.OCCUPANCY.Ring, 2, "Ring is index 2");
    }

    // Pill-click action indices mirror main.xml pillClickAction + the ConfigGeneral combo order.
    function test_pillClickConstants() {
        compare(Logic.PILL_CLICK_ACTION.None, 0, "None is index 0 (the default)");
        compare(Logic.PILL_CLICK_ACTION.ShowDesktop, 1, "ShowDesktop is index 1");
        compare(Logic.PILL_CLICK_ACTION.Overview, 2, "Overview is index 2");
        compare(Logic.PILL_CLICK_ACTION.Grid, 3, "Grid is index 3");
    }

    // Pager-style indices mirror main.xml dotStyle + the ConfigAppearance combo order.
    function test_dotStyleConstants() {
        compare(Logic.DOT_STYLE.Pill, 0, "Pill is index 0 (the default)");
        compare(Logic.DOT_STYLE.Ring, 1, "Ring (Filled & ring) is index 1");
    }

    // isRingStyle: true only for the Filled & ring pager look (the one DOT_STYLE.Ring comparison).
    function test_isRingStyle() {
        verify(Logic.isRingStyle(Logic.DOT_STYLE.Ring), "Ring style → true");
        verify(!Logic.isRingStyle(Logic.DOT_STYLE.Pill), "Pill style → false");
    }

    // ringThickness: ring outline width = round(dotSize * 0.18), floored at 1px so a tiny dot still shows a ring.
    function test_ringThickness() {
        compare(Logic.ringThickness(100), 18, "100 → 18 (0.18×)");
        compare(Logic.ringThickness(16), 3, "16 → 3 (rounded)");
        compare(Logic.ringThickness(2), 1, "2 → 1 (min-1 clamp, not 0)");
        compare(Logic.ringThickness(0), 1, "0 → 1 (min-1 clamp)");
    }

    // innerDotDiameter: the InnerDot occupancy marker is a fixed fraction (0.45×) of the dot diameter
    // (no round/floor, unlike ringThickness — it renders the centre dot directly).
    function test_innerDotDiameter() {
        fuzzyCompare(Logic.innerDotDiameter(100), 45, 0.001, "100 → 45 (0.45×)");
        fuzzyCompare(Logic.innerDotDiameter(16), 7.2, 0.001, "16 → 7.2");
        fuzzyCompare(Logic.innerDotDiameter(0), 0, 0.001, "0 → 0");
    }

    // ringOverlayVisible: ONLY an OCCUPIED inactive dot in the Ring occupancy style (and NOT the Filled & ring dot-style) shows the ring overlay.
    function test_ringOverlayVisible() {
        var pill = Logic.DOT_STYLE.Pill;
        verify(Logic.ringOverlayVisible(false, true, Logic.OCCUPANCY.Ring, pill), "Ring + inactive + occupied → ring overlay");
        verify(!Logic.ringOverlayVisible(false, false, Logic.OCCUPANCY.Ring, pill), "Ring + empty → no overlay");
        verify(!Logic.ringOverlayVisible(true, true, Logic.OCCUPANCY.Ring, pill), "Ring + active → no overlay (it's the pill)");
        verify(!Logic.ringOverlayVisible(false, true, Logic.OCCUPANCY.Filled, pill), "non-Ring style → no ring overlay");
        // Suppressed in the Filled & ring dot-style: the body is ALREADY a ring, so the overlay would be redundant.
        verify(!Logic.ringOverlayVisible(false, true, Logic.OCCUPANCY.Ring, Logic.DOT_STYLE.Ring), "Filled & ring dot-style → ring overlay suppressed");
    }

    // innerDotVisible: ONLY an occupied inactive dot in the InnerDot style shows the centre dot.
    function test_innerDotVisible() {
        verify(Logic.innerDotVisible(false, true, Logic.OCCUPANCY.InnerDot), "InnerDot + inactive + occupied → centre dot");
        verify(!Logic.innerDotVisible(false, false, Logic.OCCUPANCY.InnerDot), "InnerDot + empty → no centre dot");
        verify(!Logic.innerDotVisible(true, true, Logic.OCCUPANCY.InnerDot), "InnerDot + active → no centre dot (it's the pill)");
        verify(!Logic.innerDotVisible(false, true, Logic.OCCUPANCY.Ring), "non-InnerDot style → no centre dot");
    }

    // dotHasRing: a dot draws the ring OUTLINE only for a non-current dot in the Filled & ring style
    // (independent of occupancy). Always false in the Pill style and for the current dot.
    function test_dotHasRing() {
        verify(!Logic.dotHasRing(Logic.DOT_STYLE.Pill, false), "Pill style → no ring outline");
        verify(!Logic.dotHasRing(Logic.DOT_STYLE.Pill, true), "Pill style + active → no ring outline");
        verify(Logic.dotHasRing(Logic.DOT_STYLE.Ring, false), "Ring style + non-current → ring outline");
        verify(!Logic.dotHasRing(Logic.DOT_STYLE.Ring, true), "Ring style + current → no outline (filled circle)");
    }

    // dotBodyIsHollow: the dot's INTERIOR is transparent ONLY in the Filled & ring dot-style for a
    // non-current dot, and NOT when the Filled occupancy marker is filling its interior. Always false in
    // the Pill style. (The ring OUTLINE is dotHasRing — decoupled, so occupied+Filled keeps its outline.)
    function test_dotBodyIsHollow_data() {
        var Pill = Logic.DOT_STYLE.Pill, Ring = Logic.DOT_STYLE.Ring;
        var F = Logic.OCCUPANCY.Filled, I = Logic.OCCUPANCY.InnerDot, R = Logic.OCCUPANCY.Ring;
        return [
            // Pill style: never hollow, whatever the occupancy.
            { tag: "pill-inactive", style: Pill, active: false, occupied: false, occ: F, exp: false },
            { tag: "pill-active", style: Pill, active: true, occupied: false, occ: F, exp: false },
            { tag: "pill-occupied-filled", style: Pill, active: false, occupied: true, occ: F, exp: false },
            // Ring style.
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

    // dotBodyFilled: the third ring body state — a ring OUTLINE plus a filled interior. True ONLY for a
    // non-current Filled-occupied dot in the Filled & ring style (= hasRing && !bodyIsHollow). False
    // everywhere in the Pill style, for the current dot (filled circle, no outline), and for a hollow ring.
    function test_dotBodyFilled() {
        var Pill = Logic.DOT_STYLE.Pill, Ring = Logic.DOT_STYLE.Ring;
        var F = Logic.OCCUPANCY.Filled, I = Logic.OCCUPANCY.InnerDot;
        verify(Logic.dotBodyFilled(Ring, false, true, F), "Ring + non-current + occupied + Filled → ring outline + filled interior");
        verify(!Logic.dotBodyFilled(Ring, false, false, F), "Ring + empty → hollow, not filled");
        verify(!Logic.dotBodyFilled(Ring, false, true, I), "Ring + occupied + InnerDot → hollow (marker is an overlay)");
        verify(!Logic.dotBodyFilled(Ring, true, true, F), "Ring + current → filled circle, but no ring outline → not 'ring filled'");
        verify(!Logic.dotBodyFilled(Pill, false, true, F), "Pill style → never a filled ring");
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

    // --- arraysShallowEqual: skip a `var` reassignment whose flat-primitive contents are identical -
    // The aggregator uses this to avoid notifying on an unchanged occupancy/tooltip snapshot (a QML
    // `var` write always fires its change signal). Element-wise strict compare; identity/null/length
    // guarded; two empty arrays are equal. NOT recursive — nested arrays compare by reference only.
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
            // strict !== compare: distinct nested arrays are unequal even with equal contents.
            { tag: "nested-distinct-refs-unequal", a: [["a"]], b: [["a"]], exp: false },
            { tag: "nested-same-ref-equal", a: nested, b: nested, exp: true },
            // type-strictness: 1 !== true, "1" !== 1 (no coercion).
            { tag: "no-bool-number-coercion", a: [1], b: [true], exp: false },
            { tag: "no-string-number-coercion", a: ["1"], b: [1], exp: false }
        ];
    }
    function test_arraysShallowEqual(data) {
        compare(Logic.arraysShallowEqual(data.a, data.b), data.exp, data.tag);
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

    // --- windowOccupiesDesktop: per-window OCCUPANCY predicate (used by computeDesktopOccupancy) -----
    // Deliberately DIFFERENT from windowIsOnDesktop (the tooltip membership above): for dynamic-workspace
    // occupancy an on-all-desktops window does NOT count (it would pin every desktop, so none could ever be
    // empty) and a skipPager window does NOT count, while a MINIMIZED window DOES (it still occupies its
    // desktop). Real window only; a null/undefined window or missing `desktops` is false. Strict boolean.
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
            // null/undefined ELEMENT guard — the one branch computeDesktopOccupancy can't reach (it only
            // nulls the whole array, which short-circuits before this predicate is ever called).
            { tag: "null-window", window: null, uuid: "a", exp: false },
            { tag: "undefined-window", window: undefined, uuid: "a", exp: false },
            // a real window on its desktop occupies it; a miss / empty / missing list does not.
            { tag: "desktops-match", window: occ({ desktops: ["a", "b"] }), uuid: "a", exp: true },
            { tag: "desktops-miss", window: occ({ desktops: ["b"] }), uuid: "a", exp: false },
            { tag: "desktops-undefined", window: occ({}), uuid: "a", exp: false },
            { tag: "empty-desktops-array", window: occ({ desktops: [] }), uuid: "a", exp: false },
            // non-window (launcher/panel) never occupies, even with a matching desktops list.
            { tag: "non-window-excluded", window: occ({ isWindow: false, desktops: ["a"] }), uuid: "a", exp: false },
            // KEY divergence from windowIsOnDesktop: on-all is EXCLUDED here (would pin every desktop).
            { tag: "on-all-excluded", window: occ({ onAll: true, desktops: ["a"] }), uuid: "a", exp: false },
            { tag: "on-all-excluded-no-desktops", window: occ({ onAll: true }), uuid: "a", exp: false },
            // skipPager (hidden from the pager) is excluded too.
            { tag: "skip-pager-excluded", window: occ({ skipPager: true, desktops: ["a"] }), uuid: "a", exp: false },
            // KEY inclusion: a MINIMIZED window still occupies its desktop (no minimized check by design).
            { tag: "minimized-still-counts", window: occ({ minimized: true, desktops: ["a"] }), uuid: "a", exp: true },
            // isWindow entirely missing (a raw object) is falsy → excluded, even with a matching list.
            { tag: "isWindow-missing", window: { desktops: ["a"] }, uuid: "a", exp: false }
        ];
    }
    function test_windowOccupiesDesktop(data) {
        var result = Logic.windowOccupiesDesktop(data.window, data.uuid);
        compare(result, data.exp, data.tag);
        compare(typeof result, "boolean", data.tag + " (strict boolean)");
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

    // --- computeDesktopOccupancy: per-desktop "has a window" boolean[] for dynamic workspaces -------
    // Index-aligned with desktopIds. A desktop is occupied by a REAL window that is NOT on-all and NOT
    // skipPager; minimized windows DO count (unlike a tooltip, an on-all window does NOT pin a desktop).
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

    // --- windowOccupiesDesktopOnScreen: per-screen occupancy (Plasma 6.7 per-output desktops) -------
    // windowOccupiesDesktop AND the window's OUTPUT origin (x,y) matches the pager's. Origin-only match
    // tolerates per-output scaling (different size, same top-left). NEVER drops a window: an unknown target
    // rect or an unknown own screen counts everywhere (degrades to global). The desktop exclusions still win.
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
            // on the desktop AND on this output → occupies; on another output → does not.
            { tag: "same-screen-occupies", window: occ(["a"], A), uuid: "a", rect: A, exp: true },
            { tag: "other-screen-excluded", window: occ(["a"], B), uuid: "a", rect: A, exp: false },
            // origin matches but size differs (fractional/per-output scaling) → still this screen.
            { tag: "origin-match-different-size", window: occ(["a"], A), uuid: "a", rect: Ahidpi, exp: true },
            // unknown TARGET rect (pager not yet placed) → counts everywhere (global fallback).
            { tag: "null-target-rect-global", window: occ(["a"], B), uuid: "a", rect: null, exp: true },
            { tag: "zero-target-rect-global", window: occ(["a"], B), uuid: "a", rect: { x: 0, y: 0, width: 0, height: 0 }, exp: true },
            // unknown OWN screen (e.g. a window with no geometry) → counts everywhere (never dropped).
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

    // --- computeDesktopOccupancyForScreen: per-screen per-desktop boolean[] ---------------------------
    // Index-aligned with desktopIds, counting only windows on the pager's output. An unknown screenRect
    // returns the IDENTICAL array to computeDesktopOccupancy (single-monitor / pre-placement == global).
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

    // The degradation contract pinned exactly: an unknown screenRect (null or zero-size) returns the SAME
    // array computeDesktopOccupancy would (so single-monitor and pre-placement frames are byte-for-byte global).
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

    // --- dynamicWorkspacePlan: the single add/remove/no-op per cycle (GNOME-style) ------------------
    // One action per call; reactive re-triggering converges to exactly one trailing empty. Only the
    // TRAILING run is managed (empty middles are left alone); transient/length-mismatch frames are no-ops.
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
            // >=2 trailing empties -> trim the LAST one (re-trigger trims the rest).
            { tag: "two-trailing-trim-last", occ: [true, false, false], ids: ["a", "b", "c"], exp: { kind: "remove", uuid: "c" } },
            { tag: "all-empty-trim-last", occ: [false, false], ids: ["a", "b"], exp: { kind: "remove", uuid: "b" } },
            // an empty MIDDLE desktop is left alone — only the trailing run is managed.
            { tag: "empty-middle-left-alone", occ: [false, true, false], ids: ["a", "b", "c"], exp: null },
            // a leading empty + a 2-deep trailing run still just trims the tail (not the middle).
            { tag: "leading-empty-trims-tail", occ: [false, true, false, false], ids: ["a", "b", "c", "d"], exp: { kind: "remove", uuid: "d" } }
        ];
    }
    function test_dynamicWorkspacePlan(data) {
        compare(JSON.stringify(Logic.dynamicWorkspacePlan(data.occ, data.ids)), JSON.stringify(data.exp), data.tag);
    }

    // --- formatDynamicDesktopName: user-configurable base + " " + number, never empty ---------------
    // A configured prefix wins; a blank prefix falls back to the i18n default passed in (main.qml's
    // "Desktop"); an all-blank case uses the literal "Desktop" so the name is never empty (KWin drops
    // createDesktop with an empty name). The prefix is sanitized (trim, cap 100) like a rename.
    function test_formatDynamicDesktopName_data() {
        return [
            { tag: "custom-prefix", prefix: "Workspace", number: 3, fallback: "Desktop", exp: "Workspace 3" },
            { tag: "blank-uses-fallback", prefix: "", number: 2, fallback: "Desktop", exp: "Desktop 2" },
            { tag: "whitespace-uses-fallback", prefix: "   ", number: 5, fallback: "Desktop", exp: "Desktop 5" },
            { tag: "prefix-trimmed", prefix: "  Web  ", number: 4, fallback: "Desktop", exp: "Web 4" },
            // a localized fallback (non-English main.qml i18n) is honoured when the prefix is blank.
            { tag: "localized-fallback", prefix: "", number: 2, fallback: "Bureau", exp: "Bureau 2" },
            // all-blank (prefix AND fallback) still yields a non-empty name via the literal last resort.
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

    // --- electDynamicWriter: the single global writer among pager instances (multi-monitor) ----------
    // registry maps coordinator token -> enabled. The writer is the lowest-token ENABLED instance, or -1
    // when none is enabled. Keys are strings (object keys) — the function coerces them to Number.
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

    // dataChangeAffectsRoles: rebuild the tooltip only when a role the rebuild READS changed (skips the
    // IsActive focus churn etc.). An EMPTY/null roles list is Qt's "all changed" → rebuild. The role ints
    // are synthetic here (main.qml supplies the real taskmanager enum ints).
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
            // a relevant role present ANYWHERE in the list (even last) still rebuilds.
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

    // DEFAULTS: the single source of truth for the QML-side config defaults. Every value mirrors a
    // main.xml <default> and is referenced by main.qml's `?? Logic.DEFAULTS.X`, so drift fails loudly.
    function test_defaults_data() {
        return [
            { tag: "enableScroll", key: "enableScroll", exp: true },
            { tag: "scrollWrap", key: "scrollWrap", exp: false },
            { tag: "invertScroll", key: "invertScroll", exp: false },
            { tag: "pillClickAction", key: "pillClickAction", exp: 0 },
            { tag: "showTooltips", key: "showTooltips", exp: true },
            { tag: "showWindowList", key: "showWindowList", exp: true },
            { tag: "enableAddRemove", key: "enableAddRemove", exp: true },
            { tag: "enableRename", key: "enableRename", exp: true },
            { tag: "dynamicWorkspaces", key: "dynamicWorkspaces", exp: false },
            { tag: "dynamicNamePrefix", key: "dynamicNamePrefix", exp: "" },
            { tag: "animationDuration", key: "animationDuration", exp: 0 },
            { tag: "dotStyle", key: "dotStyle", exp: 0 },
            { tag: "dotSize", key: "dotSize", exp: 0 },
            { tag: "pillSize", key: "pillSize", exp: 0 },
            { tag: "spacingFactor", key: "spacingFactor", exp: 0.5 },
            { tag: "pillWidthFactor", key: "pillWidthFactor", exp: 3.5 },
            { tag: "inactiveOpacity", key: "inactiveOpacity", exp: 0.45 },
            { tag: "hoverOpacity", key: "hoverOpacity", exp: 0.8 },
            { tag: "showOccupancy", key: "showOccupancy", exp: false },
            { tag: "occupiedOpacity", key: "occupiedOpacity", exp: 0.7 },
            { tag: "occupancyStyle", key: "occupancyStyle", exp: 0 },
            { tag: "followThemeColors", key: "followThemeColors", exp: true },
            { tag: "activeColor", key: "activeColor", exp: "#3daee9" },
            { tag: "inactiveColor", key: "inactiveColor", exp: "#eff0f1" },
            { tag: "occupiedColor", key: "occupiedColor", exp: "#3daee9" },
            { tag: "wheelNotchDelta", key: "wheelNotchDelta", exp: 120 }
        ];
    }
    function test_defaults(data) {
        compare(Logic.DEFAULTS[data.key], data.exp, data.tag);
    }

    // DEFAULTS is shared (.pragma library) and must stay immutable. Object.freeze makes the write a no-op
    // (silent, or a TypeError under "use strict"); tolerate either and assert the value stays put.
    function test_defaultsAreFrozen() {
        verify(Object.isFrozen(Logic.DEFAULTS), "Logic.DEFAULTS must be frozen");
        try { Logic.DEFAULTS.dotSize = 999; } catch (e) { /* strict-mode TypeError is expected */ }
        compare(Logic.DEFAULTS.dotSize, 0, "a frozen DEFAULTS ignores writes");
    }

    // The exact key SET is pinned (test_defaults checks only values). A new key must be added here too.
    function test_defaultsKeySet() {
        var keys = Object.keys(Logic.DEFAULTS).sort();
        var expected = ["activeColor", "animationDuration", "dotSize", "dotStyle", "dynamicNamePrefix",
                        "dynamicWorkspaces", "enableAddRemove", "enableRename",
                        "enableScroll", "followThemeColors", "hoverOpacity", "inactiveColor",
                        "inactiveOpacity", "invertScroll", "occupancyStyle", "occupiedColor", "occupiedOpacity",
                        "pillClickAction", "pillSize", "pillWidthFactor", "scrollWrap", "showOccupancy", "showTooltips",
                        "showWindowList", "spacingFactor", "wheelNotchDelta"].sort();
        compare(keys.length, 26, "DEFAULTS has exactly 26 keys");
        compare(JSON.stringify(keys), JSON.stringify(expected), "the exact DEFAULTS key set is pinned");
    }

    // CROSS-CHECK the KConfigXT schema against the JS mirror: every main.xml <default> must equal
    // Logic.DEFAULTS[name] (the two are hand-synced — KConfigXT can't read a JS literal). Nothing else
    // verified they agree. wheelNotchDelta is the one DEFAULTS key with no main.xml entry.
    function test_mainXmlDefaultsMatchLogicDefaults() {
        // Relative URL — XMLHttpRequest resolves it against this test file's location (no Qt.resolvedUrl).
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "../../package/contents/config/main.xml", false);
        xhr.send();
        var xml = xhr.responseText;
        verify(xml && xml.length > 0, "main.xml is readable");

        // Capture each entry's name + type + <default> body; non-greedy so each <entry> pairs with its
        // OWN following <default> (an empty <default></default> yields "").
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
                // Tolerate a float ULP between the parsed schema literal and the JS literal.
                verify(Math.abs(parseFloat(raw) - expected) <= 1e-9, name + " (Double) default matches");
                break;
            case "Color":
                // QColor hex strings; compare case-insensitively (#3daee9 vs #3DAEE9).
                compare(raw.toLowerCase(), String(expected).toLowerCase(), name + " (Color) default matches");
                break;
            case "String":
                compare(raw, expected, name + " (String) default matches");
                break;
            default:
                verify(false, "unhandled main.xml entry type '" + type + "' for '" + name + "'");
            }
        }
        // Every schema entry was parsed (a regex miss would silently skip a key) — all of DEFAULTS but wheelNotchDelta.
        compare(seen, Object.keys(Logic.DEFAULTS).length - 1, "every main.xml entry was checked (all but wheelNotchDelta)");
    }

    // KWin DBus call SHAPES: pin the silently-failing strings/types. Each *Spec builds the exact
    // { service, path, iface, member, args:[{t,v}] } main.qml dispatches, or null when a guard trips. A
    // wrong string/type is DROPPED by KWin with no error (CLAUDE.md) — so JSON-compare pins it by value.
    function test_switchSpec_data() {
        return [
            // desktopIds/currentDesktop can be transiently empty (robustness.md) -> guarded to null.
            { tag: "empty-uuid-null", uuid: "", exp: null },
            { tag: "undefined-uuid-null", uuid: undefined, exp: null },
            {
                tag: "valid", uuid: "uuid-a",
                exp: {
                    service: "org.kde.KWin", path: "/VirtualDesktopManager",
                    iface: "org.freedesktop.DBus.Properties", member: "Set",
                    // the Set(ssv) shape: iface name + "current" + a VARIANT of the plain uuid.
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
        // a transient-undefined count must reach uint32 as a real integer (position|0); the name is stringified.
        compare(Logic.addSpec(undefined, "X").args[0].v, 0, "undefined position coerces to 0");
        compare(Logic.addSpec(2.9, "X").args[0].v, 2, "fractional position truncates via |0");
        compare(Logic.addSpec(0, 42).args[1].v, "42", "name is stringified");
    }

    function test_removeSpec_data() {
        return [
            { tag: "empty-uuid-null", uuid: "", count: 3, exp: null },
            // never-remove-last (reuses canRemoveDesktop): a single (or zero) desktop is guarded to null.
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
            // sanitizeDesktopName rejects empty/whitespace -> null (a blank rename is a tested no-op).
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
        // sanitizeDesktopName caps at 100 chars; the spec must carry the capped name.
        var longName = new Array(150).join("a");   // 149 'a's
        compare(Logic.renameSpec("uuid-a", longName).args[1].v.length, 100, "renameSpec caps the name at 100 chars");
    }

    // invokeShortcutSpec: the kglobalaccel invokeShortcut(string) shape (null for a falsy name).
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

    // pillClickSpec: the pill-click action -> KWin shortcut spec. None / unknown -> null (safe no-op); the
    // active actions toggle KWin shortcuts by their exact unique names ("Grid" -> "Grid View").
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
}
