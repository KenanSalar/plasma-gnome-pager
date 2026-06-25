/*
 * Plasma Gnome Pager — tst_indicatormetrics.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for IndicatorMetrics in isolation — the dot-strip sizing engine extracted from
 * WorkspaceIndicator. It is a pure QtObject (only Kirigami.Units + logic.js), so it loads headless.
 * Asserts the NATURAL/floor/EFFECTIVE size contract: the natural extents reproduce Logic.lineExtent;
 * effective == natural when there is room; the dot shrinks (scale-to-fit) on a narrow major OR thin
 * cross allocation, floored at minDotSize; and the pill scales in lockstep with the dot. Expected
 * values come from the pure logic.js formulas (not literals), so they stay HiDPI/theme-independent.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen.
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager
import "../../package/contents/ui/logic.js" as Logic

TestCase {
    id: testCase
    name: "IndicatorMetrics"

    Component {
        id: metricsComponent
        Pager.IndicatorMetrics {}
    }

    function makeMetrics(props) {
        return createTemporaryObject(metricsComponent, testCase, props || {});
    }

    // naturalDotSize: a positive request is used verbatim; 0 falls back to the themed half-icon.
    function test_naturalDotSizeRequestVsAuto() {
        const m = makeMetrics({ dotSizeRequest: 20 });
        compare(m.naturalDotSize, 20, "positive dotSizeRequest is the natural size");
        const auto = makeMetrics({ dotSizeRequest: 0 });
        compare(auto.naturalDotSize, Kirigami.Units.iconSizes.small / 2, "0 = auto = themed half-icon");
    }

    // pillThicknessRatio: 1 when the pill is auto (matches the dot); naturalPillSize/naturalDotSize otherwise.
    function test_pillThicknessRatio() {
        const auto = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0 });
        compare(auto.naturalPillSize, 10, "auto pill thickness == the dot size");
        compare(auto.pillThicknessRatio, 1, "auto pill → ratio 1");
        const thick = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 30 });
        compare(thick.naturalPillSize, 30, "explicit pill thickness is used");
        compare(thick.pillThicknessRatio, 3, "ratio = pill / dot");
    }

    // minDotSize: the themed floor, clamped <= naturalDotSize (a tiny configured dot never scales UP).
    function test_minDotSizeClampedToNatural() {
        const tiny = makeMetrics({ dotSizeRequest: 2 });
        compare(tiny.minDotSize, 2, "minDotSize clamps to natural for a tiny configured dot");
        const big = makeMetrics({ dotSizeRequest: 40 });
        compare(big.minDotSize, Kirigami.Units.iconSizes.small / 4, "minDotSize is the themed floor for a large dot");
    }

    // Natural extents reproduce the pure lineExtent formula (capsule length = pill thickness * widthFactor).
    function test_naturalStripLengthMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        const expected = Logic.lineExtent(4, 10, 10 * 0.5, 10 * 3);   // naturalPillSize == 10 (auto)
        fuzzyCompare(m.naturalStripLength, expected, 0.001, "naturalStripLength == lineExtent(perLine, dot, gap, capsule)");
    }

    function test_naturalCrossThicknessMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 30, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 2, lineCount: 3 });
        const expected = Logic.lineExtent(3, 10, 10 * 0.5, Math.max(10, 30));   // pill-bearing line is max(dot, pill)
        fuzzyCompare(m.naturalCrossThickness, expected, 0.001, "naturalCrossThickness stacks lineCount lines, pill-bearing line max(dot,pill)");
    }

    // Room available on both axes → effective == natural, byte-for-byte (the common case).
    function test_effectiveEqualsNaturalWhenAmple() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableMajor = m.naturalStripLength * 2;     // plenty of room
        m.availableCross = m.naturalCrossThickness * 2;
        compare(m.dotSize, m.naturalDotSize, "effective dotSize == natural when there is room on both axes");
        compare(m.pillSize, m.naturalPillSize, "effective pillSize == natural");
        fuzzyCompare(m.dotSpacing, m.dotSize * 0.5, 0.001, "dotSpacing = dotSize * spacingFactor");
        fuzzyCompare(m.pillWidth, m.pillSize * 3, 0.001, "pillWidth = pillSize * pillWidthFactor");
    }

    // A narrow MAJOR allocation shrinks the dot to fit (majorFit binds), still capped at natural and floored,
    // and a full line at the effective size exactly fills the allocation (the inverse of lineExtent).
    function test_shrinkOnNarrowMajor() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;       // cross unconstrained
        m.availableMajor = m.naturalStripLength * 0.6;        // 60% of the natural length (above the floor)
        verify(m.dotSize < m.naturalDotSize, "dotSize shrinks below natural on a narrow major axis");
        verify(m.dotSize >= m.minDotSize, "but never below the legibility floor");
        fuzzyCompare(Logic.lineExtent(4, m.dotSize, m.dotSize * 0.5, m.pillWidth), m.availableMajor, 0.01,
            "the shrunk line exactly fills the narrow major allocation");
    }

    // A thin CROSS allocation (multi-row grid on a thin panel) shrinks the dot too (crossFit binds).
    function test_shrinkOnThinCross() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 2, lineCount: 3 });
        m.availableMajor = m.naturalStripLength * 2;          // major unconstrained
        m.availableCross = m.naturalCrossThickness * 0.6;     // thinner than the 3 stacked lines need
        verify(m.dotSize < m.naturalDotSize, "dotSize shrinks on a thin cross axis (multi-row grid)");
    }

    // The pill scales in lockstep with the dot under shrink, so the configured dot:pill proportion holds.
    function test_pillScalesInLockstep() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 48, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;
        m.availableMajor = m.naturalStripLength * 0.6;
        verify(m.dotSize < m.naturalDotSize, "dot shrinks");
        fuzzyCompare(m.pillThicknessRatio, 3, 0.001, "ratio preserved (48/16)");
        fuzzyCompare(m.pillSize, m.dotSize * m.pillThicknessRatio, 0.001, "pillSize = dotSize * ratio (lockstep)");
    }

    // At an extreme-narrow allocation the dot (and the pill) clamp at the floor, never shrinking further.
    function test_floorAtExtremeNarrow() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 32, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;
        m.availableMajor = m.naturalStripLength * 0.05;    // far below the floor
        compare(m.dotSize, m.minDotSize, "dotSize clamps at minDotSize under extreme compression");
        fuzzyCompare(m.pillSize, m.minDotSize * m.pillThicknessRatio, 0.001, "pillSize floors in lockstep");
    }

    // Before layout (no allocation) the fits are +Infinity, so effective == natural (no premature shrink).
    function test_unboundedBeforeLayout() {
        const m = makeMetrics({ dotSizeRequest: 10, perLine: 4, lineCount: 1 });
        // availableMajor/Cross default 0 → fitDotSize +Infinity → min keeps natural
        compare(m.dotSize, m.naturalDotSize, "no allocation yet → effective == natural (no premature shrink)");
    }

    // Conserved (capsule-bearing) extents the indicator pins the strip to: lineExtent over the EFFECTIVE sizes.
    // When there is room they equal the natural extents (the strip is pinned to the same value it sizes to today).
    function test_stripLengthMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 2 });
        const expected = Logic.lineExtent(4, m.dotSize, m.dotSpacing, m.pillWidth);   // a full capsule-bearing line
        fuzzyCompare(m.stripLength, expected, 0.001, "stripLength == lineExtent(perLine, dot, gap, pillWidth)");
        fuzzyCompare(m.stripLength, m.naturalStripLength, 0.001, "== naturalStripLength when there is room");
    }

    function test_crossThicknessMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 30, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 2, lineCount: 3 });
        const expected = Logic.lineExtent(3, m.dotSize, m.dotSpacing, Math.max(m.dotSize, m.pillSize));
        fuzzyCompare(m.crossThickness, expected, 0.001, "crossThickness == lineExtent(lineCount, dot, gap, max(dot,pill))");
        fuzzyCompare(m.crossThickness, m.naturalCrossThickness, 0.001, "== naturalCrossThickness when there is room");
    }

    // stripLength tracks the EFFECTIVE (shrunk) size, not natural — so the pinned strip fits a compressed panel
    // (a full capsule line at the effective dot exactly fills the allocation, the inverse of lineExtent).
    function test_stripLengthTracksEffectiveUnderShrink() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;     // cross unconstrained
        m.availableMajor = m.naturalStripLength * 0.6;      // compress the major axis
        verify(m.dotSize < m.naturalDotSize, "the dot shrank");
        fuzzyCompare(m.stripLength, m.availableMajor, 0.01, "stripLength tracks the effective size → fills the narrow allocation");
        verify(m.stripLength < m.naturalStripLength, "and is below the natural strip length");
    }
}
