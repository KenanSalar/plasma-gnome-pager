/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A built WorkspaceIndicator on VdiMock, sized by hand as a panel would size it: the hints it
 * advertises, the grid and its orientation, the sizes of dots and pill, and shrinking to fit.
 */
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../shared"
import "../../package/contents/ui/logic.js" as Logic
import "../shared/elements.js" as Elements

IndicatorTestCase {
    id: layoutCase
    name: "IndicatorLayout"

    // With only an implicit width, the shell gave the applet a square cell and the dots overflowed it.
    function test_advertisesWidthViaLayout() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator.implicitWidth > 0, "indicator has a positive content width");
        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth advertises the natural content width");
        compare(indicator.Layout.maximumWidth, indicator.implicitWidth, "maximumWidth pins the natural width (a pager does not stretch past it)");
        // A minimum at the floor lets the panel squeeze the strip.
        verify(indicator.minDotSize < indicator.naturalDotSize, "the legible floor dot is smaller than natural");
        verify(indicator.Layout.minimumWidth < indicator.implicitWidth, "minimumWidth drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorStripLength, 0.5, "minimumWidth is the floor (strip at the minimum legible dot)");
    }

    // Without the room, the outer dots would sit flush against the background's rounded ends.
    function test_hoverBackgroundPadsMajorAxis() {
        const padded = makeIndicator(makeMock(ids, currentUuid));
        const bare = makeIndicator(makeMock(ids, currentUuid), { showHoverBackground: false });
        verify(padded.hoverPadding > 0, "the background reserves padding when it is on");
        compare(bare.hoverPadding, 0, "and none at all when it is off");
        fuzzyCompare(padded.implicitWidth, bare.implicitWidth + 2 * padded.hoverPadding, 0.5, "the cell grows by the padding at both ends");
        fuzzyCompare(padded.Layout.maximumWidth, padded.implicitWidth, 0.5, "the maximum grows with it (the pager still does not stretch)");
        fuzzyCompare(padded.implicitHeight, bare.implicitHeight + 2 * padded.hoverCrossPadding, 0.5, "and by the (smaller) cross padding above and below");
    }

    // The defaults put a pill's thickness of clearance on each side, as GNOME does.
    function test_hoverBackgroundMatchesGnomeProportions() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 80 });
        const bg = hoverBackgroundOf(indicator);
        fuzzyCompare(bg.height / indicator.lineThickness, 3.0, 0.05, "the background is 3 pill thicknesses tall");
        verify(bg.height > indicator.crossThickness + 1, "which is strictly taller than the strip it sits behind");
    }

    // A cramped panel squeezes out the padding before the dots shrink.
    function test_hoverBackgroundPaddingNotInMinimum() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorStripLength, 0.5, "minimumWidth is still the bare floor");
        verify(indicator.Layout.minimumWidth < indicator.implicitWidth - 2 * indicator.hoverPadding + 0.5, "the floor sits below even the unpadded natural length");
    }

    function test_hoverBackgroundOffKeepsBareHints() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showHoverBackground: false });
        fuzzyCompare(indicator.implicitWidth, indicator.naturalStripLength, 0.5, "implicitWidth is the bare strip length");
        fuzzyCompare(indicator.Layout.maximumWidth, indicator.naturalStripLength, 0.5, "maximumWidth is the bare strip length");
        fuzzyCompare(indicator.implicitHeight, indicator.naturalCrossThickness, 0.5, "implicitHeight is the bare cross thickness");
        compare(indicator.hoverCrossPaddingEffective, 0, "the render-side clearance collapses too, not just the hint-side one");
        fuzzyCompare(indicator.hoverCrossExtent, indicator.crossThickness, 0.5, "so the (hidden) background reports the bare strip thickness");
    }

    function test_hoverBackgroundFillsCellStadium() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        const bg = hoverBackgroundOf(indicator);
        verify(bg !== null, "the indicator carries a hover-background rectangle");
        fuzzyCompare(bg.width, indicator.width, 0.5, "spans the full cell along the major axis");
        fuzzyCompare(bg.height, indicator.hoverCrossExtent, 0.5, "the cross extent is the strip plus its padding");
        fuzzyCompare(bg.radius, Math.min(bg.width, bg.height) / 2, 0.5, "stadium ends");
        const c = Elements.centerOf(bg, indicator);
        fuzzyCompare(c.x, indicator.width / 2, 0.5, "centred horizontally");
        fuzzyCompare(c.y, indicator.height / 2, 0.5, "centred vertically");
    }

    function test_hoverBackgroundStadiumVertical() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true, width: 50, height: 200 });
        const bg = hoverBackgroundOf(indicator);
        fuzzyCompare(bg.height, indicator.height, 0.5, "spans the full cell along the major (vertical) axis");
        fuzzyCompare(bg.width, indicator.hoverCrossExtent, 0.5, "the cross (horizontal) extent is the strip plus its padding");
        fuzzyCompare(bg.radius, Math.min(bg.width, bg.height) / 2, 0.5, "stadium ends");
    }

    function test_hoverClearanceFactorsDriveGeometry() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 300, height: 160 });
        const bg = hoverBackgroundOf(indicator);
        const baseHeight = bg.height;
        const baseWidth = indicator.implicitWidth;

        indicator.hoverThicknessFactor = indicator.hoverThicknessFactor * 2;
        tryVerify(() => bg.height > baseHeight + 1, 2000, "raising the thickness factor makes the background taller");
        fuzzyCompare(bg.height, indicator.crossThickness + 2 * Logic.hoverPadding(indicator.lineThickness, indicator.hoverThicknessFactor), 0.5, "by exactly the requested clearance");

        indicator.hoverLengthFactor = indicator.hoverLengthFactor * 2;
        tryVerify(() => indicator.implicitWidth > baseWidth + 1, 2000, "raising the length factor widens the advertised cell");
    }

    function test_hoverClearanceZeroHugsTheStrip() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            width: 300, height: 160, hoverLengthFactor: 0, hoverThicknessFactor: 0
        });
        compare(indicator.hoverPadding, 0, "no length clearance");
        fuzzyCompare(hoverBackgroundOf(indicator).height, indicator.crossThickness, 0.5, "the background is exactly the strip thickness");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalStripLength, 0.5, "and the cell is the bare strip length");
    }

    function test_hoverBackgroundNeverOverflowsThinPanel() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200 });
        indicator.height = indicator.crossThickness;   // no room to pad
        const bg = hoverBackgroundOf(indicator);
        tryCompare(bg, "height", indicator.height, 2000, "the background caps at the cell");
        verify(bg.height <= indicator.height + 0.5, "and never draws past it");
    }

    function test_hoverBackgroundDoesNotFillAnOversizedPanel() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 120 });
        const bg = hoverBackgroundOf(indicator);
        verify(bg.height < indicator.height - 1, "the background keeps its proportion instead of filling the panel");
        fuzzyCompare(bg.height, indicator.crossThickness + 2 * Logic.hoverPadding(indicator.lineThickness, indicator.hoverThicknessFactor), 0.5, "strip + padding");
    }

    // Only a name keeps the hint-side padding off the rendered sizes, which would loop back through the
    // allocation. Height stays unset so implicitHeight drives the cell, and the strip is squeezed because
    // the two paddings differ only once the dots shrink: with room, every check here would pass vacuously.
    function test_hoverHintsAreGeometryIndependent() {
        const many = manyIds(12);
        const indicator = makeIndicator(makeMock(many, many[0]), { width: 600 });
        compare(indicator.dotSize, indicator.naturalDotSize, "roomy to start: the dots render at natural size");
        const hint = {
            implicitWidth: indicator.implicitWidth,
            implicitHeight: indicator.implicitHeight,
            maximumWidth: indicator.Layout.maximumWidth,
            padding: indicator.hoverPadding,
            crossPadding: indicator.hoverCrossPadding
        };

        indicator.width = 120;   // squeeze until the dots have to shrink
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize, 2000, "scale-to-fit is active");
        verify(indicator.hoverCrossPaddingEffective < hint.crossPadding, "the RENDER-side clearance shrinks with the dots (so the hint checks are not vacuous)");

        compare(indicator.hoverCrossPadding, hint.crossPadding, "but the HINT-side clearance stays on the natural sizes");
        compare(indicator.hoverPadding, hint.padding, "on the major axis too");
        compare(indicator.implicitHeight, hint.implicitHeight, "so implicitHeight never follows the RENDERED dot — that would be the binding loop");
        compare(indicator.implicitWidth, hint.implicitWidth, "and implicitWidth stays put as well");
        compare(indicator.Layout.maximumWidth, hint.maximumWidth, "as does the advertised maximum");
    }

    // vertical panel
    function test_verticalStacksDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        const dots = dotsByIndex(indicator);
        for (let i = 0; i < dots.length - 1; i++) {
            const thisY = dots[i].mapToItem(indicator, 0, 0).y;
            const nextY = dots[i + 1].mapToItem(indicator, 0, 0).y;
            verify(nextY > thisY, "element " + (i + 1) + " sits below element " + i);
            const thisX = dots[i].mapToItem(indicator, 0, 0).x;
            const nextX = dots[i + 1].mapToItem(indicator, 0, 0).x;
            fuzzyCompare(nextX, thisX, 0.5, "elements share a column (equal X)");
        }
    }

    function test_verticalUniformSpacing() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });   // middle is the capsule
        const dots = dotsByIndex(indicator);
        for (let i = 0; i < dots.length - 1; i++) {
            const bottomEdge = dots[i].mapToItem(indicator, 0, dots[i].height).y;
            const nextTop = dots[i + 1].mapToItem(indicator, 0, 0).y;
            fuzzyCompare(nextTop - bottomEdge, indicator.dotSpacing, 0.5, "uniform vertical gap after element " + i);
        }
    }

    function test_verticalCapsuleGrowsTall() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            const expected = (ids[i] === currentUuid) ? indicator.pillWidth : indicator.dotSize;
            fuzzyCompare(dot.height, expected, 0.5, "height of " + ids[i]);
            fuzzyCompare(dot.width, indicator.dotSize, 0.5, "width stays a dot for " + ids[i]);
        }
    }

    function test_verticalAdvertisesHeightViaLayout() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        verify(indicator.implicitHeight > 0, "indicator has a positive content height");
        compare(indicator.Layout.preferredHeight, indicator.implicitHeight, "preferredHeight advertises the natural content length");
        compare(indicator.Layout.maximumHeight, indicator.implicitHeight, "maximumHeight pins the natural length (a pager does not stretch past it)");
        verify(indicator.Layout.minimumHeight < indicator.implicitHeight, "minimumHeight drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumHeight, indicator.floorStripLength, 0.5, "minimumHeight is the floor (column at the minimum legible dot)");

        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth is one dot thick");
        const maxW = indicator.Layout.maximumWidth;
        verify(maxW < 0 || maxW > indicator.implicitWidth, "width axis is free (max unconstrained), so the panel fills the thickness");
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorCrossThickness, 0.5, "cross (width) min is the floor");
    }

    function test_verticalImplicitCrossAxis() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        fuzzyCompare(indicator.implicitWidth, indicator.dotSize + 2 * indicator.hoverCrossPadding, 0.5, "vertical strip is one dot wide");
        const steady = Logic.lineExtent(ids.length, indicator.dotSize, indicator.dotSpacing, indicator.pillWidth);
        fuzzyCompare(indicator.implicitHeight, steady + 2 * indicator.hoverPadding, 0.5, "vertical strip length is the steady-state formula");
    }

    function test_verticalMorphOnSwitch() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi, { vertical: true });
        verify(Math.abs(dotByUuid(indicator, ids[0]).height - indicator.pillWidth) <= 0.5, "ids[0] starts as the tall capsule");

        vdi.currentDesktop = ids[2];

        tryVerify(function () {
            return Math.abs(dotByUuid(indicator, ids[2]).height - indicator.pillWidth) <= 0.5
                && Math.abs(dotByUuid(indicator, ids[0]).height - indicator.dotSize) <= 0.5;
        }, 2000, "capsule morphs tall onto the newly current element; the old shrinks to a dot");
    }

    function test_verticalNoClipAtEnds() {
        const many = [ids[0], ids[1], ids[2], "uuid-d", "uuid-e", "uuid-f"];

        const atFirst = makeIndicator(makeMock(many, many[0]), { vertical: true });
        const firstDots = dotsByIndex(atFirst);
        const firstTop = firstDots[0].mapToItem(atFirst, 0, 0).y;
        verify(firstTop >= -0.5, "first element does not clip past the top edge");

        const atLast = makeIndicator(makeMock(many, many[many.length - 1]), { vertical: true });
        const lastDots = dotsByIndex(atLast);
        const last = lastDots[lastDots.length - 1];
        const lastBottom = last.mapToItem(atLast, 0, last.height).y;
        verify(lastBottom <= atLast.height + 0.5, "last element does not clip past the bottom edge");
    }

    // grid
    function test_gridMirrorsKWinRows() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2));
        compare(indicator.perLine, 2, "4 desktops / 2 rows → 2 per line");
        compare(indicator.lineCount, 2, "two lines");
        compare(collectDots(indicator).length, 4, "all four dots present");
    }

    function test_gridUnevenLastLine() {
        const indicator = makeIndicator(makeMock(fiveIds, fiveIds[0], [], 2));
        compare(indicator.perLine, 3, "5 desktops / 2 rows → 3 per line");
        compare(indicator.lineCount, 2, "two lines (second holds the remaining 2)");
        compare(collectDots(indicator).length, 5, "all five dots present");
    }

    function test_gridDefaultsToSingleLine() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0]));   // no rows → 1
        compare(indicator.perLine, 4, "single line holds all desktops");
        compare(indicator.lineCount, 1, "exactly one line by default");
    }

    function test_gridReactiveToRows() {
        const vdi = makeMock(fourIds, fourIds[0]);   // 1 row
        const indicator = makeIndicator(vdi);
        compare(indicator.lineCount, 1, "starts single-line");

        vdi.desktopLayoutRows = 2;   // as from System Settings

        tryCompare(indicator, "lineCount", 2, 2000, "grid re-lays out to two lines");
        compare(indicator.perLine, 2, "two per line after the change");
    }

    function test_gridStacksRowsHorizontally() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2));
        const dots = dotsByIndex(indicator);   // global order: [0,1] line 0, [2,3] line 1
        const y0 = dots[0].mapToItem(indicator, 0, 0).y;
        const y1 = dots[1].mapToItem(indicator, 0, 0).y;
        const y2 = dots[2].mapToItem(indicator, 0, 0).y;
        fuzzyCompare(y1, y0, 0.5, "the two dots of line 0 share a row");
        verify(y2 > y0 + 0.5, "line 1 sits below line 0");
    }

    function test_gridSizingTwoRows() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2));
        const major = Logic.lineExtent(indicator.perLine, indicator.dotSize, indicator.dotSpacing, indicator.pillWidth);
        const cross = Logic.lineExtent(indicator.lineCount, indicator.dotSize, indicator.dotSpacing, indicator.dotSize);
        fuzzyCompare(indicator.implicitWidth, major + 2 * indicator.hoverPadding, 0.5, "width is one line long");
        fuzzyCompare(indicator.implicitHeight, cross + 2 * indicator.hoverCrossPadding, 0.5, "height carries both lines");
        compare(indicator.Layout.maximumWidth, indicator.implicitWidth, "major (width) axis is pinned");
        verify(indicator.Layout.minimumHeight < indicator.implicitHeight, "cross (height) min drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumHeight, indicator.floorCrossThickness, 0.5, "cross (height) min is the floor (both lines at the min legible dot)");
        const maxH = indicator.Layout.maximumHeight;
        verify(maxH < 0 || maxH > indicator.implicitHeight, "cross axis max is free (fills panel thickness)");
    }

    function test_gridActiveCapsuleInSecondLine() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[3], [], 2));
        fuzzyCompare(dotByUuid(indicator, fourIds[3]).width, indicator.pillWidth, 0.5, "second-line current is the capsule");
        fuzzyCompare(dotByUuid(indicator, fourIds[0]).width, indicator.dotSize, 0.5, "a first-line inactive is a dot");
    }

    function test_gridNamesMapAcrossLines() {
        const names = ["One", "Two", "Three", "Four"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], names, 2));
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).desktopName, names[i], "dot " + i + " keeps its global name");
    }

    function test_gridVerticalTranspose() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true });
        compare(indicator.perLine, 2, "2 dots per line");
        compare(indicator.lineCount, 2, "two lines");
        const dots = dotsByIndex(indicator);   // [0,1] line 0, [2,3] line 1
        const p0 = dots[0].mapToItem(indicator, 0, 0);
        const p1 = dots[1].mapToItem(indicator, 0, 0);
        const p2 = dots[2].mapToItem(indicator, 0, 0);
        verify(p1.y > p0.y + 0.5, "dots stack vertically within a line");
        verify(p2.x > p0.x + 0.5, "the second line sits beside the first (transposed)");
    }

    // matchDesktopGrid and singleLine (#23)
    function test_gridVerticalResolution() {
        const transpose = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true });
        compare(transpose.gridVertical, true, "vertical panel, toggle off → transpose");

        const matched = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, matchDesktopGrid: true });
        compare(matched.gridVertical, false, "vertical panel, toggle on → match KWin (no transpose)");

        const horizontal = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { matchDesktopGrid: true });
        compare(horizontal.gridVertical, false, "horizontal panel: the toggle has no effect");

        // singleLine sets how many lines there are, never which way they run.
        const single = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, singleLine: true });
        compare(single.gridVertical, true, "single line alone, vertical panel → vertical strip (down the panel)");
        const both = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, singleLine: true, matchDesktopGrid: true });
        compare(both.gridVertical, false, "single line + match-grid → one HORIZONTAL row (match-grid sets the direction)");
        const singleHoriz = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { singleLine: true });
        compare(singleHoriz.gridVertical, false, "single line on a horizontal panel → horizontal strip");
    }

    function test_matchDesktopGridFaithfulMultiRow() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, matchDesktopGrid: true });
        compare(indicator.perLine, 2, "2 dots per line");
        compare(indicator.lineCount, 2, "two lines");
        const dots = dotsByIndex(indicator);   // [0,1] line 0, [2,3] line 1
        const y0 = dots[0].mapToItem(indicator, 0, 0).y;
        const y1 = dots[1].mapToItem(indicator, 0, 0).y;
        const y2 = dots[2].mapToItem(indicator, 0, 0).y;
        fuzzyCompare(y1, y0, 0.5, "the two dots of line 0 share a row (not stacked → not transposed)");
        verify(y2 > y0 + 0.5, "line 1 sits below line 0 (rows run top-to-bottom, like KWin)");
    }

    // The reporter's setup: two desktops in two rows on a vertical panel. No current desktop, so neither
    // dot is the wider pill and the one-column check is exact.
    function test_matchDesktopGridReporterCase() {
        const indicator = makeIndicator(makeMock(["uuid-a", "uuid-b"], staleUuid, [], 2), { vertical: true, matchDesktopGrid: true });
        compare(indicator.perLine, 1, "2 desktops / 2 rows → 1 per line");
        compare(indicator.lineCount, 2, "two lines");
        const dots = dotsByIndex(indicator);
        const p0 = dots[0].mapToItem(indicator, 0, 0);
        const p1 = dots[1].mapToItem(indicator, 0, 0);
        verify(p1.y > p0.y + 0.5, "the second desktop stacks below the first");
        fuzzyCompare(p1.x, p0.x, 0.5, "both desktops share one column (a vertical stack, not side by side)");
    }

    function test_matchDesktopGridIgnoredHorizontal() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { matchDesktopGrid: true });
        const dots = dotsByIndex(indicator);
        const y0 = dots[0].mapToItem(indicator, 0, 0).y;
        const y1 = dots[1].mapToItem(indicator, 0, 0).y;
        const y2 = dots[2].mapToItem(indicator, 0, 0).y;
        fuzzyCompare(y1, y0, 0.5, "line 0 dots share a row (unchanged by the toggle)");
        verify(y2 > y0 + 0.5, "line 1 below line 0 (unchanged by the toggle)");
    }

    function test_singleLineCollapsesGridToOneLine() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { singleLine: true });
        compare(indicator.perLine, 4, "all 4 desktops on one line");
        compare(indicator.lineCount, 1, "exactly one line (KWin's 2 rows are ignored)");
    }

    // What the reporter wanted: one strip down a vertical panel with a tall pill, rather than
    // matchDesktopGrid's column with a wide one.
    function test_singleLineVerticalStripHasVerticalPill() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, singleLine: true });
        compare(indicator.lineCount, 1, "one line on a vertical panel");
        const dots = dotsByIndex(indicator);
        verify(dots[1].mapToItem(indicator, 0, 0).y > dots[0].mapToItem(indicator, 0, 0).y + 0.5, "desktops stack down the panel");
        const active = dots[0];
        verify(active.height > active.width + 0.5, "the active desktop is a vertical (tall) pill, not a horizontal one");
    }

    function test_singleLineHorizontalRowOnVerticalPanel() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, singleLine: true, matchDesktopGrid: true });
        compare(indicator.lineCount, 1, "one line (grid collapsed)");
        compare(indicator.gridVertical, false, "laid out across the panel, not down it");
        const dots = dotsByIndex(indicator);
        verify(dots[1].mapToItem(indicator, 0, 0).x > dots[0].mapToItem(indicator, 0, 0).x + 0.5, "desktops run horizontally across the panel");
        verify(dots[0].width > dots[0].height + 0.5, "the active desktop is a horizontal pill");
    }

    // A strip sized by its content drifted the dots during a switch between rows. With no pill a content
    // sized strip is narrower, so its first dot moves; the morph test watches the same drift live.
    function test_multiRowStripPinnedRegardlessOfCapsule() {
        const opts = { width: 400, height: 200, dotSizeRequest: 16, pillWidthFactor: 4 };   // a long pill, room to spare
        const withCapsule = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), opts);
        const noCapsule = makeIndicator(makeMock(fourIds, staleUuid, [], 2), opts);
        const xCapsule = dotsByIndex(withCapsule)[0].mapToItem(withCapsule, 0, 0).x;
        const xNoCapsule = dotsByIndex(noCapsule)[0].mapToItem(noCapsule, 0, 0).x;
        fuzzyCompare(xNoCapsule, xCapsule, 0.5, "the strip (and so the dots) keep their position whether or not a capsule is present");
    }

    // sizes
    function test_metricsFlowThrough() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            dotSizeRequest: 20,
            pillWidthFactor: 3,
            spacingFactor: 1,
            inactiveOpacity: 0.3,
            hoverOpacity: 0.9
        });
        fuzzyCompare(indicator.dotSize, 20, 0.5, "dotSizeRequest resolves to dotSize");
        fuzzyCompare(indicator.pillWidth, 60, 0.5, "pillWidth = dotSize * pillWidthFactor");
        fuzzyCompare(indicator.dotSpacing, 20, 0.5, "dotSpacing = dotSize * spacingFactor");

        const dot = dotByUuid(indicator, ids[0]);
        fuzzyCompare(dot.dotSize, 20, 0.5, "dot gets the resolved dotSize");
        fuzzyCompare(dot.pillWidthFactor, 3, 0.5, "dot gets pillWidthFactor");
        fuzzyCompare(dot.inactiveOpacity, 0.3, 0.001, "dot gets inactiveOpacity");
        fuzzyCompare(dot.hoverOpacity, 0.9, 0.001, "dot gets hoverOpacity");
    }

    function test_dotSizeSentinelDefault() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.dotSizeRequest, 0, "request defaults to the 0 sentinel");
        fuzzyCompare(indicator.dotSize, Kirigami.Units.iconSizes.small / 2, 0.5, "0 resolves to the themed default");
    }

    function test_autoPillTracksDotSize() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 20, pillWidthFactor: 3 });
        compare(indicator.pillSizeRequest, 0, "pill request defaults to the 0 (match-dots) sentinel");
        fuzzyCompare(indicator.pillThicknessRatio, 1, 0.001, "auto pill thickness ratio is 1");
        fuzzyCompare(indicator.pillSize, 20, 0.5, "auto pill thickness == the dot size");
        fuzzyCompare(indicator.pillWidth, 60, 0.5, "pillWidth = dotSize * pillWidthFactor when the pill tracks the dots");
    }

    // Room to spare, so shrinking to fit stays out of it.
    function test_independentThickerPill() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 8, pillSizeRequest: 24, pillWidthFactor: 3 });
        indicator.width = indicator.naturalStripLength * 2;
        indicator.height = indicator.naturalCrossThickness * 2;
        fuzzyCompare(indicator.dotSize, 8, 0.5, "dots keep their own size");
        fuzzyCompare(indicator.pillSize, 24, 0.5, "pill thickness is independent of the dots");
        fuzzyCompare(indicator.pillWidth, 72, 0.5, "pillWidth = pillSize * pillWidthFactor");

        const activeDot = dotByUuid(indicator, currentUuid);
        fuzzyCompare(activeDot.height, 24, 0.5, "active dot is pill-thick on the cross axis");
        fuzzyCompare(activeDot.width, 72, 0.5, "active dot is pill-long on the major axis");

        const inactiveDot = dotByUuid(indicator, ids[0]);
        fuzzyCompare(inactiveDot.height, 8, 0.5, "inactive dot stays a small dot on the cross axis");
        fuzzyCompare(inactiveDot.width, 8, 0.5, "inactive dot stays a small dot on the major axis");
    }

    function test_pillThicknessAdvertisedOnCrossAxis() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 8, pillSizeRequest: 24 });
        fuzzyCompare(indicator.naturalCrossThickness, 24, 0.5, "cross thickness is the thicker pill, not the dot");
        fuzzyCompare(indicator.implicitHeight, 24 + 2 * indicator.hoverCrossPadding, 0.5, "implicitHeight advertises the pill thickness on a horizontal strip");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalStripLength + 2 * indicator.hoverPadding, 0.5, "major axis still advertises the strip length");
    }

    function test_pillScalesWithFitShrink() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 16, pillSizeRequest: 32, pillWidthFactor: 3 });
        const ratio = indicator.pillThicknessRatio;   // 32 / 16 == 2
        fuzzyCompare(ratio, 2, 0.001, "configured ratio is pill/dot");
        indicator.width = indicator.naturalStripLength * 0.5;   // still above the floor
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "dot shrank below natural");
        fuzzyCompare(indicator.pillSize / indicator.dotSize, ratio, 0.01, "pill thickness keeps the configured ratio while shrinking");
        fuzzyCompare(indicator.pillWidth, indicator.pillSize * indicator.pillWidthFactor, 0.5, "pillWidth tracks the shrunk pill thickness");
    }

    // The ring style ignores the pill settings, so they're set here to prove it.
    function test_filledRingStyleNoPill() {
        const indicator = makeIndicator(makeMock(ids, currentUuid),
            { dotStyle: Logic.DOT_STYLE.Ring, dotSizeRequest: 16, pillSizeRequest: 40, pillWidthFactor: 4 });
        indicator.width = indicator.naturalStripLength * 2;
        indicator.height = indicator.naturalCrossThickness * 2;

        fuzzyCompare(indicator.effPillWidthFactor, 1, 0.001, "ring style neutralizes pillWidthFactor to 1");
        compare(indicator.effPillSizeRequest, 0, "ring style neutralizes pillSizeRequest to 0 (match dots)");
        fuzzyCompare(indicator.pillThicknessRatio, 1, 0.001, "pill thickness ratio is 1 (no thick pill)");
        fuzzyCompare(indicator.pillWidth, indicator.dotSize, 0.5, "the active extent equals the dot size (no pill)");

        const activeDot = dotByUuid(indicator, currentUuid);
        const inactiveDot = dotByUuid(indicator, ids[0]);
        fuzzyCompare(activeDot.width, inactiveDot.width, 0.5, "active dot is no wider than an inactive one (no pill)");
        fuzzyCompare(activeDot.height, inactiveDot.height, 0.5, "active dot is no taller than an inactive one");
        fuzzyCompare(activeDot.width, indicator.dotSize, 0.5, "every dot is dot-sized on the major axis");
    }

    // Set after construction, since makeMock's `|| 1` would turn a 0 into 1.
    function test_gridRowsClampGuard() {
        const vdi = makeMock(fourIds, fourIds[0]);
        const indicator = makeIndicator(vdi);
        vdi.desktopLayoutRows = 0;

        compare(indicator.desktopRows, 1, "a 0 row count clamps to a single line");
        compare(indicator.lineCount, 1, "everything stays on one line");
        compare(indicator.perLine, fourIds.length, "the single line holds all desktops");
    }

    // shrinking to fit

    // Setting width directly, as the panel does, replaces the implicitWidth binding.
    function test_scaleDotsShrinkOnNarrowWidth() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 0.6;
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "effective dot shrank below natural");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        fuzzyCompare(dotByUuid(indicator, sixIds[1]).dotSize, indicator.dotSize, 0.5, "each dot uses the effective size");
        // The widths animate there.
        tryVerify(() => lastElementFits(indicator, "x"), 2000, "the shrunken line fits the allocated width");
    }

    function test_scaleDotsUnchangedWhenAmple() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 2;
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.5, "no shrink when there is room");
        fuzzyCompare(dotByUuid(indicator, sixIds[0]).width, indicator.pillWidth, 0.5, "capsule at the natural pill width");
    }

    function test_scaleDotsShrinkOnShortHeightVertical() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]), { vertical: true });
        indicator.height = indicator.naturalStripLength * 0.6;
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "vertical effective dot shrank");
        // The heights animate there.
        tryVerify(() => lastElementFits(indicator, "y"), 2000, "the shrunken column fits the allocated height");
    }

    // Four rows on a thin panel. The cross fit is the exact inverse of the stacked lines, so 0.6 of their
    // natural thickness gives dots 0.6 of their natural size, still above the floor.
    function test_scaleDotsShrinkOnThinCrossMultiRow() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));   // 4 lines of 3
        indicator.height = indicator.naturalCrossThickness * 0.6;
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "cross-fit shrank the dot below natural");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        tryVerify(() => lastElementFits(indicator, "y"), 2000, "the shrunken grid fits the allocated cross thickness");
    }

    function test_scaleDotsCrossUnchangedWhenAmpleThickness() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));
        indicator.height = indicator.naturalCrossThickness * 2;
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.5, "no shrink when the thickness is ample");
    }

    function test_scaleDotsShrinkOnThinCrossVertical() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4), { vertical: true });
        indicator.width = indicator.naturalCrossThickness * 0.6;
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "cross-fit shrank the dot below natural (vertical)");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        tryVerify(() => lastElementFits(indicator, "x"), 2000, "the shrunken grid fits the allocated cross thickness (width)");
    }

    function test_manyDesktopsMultiRowGrid() {
        const big = manyIds(20);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));
        compare(collectDots(indicator).length, 20, "all 20 dots render across the grid");
        compare(indicator.desktopRows, 4, "mirrors KWin's 4 rows");
        compare(indicator.perLine, 5, "ceil(20/4) per line");
        compare(indicator.lineCount, 4, "4 grid lines");
    }

    // Below the floor the strip overflows rather than draw dots too small to read.
    function test_scaleClampsAtFloorOnExtremeNarrow() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 0.3;
        tryVerify(() => Math.abs(indicator.dotSize - indicator.minDotSize) < 0.001, 2000,
                  "the effective dot clamps exactly at the legible floor");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "never shrinks past the floor");
    }

    // A configured dot smaller than the floor mustn't grow to it, however much room there is.
    function test_scaleNeverEnlargesTinyConfiguredDot() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 2 });
        fuzzyCompare(indicator.naturalDotSize, 2, 0.001, "a tiny request is the natural size");
        fuzzyCompare(indicator.minDotSize, 2, 0.001, "minDotSize clamps to natural (never above it)");
        indicator.width = indicator.naturalStripLength * 4;
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.001, "huge room never scales the dot UP past natural");
    }

    // The positioner's default alignment put the dots at the top of a line made thick by the pill.
    function test_inactiveDotCentredAgainstThickPillHorizontal() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 8, pillSizeRequest: 24 });
        indicator.width = indicator.naturalStripLength * 2;
        indicator.height = indicator.naturalCrossThickness * 2;
        const active = dotByUuid(indicator, currentUuid);
        const inactive = dotByUuid(indicator, ids[0]);
        const activeCentreY = Elements.centerOf(active, indicator).y;
        const inactiveCentreY = Elements.centerOf(inactive, indicator).y;
        fuzzyCompare(inactiveCentreY, activeCentreY, 0.5, "inactive dot is cross-centred against the thicker pill");
    }

    function test_inactiveDotCentredAgainstThickPillVertical() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true, dotSizeRequest: 8, pillSizeRequest: 24 });
        indicator.height = indicator.naturalStripLength * 2;
        indicator.width = indicator.naturalCrossThickness * 2;
        const active = dotByUuid(indicator, currentUuid);
        const inactive = dotByUuid(indicator, ids[0]);
        const activeCentreX = Elements.centerOf(active, indicator).x;
        const inactiveCentreX = Elements.centerOf(inactive, indicator).x;
        fuzzyCompare(inactiveCentreX, activeCentreX, 0.5, "inactive dot is cross-centred against the thicker pill (vertical)");
    }

    function test_pillFloorAtExtremeNarrow() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]), { dotSizeRequest: 16, pillSizeRequest: 32 });
        const ratio = indicator.pillThicknessRatio;
        indicator.width = indicator.naturalStripLength * 0.2;
        tryVerify(() => Math.abs(indicator.dotSize - indicator.minDotSize) < 0.001, 2000,
                  "the effective dot clamps exactly at the legible floor");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "dot never shrinks past the floor");
        fuzzyCompare(indicator.pillSize, indicator.minDotSize * ratio, 0.01, "pill clamps at its proportional floor (minDotSize * ratio)");
        verify(indicator.pillSize >= indicator.minDotSize * ratio - 0.01, "pill never shrinks past its floor");
    }

    // The price of every row keeping the reflow look: rows don't share column widths.
    function test_gridLinesSizedIndependently() {
        const indicator = makeIndicator(makeMock(fiveIds, fiveIds[0], [], 2));
        compare(indicator.perLine, 3, "3 per line");
        compare(indicator.lineCount, 2, "two lines");
        const dots = dotsByIndex(indicator);   // [0,1,2] line 0 (capsule at 0), [3,4] line 1
        const line0Width = dots[2].mapToItem(indicator, dots[2].width, 0).x - dots[0].mapToItem(indicator, 0, 0).x;
        const line1Width = dots[4].mapToItem(indicator, dots[4].width, 0).x - dots[3].mapToItem(indicator, 0, 0).x;
        verify(line0Width > line1Width + 0.5, "the capsule-bearing line is wider than the short trailing line");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalStripLength + 2 * indicator.hoverPadding, 0.5, "the strip width is the wider (full) line");
    }

    // A panel moved to a side edge while running. Ample room, so nothing shrinks.
    function test_runtimeFormFactorFlip() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 400, height: 400 });
        const cap = dotByUuid(indicator, currentUuid);
        fuzzyCompare(cap.width, indicator.pillWidth, 0.5, "horizontal: the capsule's long axis is width");
        fuzzyCompare(cap.height, indicator.pillSize, 0.5, "horizontal: the capsule's cross axis is the pill thickness");

        indicator.vertical = true;

        tryVerify(function () {
            return Math.abs(cap.height - indicator.pillWidth) <= 0.5
                && Math.abs(cap.width - indicator.pillSize) <= 0.5;
        }, 2000, "after the flip the capsule's long axis becomes height; the cross axis becomes width");

        compare(indicator.Layout.preferredHeight, indicator.implicitHeight, "major (height) preferred now pins the strip length");
        compare(indicator.Layout.maximumHeight, indicator.implicitHeight, "major (height) maximum pins the natural length");
        const maxW = indicator.Layout.maximumWidth;
        verify(maxW < 0 || maxW > indicator.implicitWidth, "cross (width) axis is now free to fill the panel thickness");
    }
}
