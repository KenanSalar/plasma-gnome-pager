/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * IndicatorMetrics on its own, with hand-set allocations. Expected sizes come from the logic.js
 * formulas rather than literals, so they hold at any scale and theme.
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

    function test_naturalDotSizeRequestVsAuto() {
        const m = makeMetrics({ dotSizeRequest: 20 });
        compare(m.naturalDotSize, 20, "positive dotSizeRequest is the natural size");
        const auto = makeMetrics({ dotSizeRequest: 0 });
        compare(auto.naturalDotSize, Kirigami.Units.iconSizes.small / 2, "0 = auto = themed half-icon");
    }

    function test_pillThicknessRatio() {
        const auto = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0 });
        compare(auto.naturalPillSize, 10, "auto pill thickness == the dot size");
        compare(auto.pillThicknessRatio, 1, "auto pill → ratio 1");
        const thick = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 30 });
        compare(thick.naturalPillSize, 30, "explicit pill thickness is used");
        compare(thick.pillThicknessRatio, 3, "ratio = pill / dot");
    }

    // A configured dot smaller than the floor must not grow to it.
    function test_minDotSizeClampedToNatural() {
        const tiny = makeMetrics({ dotSizeRequest: 2 });
        compare(tiny.minDotSize, 2, "minDotSize clamps to natural for a tiny configured dot");
        const big = makeMetrics({ dotSizeRequest: 40 });
        compare(big.minDotSize, Kirigami.Units.iconSizes.small / 4, "minDotSize is the themed floor for a large dot");
    }

    function test_naturalStripLengthMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        const expected = Logic.lineExtent(4, 10, 10 * 0.5, 10 * 3);   // naturalPillSize == 10 (auto)
        fuzzyCompare(m.naturalStripLength, expected, 0.001, "naturalStripLength == lineExtent(perLine, dot, gap, capsule)");
    }

    function test_naturalCrossThicknessMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 30, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 2, lineCount: 3 });
        const expected = Logic.lineExtent(3, 10, 10 * 0.5, Math.max(10, 30));   // the pill's line is the thicker
        fuzzyCompare(m.naturalCrossThickness, expected, 0.001, "naturalCrossThickness stacks lineCount lines, pill-bearing line max(dot,pill)");
    }

    function test_effectiveEqualsNaturalWhenAmple() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableMajor = m.naturalStripLength * 2;     // plenty of room
        m.availableCross = m.naturalCrossThickness * 2;
        compare(m.dotSize, m.naturalDotSize, "effective dotSize == natural when there is room on both axes");
        compare(m.pillSize, m.naturalPillSize, "effective pillSize == natural");
        fuzzyCompare(m.dotSpacing, m.dotSize * 0.5, 0.001, "dotSpacing = dotSize * spacingFactor");
        fuzzyCompare(m.pillWidth, m.pillSize * 3, 0.001, "pillWidth = pillSize * pillWidthFactor");
    }

    function test_shrinkOnNarrowMajor() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;       // cross unconstrained
        m.availableMajor = m.naturalStripLength * 0.6;        // 60% of the natural length (above the floor)
        verify(m.dotSize < m.naturalDotSize, "dotSize shrinks below natural on a narrow major axis");
        verify(m.dotSize >= m.minDotSize, "but never below the legibility floor");
        fuzzyCompare(Logic.lineExtent(4, m.dotSize, m.dotSize * 0.5, m.pillWidth), m.availableMajor, 0.01,
            "the shrunk line exactly fills the narrow major allocation");
    }

    function test_shrinkOnThinCross() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 2, lineCount: 3 });
        m.availableMajor = m.naturalStripLength * 2;          // major unconstrained
        m.availableCross = m.naturalCrossThickness * 0.6;     // thinner than the 3 stacked lines need
        verify(m.dotSize < m.naturalDotSize, "dotSize shrinks on a thin cross axis (multi-row grid)");
    }

    function test_pillScalesInLockstep() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 48, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;
        m.availableMajor = m.naturalStripLength * 0.6;
        verify(m.dotSize < m.naturalDotSize, "dot shrinks");
        fuzzyCompare(m.pillThicknessRatio, 3, 0.001, "ratio preserved (48/16)");
        fuzzyCompare(m.pillSize, m.dotSize * m.pillThicknessRatio, 0.001, "pillSize = dotSize * ratio (lockstep)");
    }

    function test_floorAtExtremeNarrow() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 32, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;
        m.availableMajor = m.naturalStripLength * 0.05;    // far below the floor
        compare(m.dotSize, m.minDotSize, "dotSize clamps at minDotSize under extreme compression");
        fuzzyCompare(m.pillSize, m.minDotSize * m.pillThicknessRatio, 0.001, "pillSize floors in lockstep");
    }

    // Before the first layout there is no allocation, which mustn't read as a tiny one.
    function test_unboundedBeforeLayout() {
        const m = makeMetrics({ dotSizeRequest: 10, perLine: 4, lineCount: 1 });
        // availableMajor/Cross default 0 → fitDotSize +Infinity → min keeps natural
        compare(m.dotSize, m.naturalDotSize, "no allocation yet → effective == natural (no premature shrink)");
    }

    function test_stripLengthMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 2 });
        const expected = Logic.lineExtent(4, m.dotSize, m.dotSpacing, m.pillWidth);
        fuzzyCompare(m.stripLength, expected, 0.001, "stripLength == lineExtent(perLine, dot, gap, pillWidth)");
        fuzzyCompare(m.stripLength, m.naturalStripLength, 0.001, "== naturalStripLength when there is room");
    }

    function test_crossThicknessMatchesFormula() {
        const m = makeMetrics({ dotSizeRequest: 10, pillSizeRequest: 30, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 2, lineCount: 3 });
        const expected = Logic.lineExtent(3, m.dotSize, m.dotSpacing, Math.max(m.dotSize, m.pillSize));
        fuzzyCompare(m.crossThickness, expected, 0.001, "crossThickness == lineExtent(lineCount, dot, gap, max(dot,pill))");
        fuzzyCompare(m.crossThickness, m.naturalCrossThickness, 0.001, "== naturalCrossThickness when there is room");
    }

    // Pinned to a natural length, the strip would overflow a panel that squeezed the dots.
    function test_stripLengthTracksEffectiveUnderShrink() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;     // cross unconstrained
        m.availableMajor = m.naturalStripLength * 0.6;      // compress the major axis
        verify(m.dotSize < m.naturalDotSize, "the dot shrank");
        fuzzyCompare(m.stripLength, m.availableMajor, 0.01, "stripLength tracks the effective size → fills the narrow allocation");
        verify(m.stripLength < m.naturalStripLength, "and is below the natural strip length");
    }

    // An auto pill keeps the cross fit the exact inverse of the line stack, so the fill is exact.
    function test_crossThicknessTracksEffectiveUnderShrink() {
        const m = makeMetrics({ dotSizeRequest: 16, pillSizeRequest: 0, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 1, lineCount: 4 });
        m.availableMajor = m.naturalStripLength * 2;        // major unconstrained
        m.availableCross = m.naturalCrossThickness * 0.6;   // compress the cross axis
        verify(m.dotSize < m.naturalDotSize, "the dot shrank");
        fuzzyCompare(m.crossThickness, m.availableCross, 0.01, "crossThickness tracks the effective size → fills the thin allocation");
        verify(m.crossThickness < m.naturalCrossThickness, "and is below the natural cross thickness");
    }

    // Zero factors are what the indicator passes while the hover background is off.
    function test_hoverClearanceOffCollapsesToBareExtents() {
        const m = makeMetrics({ dotSizeRequest: 10, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1, hoverLengthFactor: 0, hoverThicknessFactor: 0 });
        compare(m.hoverPadding, 0, "no length clearance");
        compare(m.hoverCrossPadding, 0, "no thickness clearance");
        compare(m.hoverCrossPaddingEffective, 0, "none on the render side either");
        fuzzyCompare(m.paddedStripLength, m.naturalStripLength, 0.001, "padded length == the bare strip");
        fuzzyCompare(m.paddedCrossThickness, m.naturalCrossThickness, 0.001, "padded thickness == the bare strip");
    }

    function test_hoverClearanceGrowsTheHintExtents() {
        const m = makeMetrics({
            dotSizeRequest: 10, pillSizeRequest: 30, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 2,
            hoverLengthFactor: 1.0, hoverThicknessFactor: 0.5
        });
        fuzzyCompare(m.naturalLineThickness, 30, 0.001, "one line is as thick as the pill where the pill is thicker");
        fuzzyCompare(m.hoverPadding, Logic.hoverPadding(30, 1.0), 0.001, "length clearance is factor × line thickness");
        fuzzyCompare(m.hoverCrossPadding, Logic.hoverPadding(30, 0.5), 0.001, "thickness clearance uses its OWN factor");
        fuzzyCompare(m.paddedStripLength, m.naturalStripLength + 2 * m.hoverPadding, 0.001, "the cell grows at both ends");
        fuzzyCompare(m.paddedCrossThickness, m.naturalCrossThickness + 2 * m.hoverCrossPadding, 0.001, "and on both sides");
    }

    // A hint that moved with the rendered dots would close a binding loop through the allocation.
    function test_hoverHintClearanceIsGeometryIndependent() {
        const m = makeMetrics({ dotSizeRequest: 16, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 6, lineCount: 1 });
        m.availableCross = m.naturalCrossThickness * 2;
        const hintPadding = m.hoverPadding;
        const hintCrossPadding = m.hoverCrossPadding;
        const paddedLength = m.paddedStripLength;

        m.availableMajor = m.naturalStripLength * 0.5;   // squeeze until the dots have to shrink
        verify(m.dotSize < m.naturalDotSize, "scale-to-fit is active");
        verify(m.hoverCrossPaddingEffective < hintCrossPadding, "the RENDER-side clearance shrinks with the dots");
        compare(m.hoverPadding, hintPadding, "but the HINT-side length clearance stays on the natural sizes");
        compare(m.hoverCrossPadding, hintCrossPadding, "and so does the thickness clearance");
        compare(m.paddedStripLength, paddedLength, "so the advertised extent never follows the RENDERED dot");
    }

    // Insetting the cell instead collapsed the background onto the strip once the padding outgrew the room.
    function test_hoverCrossExtentGrowsThenCaps() {
        const m = makeMetrics({ dotSizeRequest: 10, spacingFactor: 0.5, pillWidthFactor: 3, perLine: 4, lineCount: 1 });
        m.availableMajor = m.naturalStripLength * 2;

        m.availableCross = m.naturalCrossThickness * 10;   // room to spare, which the background mustn't fill
        fuzzyCompare(m.hoverCrossExtent, m.crossThickness + 2 * m.hoverCrossPaddingEffective, 0.001, "strip plus its clearance");
        verify(m.hoverCrossExtent < m.availableCross, "and keeps its proportion instead of filling the panel");

        m.availableCross = m.crossThickness;               // a panel exactly as thick as the strip: no room to pad
        fuzzyCompare(m.hoverCrossExtent, m.availableCross, 0.001, "caps at the cell rather than overflowing it");
    }
}
