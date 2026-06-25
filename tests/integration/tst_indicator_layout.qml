/*
 * Plasma Gnome Pager — tst_indicator_layout.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Layout: Layout.* advertising, vertical form factor, the multi-row grid, metric/pill sizing, and
 * scale-to-fit.
 * Derives from the shared IndicatorTestCase (tests/shared/) for the fixtures: the component
 * factory, the VirtualDesktopInfo doubles, the switchRequested spy, and the dot-tree locators.
 */
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../shared"
import "../../package/contents/ui/logic.js" as Logic
import "../shared/elements.js" as Elements

IndicatorTestCase {
    id: layoutCase
    name: "IndicatorLayout"

    // panel sizing: advertising only implicitWidth collapsed the applet to a square cell in-shell (dots
    // overflowed). The indicator must expose its content width through Layout.* hints.
    function test_advertisesWidthViaLayout() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator.implicitWidth > 0, "indicator has a positive content width");
        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth advertises the natural content width");
        compare(indicator.Layout.maximumWidth, indicator.implicitWidth, "maximumWidth pins the natural width (a pager does not stretch past it)");
        // scale-to-fit: the MINIMUM drops to the floor (one line at minDotSize) so the panel can compress us.
        verify(indicator.minDotSize < indicator.naturalDotSize, "the legible floor dot is smaller than natural");
        verify(indicator.Layout.minimumWidth < indicator.implicitWidth, "minimumWidth drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorStripLength, 0.5, "minimumWidth is the floor (strip at the minimum legible dot)");
    }

    // vertical form factor: a side panel becomes a single COLUMN (dots stack along Y, the capsule grows
    // TALL, the pinned/free Layout axes swap). These mirror the horizontal geometry/sizing onto Y/height.

    // The dots stack top-to-bottom (strictly increasing Y), all in one column (≈ equal X).
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

    // Uniform spacing along Y: the vertical gap between EVERY adjacent pair equals the strip spacing.
    function test_verticalUniformSpacing() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });   // middle is the capsule
        const dots = dotsByIndex(indicator);
        for (let i = 0; i < dots.length - 1; i++) {
            const bottomEdge = dots[i].mapToItem(indicator, 0, dots[i].height).y;
            const nextTop = dots[i + 1].mapToItem(indicator, 0, 0).y;
            fuzzyCompare(nextTop - bottomEdge, indicator.dotSpacing, 0.5, "uniform vertical gap after element " + i);
        }
    }

    // The active element grows TALL to pillWidth along the major (Y) axis; inactive stay dots.
    function test_verticalCapsuleGrowsTall() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            const expected = (ids[i] === currentUuid) ? indicator.pillWidth : indicator.dotSize;
            fuzzyCompare(dot.height, expected, 0.5, "height of " + ids[i]);
            fuzzyCompare(dot.width, indicator.dotSize, 0.5, "width stays a dot for " + ids[i]);
        }
    }

    // Vertical sizing: the HEIGHT axis is pinned to the strip length, the WIDTH axis left free so the
    // panel stretches to its thickness. Mirror of test_advertisesWidthViaLayout.
    function test_verticalAdvertisesHeightViaLayout() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        verify(indicator.implicitHeight > 0, "indicator has a positive content height");
        compare(indicator.Layout.preferredHeight, indicator.implicitHeight, "preferredHeight advertises the natural content length");
        compare(indicator.Layout.maximumHeight, indicator.implicitHeight, "maximumHeight pins the natural length (a pager does not stretch past it)");
        // scale-to-fit: the MAJOR (height) minimum drops to the floor so a short panel compresses the column.
        verify(indicator.Layout.minimumHeight < indicator.implicitHeight, "minimumHeight drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumHeight, indicator.floorStripLength, 0.5, "minimumHeight is the floor (column at the minimum legible dot)");

        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth is one dot thick");
        const maxW = indicator.Layout.maximumWidth;
        verify(maxW < 0 || maxW > indicator.implicitWidth, "width axis is free (max unconstrained), so the panel fills the thickness");
        // Cross (width) MINIMUM drops to floorCrossThickness too, so an ultra-thin side panel can compress it.
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorCrossThickness, 0.5, "cross (width) min is the floor");
    }

    // The cross axis is one dot thick.
    function test_verticalImplicitCrossAxis() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        fuzzyCompare(indicator.implicitWidth, indicator.dotSize, 0.5, "vertical strip is one dot wide");
        const steady = Logic.lineExtent(ids.length, indicator.dotSize, indicator.dotSpacing, indicator.pillWidth);
        fuzzyCompare(indicator.implicitHeight, steady, 0.5, "vertical strip length is the steady-state formula");
    }

    // Switching morphs the capsule along the height: the new current grows tall, the old shrinks to a dot.
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

    // The advertised length holds the whole column, so the end elements never clip past the edges.
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

    // multi-row grid (mirrors KWin's desktopLayoutRows): >1 row splits the desktops into that many LINES,
    // each an independent single-line reflow strip. Driven live by desktopLayoutRows; defaults to 1.

    // rows=2 over 4 desktops → 2 lines of 2; the indicator exposes perLine/lineCount.
    function test_gridMirrorsKWinRows() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2));
        compare(indicator.perLine, 2, "4 desktops / 2 rows → 2 per line");
        compare(indicator.lineCount, 2, "two lines");
        compare(collectDots(indicator).length, 4, "all four dots present");
    }

    // ceil rounding: 5 desktops / 2 rows → 3 per line, 2 lines (last line short with 2).
    function test_gridUnevenLastLine() {
        const indicator = makeIndicator(makeMock(fiveIds, fiveIds[0], [], 2));
        compare(indicator.perLine, 3, "5 desktops / 2 rows → 3 per line");
        compare(indicator.lineCount, 2, "two lines (second holds the remaining 2)");
        compare(collectDots(indicator).length, 5, "all five dots present");
    }

    // Default / 1 row stays a single line.
    function test_gridDefaultsToSingleLine() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0]));   // no rows → 1
        compare(indicator.perLine, 4, "single line holds all desktops");
        compare(indicator.lineCount, 1, "exactly one line by default");
    }

    // Changing KWin's row count re-lays out reactively (no cache; mirrors System Settings live).
    function test_gridReactiveToRows() {
        const vdi = makeMock(fourIds, fourIds[0]);   // 1 row
        const indicator = makeIndicator(vdi);
        compare(indicator.lineCount, 1, "starts single-line");

        vdi.desktopLayoutRows = 2;   // user raises "Rows" in System Settings

        tryCompare(indicator, "lineCount", 2, 2000, "grid re-lays out to two lines");
        compare(indicator.perLine, 2, "two per line after the change");
    }

    // Horizontal panel, 2 rows: dots split into two vertically-stacked lines (the second below the
    // first); within a line the dots share a row (equal y).
    function test_gridStacksRowsHorizontally() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2));
        const dots = dotsByIndex(indicator);   // global order: [0,1] line 0, [2,3] line 1
        const y0 = dots[0].mapToItem(indicator, 0, 0).y;
        const y1 = dots[1].mapToItem(indicator, 0, 0).y;
        const y2 = dots[2].mapToItem(indicator, 0, 0).y;
        fuzzyCompare(y1, y0, 0.5, "the two dots of line 0 share a row");
        verify(y2 > y0 + 0.5, "line 1 sits below line 0");
    }

    // 2-D sizing: the major (width) axis is pinned to one line's length; the cross (height) axis
    // preferreds both lines, but its minimum drops to the floor (cross scale-to-fit) and its maximum is
    // left free to fill the panel thickness.
    function test_gridSizingTwoRows() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2));
        const major = Logic.lineExtent(indicator.perLine, indicator.dotSize, indicator.dotSpacing, indicator.pillWidth);
        // Cross thickness has no capsule (every line is one dot thick) → activeExtent == dotSize.
        const cross = Logic.lineExtent(indicator.lineCount, indicator.dotSize, indicator.dotSpacing, indicator.dotSize);
        fuzzyCompare(indicator.implicitWidth, major, 0.5, "width is one line long");
        fuzzyCompare(indicator.implicitHeight, cross, 0.5, "height carries both lines");
        compare(indicator.Layout.maximumWidth, indicator.implicitWidth, "major (width) axis is pinned");
        // Cross (height) MIN now drops to floorCrossThickness so a thin panel can compress the thickness
        // and the dots cross-fit instead of overflowing it (was pinned to the natural thickness pre-fit).
        verify(indicator.Layout.minimumHeight < indicator.implicitHeight, "cross (height) min drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumHeight, indicator.floorCrossThickness, 0.5, "cross (height) min is the floor (both lines at the min legible dot)");
        const maxH = indicator.Layout.maximumHeight;
        verify(maxH < 0 || maxH > indicator.implicitHeight, "cross axis max is free (fills panel thickness)");
    }

    // The active capsule still morphs when the current desktop lives in the second line.
    function test_gridActiveCapsuleInSecondLine() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[3], [], 2));   // current is in line 1
        fuzzyCompare(dotByUuid(indicator, fourIds[3]).width, indicator.pillWidth, 0.5, "second-line current is the capsule");
        fuzzyCompare(dotByUuid(indicator, fourIds[0]).width, indicator.dotSize, 0.5, "a first-line inactive is a dot");
    }

    // Names are index-aligned across the whole flat desktop list, not reset per line.
    function test_gridNamesMapAcrossLines() {
        const names = ["One", "Two", "Three", "Four"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], names, 2));
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).desktopName, names[i], "dot " + i + " keeps its global name");
    }

    // Vertical panel, 2 rows: the grid transposes — lines sit side by side (different x), dots
    // stack within each line (increasing y), so the longer per-line extent runs down the panel.
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

    // --- matchDesktopGrid: lay the grid out in KWin orientation on a vertical panel (issue #23) -----------

    // gridVertical (the effective grid orientation) is the panel `vertical` UNLESS matchDesktopGrid un-transposes
    // it. The toggle is inert on a horizontal panel and applies to every row count on a vertical one.
    function test_gridVerticalResolution() {
        const transpose = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true });
        compare(transpose.gridVertical, true, "vertical panel, toggle off → transpose");

        const matched = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { vertical: true, matchDesktopGrid: true });
        compare(matched.gridVertical, false, "vertical panel, toggle on → match KWin (no transpose)");

        const horizontal = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { matchDesktopGrid: true });
        compare(horizontal.gridVertical, false, "horizontal panel: the toggle has no effect");
    }

    // Vertical panel, 2 rows, toggle ON: the grid is NOT transposed — it lays out exactly like a horizontal
    // panel (lines stack along Y, dots within a line share a row). The inverse of test_gridVerticalTranspose.
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

    // The exact issue-#23 scenario: 2 desktops with KWin Rows=2 on a vertical panel. With the toggle ON the
    // two dots stack vertically (one column) to match the desktop layout, instead of sitting side by side.
    // current is a transient/unknown uuid so neither dot is the wider capsule — both are equal-size dots,
    // making the single-column assertion exact no matter how the lines align.
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

    // A horizontal panel already mirrors KWin's grid, so the toggle is a no-op there: same layout as toggle off.
    function test_matchDesktopGridIgnoredHorizontal() {
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { matchDesktopGrid: true });
        const dots = dotsByIndex(indicator);
        const y0 = dots[0].mapToItem(indicator, 0, 0).y;
        const y1 = dots[1].mapToItem(indicator, 0, 0).y;
        const y2 = dots[2].mapToItem(indicator, 0, 0).y;
        fuzzyCompare(y1, y0, 0.5, "line 0 dots share a row (unchanged by the toggle)");
        verify(y2 > y0 + 0.5, "line 1 below line 0 (unchanged by the toggle)");
    }

    // Multi-row "breathing" fix: the strip is pinned to the conserved (capsule-bearing) extent, so its footprint
    // — and so the dots — do NOT depend on whether/where the capsule is. A cross-row morph therefore can't
    // resize+recenter the strip and drag the dots. Deterministic proxy: the leftmost dot's absolute position is
    // identical with a capsule present (valid current) vs. transiently absent (stale current). Before the fix the
    // content-sized strip is narrower with no capsule, so its centred dots sit further right (test fails).
    function test_multiRowStripPinnedRegardlessOfCapsule() {
        const opts = { width: 400, height: 200, dotSizeRequest: 16, pillWidthFactor: 4 };   // big Δ, ample room
        const withCapsule = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), opts);
        const noCapsule = makeIndicator(makeMock(fourIds, staleUuid, [], 2), opts);
        const xCapsule = dotsByIndex(withCapsule)[0].mapToItem(withCapsule, 0, 0).x;
        const xNoCapsule = dotsByIndex(noCapsule)[0].mapToItem(noCapsule, 0, 0).x;
        fuzzyCompare(xNoCapsule, xCapsule, 0.5, "the strip (and so the dots) keep their position whether or not a capsule is present");
    }

    // per-dot tooltip data: the indicator feeds each dot its name and the flag.

    // Metrics reach the derived sizes and every dot.
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

    // The dotSize sentinel: 0 (the default request) → the HiDPI themed size, never 0.
    function test_dotSizeSentinelDefault() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));   // no dotSizeRequest → 0
        compare(indicator.dotSizeRequest, 0, "request defaults to the 0 sentinel");
        fuzzyCompare(indicator.dotSize, Kirigami.Units.iconSizes.small / 2, 0.5, "0 resolves to the themed default");
    }

    // The pillSize sentinel: 0 (default) → "match dots", so the pill tracks the dot size (ratio 1).
    function test_autoPillTracksDotSize() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 20, pillWidthFactor: 3 });
        compare(indicator.pillSizeRequest, 0, "pill request defaults to the 0 (match-dots) sentinel");
        fuzzyCompare(indicator.pillThicknessRatio, 1, 0.001, "auto pill thickness ratio is 1");
        fuzzyCompare(indicator.pillSize, 20, 0.5, "auto pill thickness == the dot size");
        fuzzyCompare(indicator.pillWidth, 60, 0.5, "pillWidth = dotSize * pillWidthFactor when the pill tracks the dots");
    }

    // Independent sizing: small dots under a thick pill keep their own size; pill length is
    // pillSize * pillWidthFactor. Ample allocation so scale-to-fit does not interfere.
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

    // A pill thicker than the dots raises the advertised CROSS thickness to the pill, so the panel
    // allocates room for it.
    function test_pillThicknessAdvertisedOnCrossAxis() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 8, pillSizeRequest: 24 });
        fuzzyCompare(indicator.naturalCrossThickness, 24, 0.5, "cross thickness is the thicker pill, not the dot");
        fuzzyCompare(indicator.implicitHeight, 24, 0.5, "implicitHeight advertises the pill thickness on a horizontal strip");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalStripLength, 0.5, "major axis still advertises the strip length");
    }

    // Independent pill + dot shrink in LOCKSTEP under scale-to-fit: the configured pill:dot ratio holds.
    function test_pillScalesWithFitShrink() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 16, pillSizeRequest: 32, pillWidthFactor: 3 });
        const ratio = indicator.pillThicknessRatio;   // 32 / 16 == 2
        fuzzyCompare(ratio, 2, 0.001, "configured ratio is pill/dot");
        indicator.width = indicator.naturalStripLength * 0.5;   // force a major-axis shrink (stays above the floor)
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "dot shrank below natural");
        fuzzyCompare(indicator.pillSize / indicator.dotSize, ratio, 0.01, "pill thickness keeps the configured ratio while shrinking");
        fuzzyCompare(indicator.pillWidth, indicator.pillSize * indicator.pillWidthFactor, 0.5, "pillWidth tracks the shrunk pill thickness");
    }

    // Filled & ring style: NO pill. The indicator neutralizes the pill params, so the current dot is the
    // SAME size as the inactive dots (a filled circle, not a wider capsule) — a uniform row. The configured
    // pill knobs (pillSizeRequest / pillWidthFactor) are ignored in this style.
    function test_filledRingStyleNoPill() {
        const indicator = makeIndicator(makeMock(ids, currentUuid),
            { dotStyle: Logic.DOT_STYLE.Ring, dotSizeRequest: 16, pillSizeRequest: 40, pillWidthFactor: 4 });
        indicator.width = indicator.naturalStripLength * 2;    // ample allocation: no scale-to-fit
        indicator.height = indicator.naturalCrossThickness * 2;

        // The pill is neutralized: ratio 1, the active extent collapses to the dot size.
        fuzzyCompare(indicator.effPillWidthFactor, 1, 0.001, "ring style neutralizes pillWidthFactor to 1");
        compare(indicator.effPillSizeRequest, 0, "ring style neutralizes pillSizeRequest to 0 (match dots)");
        fuzzyCompare(indicator.pillThicknessRatio, 1, 0.001, "pill thickness ratio is 1 (no thick pill)");
        fuzzyCompare(indicator.pillWidth, indicator.dotSize, 0.5, "the active extent equals the dot size (no pill)");

        // Every dot is the same size — the current one is no wider/taller than the rest.
        const activeDot = dotByUuid(indicator, currentUuid);
        const inactiveDot = dotByUuid(indicator, ids[0]);
        fuzzyCompare(activeDot.width, inactiveDot.width, 0.5, "active dot is no wider than an inactive one (no pill)");
        fuzzyCompare(activeDot.height, inactiveDot.height, 0.5, "active dot is no taller than an inactive one");
        fuzzyCompare(activeDot.width, indicator.dotSize, 0.5, "every dot is dot-sized on the major axis");
    }

    // desktopRows clamp guard: the indicator clamps a transient 0/undefined desktopLayoutRows to a single
    // line. makeMock's `|| 1` default hides a literal 0, so set it post-construction.
    function test_gridRowsClampGuard() {
        const vdi = makeMock(fourIds, fourIds[0]);   // defaults to 1 row
        const indicator = makeIndicator(vdi);
        vdi.desktopLayoutRows = 0;                   // transient/invalid value from KWin

        compare(indicator.desktopRows, 1, "a 0 row count clamps to a single line");
        compare(indicator.lineCount, 1, "everything stays on one line");
        compare(indicator.perLine, fourIds.length, "the single line holds all desktops");
    }

    // A narrow allocation shrinks the dots below natural so the line still fits instead of overflowing.
    // Setting indicator.width directly replaces the implicitWidth binding — how the panel constrains us.
    function test_scaleDotsShrinkOnNarrowWidth() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 0.6;   // panel grants 60% of the natural length
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "effective dot shrank below natural");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        fuzzyCompare(dotByUuid(indicator, sixIds[1]).dotSize, indicator.dotSize, 0.5, "each dot uses the effective size");
        // tryVerify: the rendered dot widths morph (Behavior on width), so wait for the reflow to settle.
        tryVerify(() => lastElementFits(indicator, "x"), 2000, "the shrunken line fits the allocated width");
    }

    // With ample room the size is unchanged: effective == natural, the look is byte-for-byte as today.
    function test_scaleDotsUnchangedWhenAmple() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 2;     // plenty of room
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.5, "no shrink when there is room");
        fuzzyCompare(dotByUuid(indicator, sixIds[0]).width, indicator.pillWidth, 0.5, "capsule at the natural pill width");
    }

    // Vertical transpose: a short allocated HEIGHT is the major axis, so the dots shrink there too.
    function test_scaleDotsShrinkOnShortHeightVertical() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]), { vertical: true });
        indicator.height = indicator.naturalStripLength * 0.6;
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "vertical effective dot shrank");
        // tryVerify: the rendered dot heights morph (Behavior on height), so wait for the reflow to settle.
        tryVerify(() => lastElementFits(indicator, "y"), 2000, "the shrunken column fits the allocated height");
    }

    // CROSS-axis scale-to-fit: a 4-row grid on a THIN horizontal panel constrains only the cross (height)
    // thickness, so the dots shrink to fit the stacked lines. Setting height to f × naturalCrossThickness
    // yields dotSize f × naturalDotSize (the cross fit is the exact inverse), so f == 0.6 stays above the floor.
    function test_scaleDotsShrinkOnThinCrossMultiRow() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));   // 4 lines of 3
        indicator.height = indicator.naturalCrossThickness * 0.6;        // panel thinner than the 4 stacked lines need
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "cross-fit shrank the dot below natural");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        // wait for the reflow to settle; the last line sits in the bottom row, so its bottom must fit.
        tryVerify(() => lastElementFits(indicator, "y"), 2000, "the shrunken grid fits the allocated cross thickness");
    }

    // With ample thickness the multi-row grid is unchanged: the cross fit exceeds natural, so keep natural.
    function test_scaleDotsCrossUnchangedWhenAmpleThickness() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));
        indicator.height = indicator.naturalCrossThickness * 2;          // plenty of cross room
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.5, "no shrink when the thickness is ample");
    }

    // Vertical transpose of the cross-fit: on a side panel the cross axis is WIDTH, so a thin one shrinks
    // the dots to fit the width.
    function test_scaleDotsShrinkOnThinCrossVertical() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4), { vertical: true });
        indicator.width = indicator.naturalCrossThickness * 0.6;         // side panel thinner than the stacked lines need
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "cross-fit shrank the dot below natural (vertical)");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        tryVerify(() => lastElementFits(indicator, "x"), 2000, "the shrunken grid fits the allocated cross thickness (width)");
    }

    // Many desktops across a mirrored KWin grid (4 rows): all dots render, split into the right lines.
    function test_manyDesktopsMultiRowGrid() {
        const big = manyIds(20);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));
        compare(collectDots(indicator).length, 20, "all 20 dots render across the grid");
        compare(indicator.desktopRows, 4, "mirrors KWin's 4 rows");
        compare(indicator.perLine, 5, "ceil(20/4) per line");
        compare(indicator.lineCount, 4, "4 grid lines");
    }

    // An EXTREME narrow allocation (0.3×, below the floor) clamps the effective dot exactly at minDotSize —
    // no further (overflow accepted over illegible dots).
    function test_scaleClampsAtFloorOnExtremeNarrow() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 0.3;   // far below the legible floor
        tryVerify(() => Math.abs(indicator.dotSize - indicator.minDotSize) < 0.001, 2000,
                  "the effective dot clamps exactly at the legible floor");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "never shrinks past the floor");
    }

    // The clamp NEVER scales UP: a configured dot smaller than the floor makes minDotSize == naturalDotSize
    // (minDotSize clamps DOWN to natural), so even an enormous allocation keeps the tiny natural size —
    // scale-to-fit only ever shrinks. Guards the Math.min(naturalDotSize, …) on minDotSize.
    function test_scaleNeverEnlargesTinyConfiguredDot() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { dotSizeRequest: 2 });
        fuzzyCompare(indicator.naturalDotSize, 2, 0.001, "a tiny request is the natural size");
        fuzzyCompare(indicator.minDotSize, 2, 0.001, "minDotSize clamps to natural (never above it)");
        indicator.width = indicator.naturalStripLength * 4;     // an enormous allocation
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.001, "huge room never scales the dot UP past natural");
    }

    // Cross-axis centring: an inactive dot must sit centred against a thicker pill, not top-aligned
    // (the line is as thick as the capsule). Compares the dots' cross-axis centre lines.
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

    // Vertical-strip transpose of the centring fix: the cross axis is X, so an inactive dot centres on X.
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

    // Floor (extreme narrow) with a thick pill: the dot clamps at minDotSize and the pill at its
    // proportional floor minDotSize * ratio — neither shrinks further, and the lockstep ratio holds.
    function test_pillFloorAtExtremeNarrow() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]), { dotSizeRequest: 16, pillSizeRequest: 32 });
        const ratio = indicator.pillThicknessRatio;   // 2
        indicator.width = indicator.naturalStripLength * 0.2;   // far below the floor's strip length
        tryVerify(() => Math.abs(indicator.dotSize - indicator.minDotSize) < 0.001, 2000,
                  "the effective dot clamps exactly at the legible floor");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "dot never shrinks past the floor");
        fuzzyCompare(indicator.pillSize, indicator.minDotSize * ratio, 0.01, "pill clamps at its proportional floor (minDotSize * ratio)");
        verify(indicator.pillSize >= indicator.minDotSize * ratio - 0.01, "pill never shrinks past its floor");
    }

    // multi-row: lines are sized independently (the documented trade-off). 5 desktops / 2 rows → [3, 2];
    // each line is its own reflow strip, so the capsule line is WIDER than the short trailing line (not
    // forced to a common column width). The strip's natural width is the wider line.
    function test_gridLinesSizedIndependently() {
        const indicator = makeIndicator(makeMock(fiveIds, fiveIds[0], [], 2));
        compare(indicator.perLine, 3, "3 per line");
        compare(indicator.lineCount, 2, "two lines");
        const dots = dotsByIndex(indicator);   // [0,1,2] line 0 (capsule at 0), [3,4] line 1
        const line0Width = dots[2].mapToItem(indicator, dots[2].width, 0).x - dots[0].mapToItem(indicator, 0, 0).x;
        const line1Width = dots[4].mapToItem(indicator, dots[4].width, 0).x - dots[3].mapToItem(indicator, 0, 0).x;
        verify(line0Width > line1Width + 0.5, "the capsule-bearing line is wider than the short trailing line");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalStripLength, 0.5, "the strip width is the wider (full) line");
    }

    // runtime form-factor flip (horizontal <-> vertical on a LIVE indicator): toggling `vertical` on a
    // running strip (a panel re-docked to a side edge) swaps the major/cross axes — the capsule's long axis
    // flips width->height and the Layout hints swap with it. Ample room (400x400) so sizes don't shrink.
    function test_runtimeFormFactorFlip() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 400, height: 400 });
        const cap = dotByUuid(indicator, currentUuid);
        fuzzyCompare(cap.width, indicator.pillWidth, 0.5, "horizontal: the capsule's long axis is width");
        fuzzyCompare(cap.height, indicator.pillSize, 0.5, "horizontal: the capsule's cross axis is the pill thickness");

        indicator.vertical = true;   // the widget's panel moved to a side edge

        tryVerify(function () {
            return Math.abs(cap.height - indicator.pillWidth) <= 0.5
                && Math.abs(cap.width - indicator.pillSize) <= 0.5;
        }, 2000, "after the flip the capsule's long axis becomes height; the cross axis becomes width");

        // The Layout hints swap with the orientation: the major axis is now the vertical one.
        compare(indicator.Layout.preferredHeight, indicator.implicitHeight, "major (height) preferred now pins the strip length");
        compare(indicator.Layout.maximumHeight, indicator.implicitHeight, "major (height) maximum pins the natural length");
        const maxW = indicator.Layout.maximumWidth;
        verify(maxW < 0 || maxW > indicator.implicitWidth, "cross (width) axis is now free to fill the panel thickness");
    }

    // reactive behaviour-flag toggling (enableScroll / invertScroll / scrollWrap): flip each on a running
    // indicator and assert the scroll behaviour changes mid-session (the index math is unit-tested).
}
