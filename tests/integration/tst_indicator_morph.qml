/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A built WorkspaceIndicator on VdiMock: which dot is the pill as the desktops change by any means,
 * and the morph between them.
 */
import "../shared"
import "../../package/contents/ui/logic.mjs" as Logic
import "../shared/elements.mjs" as Elements

IndicatorTestCase {
    id: morphCase
    name: "IndicatorMorph"

    function test_dotCountMatchesDesktops() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator, "indicator created");
        compare(collectDots(indicator).length, ids.length);
    }

    function test_nullSourceProducesNoDots() {
        const indicator = makeIndicator(null);
        verify(indicator, "indicator created");
        compare(collectDots(indicator).length, 0);
    }

    function test_activeMapping() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        const dots = collectDots(indicator);
        let activeCount = 0;
        for (let i = 0; i < dots.length; i++) {
            compare(dots[i].active, dots[i].modelData === currentUuid, "active flag matches currentDesktop for " + dots[i].modelData);
            if (dots[i].active)
                activeCount++;
        }
        compare(activeCount, 1, "exactly one dot is active");
    }

    function test_clickForwardsUuid() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        switchSpy.target = indicator;
        switchSpy.clear();

        // An inactive dot, so a binding that never updates can't pass by accident.
        const dots = collectDots(indicator);
        let target = null;
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === ids[0])
                target = dots[i];
        verify(target, "found the first dot");

        target.activated();
        compare(switchSpy.count, 1, "switchRequested fired once");
        compare(switchSpy.signalArguments[0][0], ids[0], "forwarded the clicked UUID");
    }

    function test_activeIndexMapping() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.activeIndex, 1, "middle desktop (uuid-b) is index 1");
    }

    function test_activeElementIsCapsuleInactiveAreDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            const expected = (ids[i] === currentUuid) ? indicator.pillWidth : indicator.dotSize;
            fuzzyCompare(dot.width, expected, 0.5, "width of " + ids[i]);
        }
    }

    function test_exactlyOneCapsule() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        const dots = collectDots(indicator);
        const capsules = Elements.countCapsules(dots, indicator.pillWidth);
        let plain = 0;
        for (let i = 0; i < dots.length; i++) {
            if (Math.abs(dots[i].width - indicator.dotSize) <= 0.5)
                plain++;
        }
        compare(capsules, 1, "exactly one capsule");
        compare(plain, ids.length - 1, "all other elements are dots");
    }

    // A cell of width 0 would vanish from the panel.
    function test_nullSourceNoCapsule() {
        const indicator = makeIndicator(null);
        compare(indicator.activeIndex, -1, "no active index without a source");
        compare(collectDots(indicator).length, 0, "no elements");
        fuzzyCompare(indicator.implicitWidth, indicator.dotSize + 2 * indicator.hoverPadding, 0.5, "cell falls back to one dot wide");
    }

    // The current desktop missing from the list, as during an add or remove; the cell mustn't jump.
    function test_transientStaleNoCapsuleWidthStable() {
        const indicator = makeIndicator(makeMock(ids, staleUuid));
        compare(indicator.activeIndex, -1, "stale currentDesktop maps to -1");
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            fuzzyCompare(dots[i].width, indicator.dotSize, 0.5, "no capsule while stale: " + dots[i].modelData);
        const steady = Logic.lineExtent(ids.length, indicator.dotSize, indicator.dotSpacing, indicator.pillWidth);
        fuzzyCompare(indicator.implicitWidth, steady + 2 * indicator.hoverPadding, 0.5, "cell stays at the steady-state width");
    }

    function test_uniformSpacing() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));   // middle is the capsule
        const dots = dotsByIndex(indicator);
        for (let i = 0; i < dots.length - 1; i++) {
            const rightEdge = dots[i].mapToItem(indicator, dots[i].width, 0).x;
            const nextLeft = dots[i + 1].mapToItem(indicator, 0, 0).x;
            fuzzyCompare(nextLeft - rightEdge, indicator.dotSpacing, 0.5, "uniform gap after element " + i);
        }
    }

    // A change made outside the widget, by keyboard or another pager, arrives as the mock changing.

    function test_switchUpdatesActiveDot() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        verify(dotByUuid(indicator, ids[0]).active, "first dot active initially");
        verify(!dotByUuid(indicator, ids[2]).active, "third dot inactive initially");

        vdi.currentDesktop = ids[2];

        compare(dotByUuid(indicator, ids[0]).active, false, "old dot deactivates");
        compare(dotByUuid(indicator, ids[2]).active, true, "new dot activates");
    }

    function test_morphOnSwitch() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        verify(Elements.isCapsule(dotByUuid(indicator, ids[0]), indicator.pillWidth), "ids[0] starts as the capsule");

        vdi.currentDesktop = ids[2];

        tryVerify(function () {
            return Elements.isCapsule(dotByUuid(indicator, ids[2]), indicator.pillWidth)
                && Math.abs(dotByUuid(indicator, ids[0]).width - indicator.dotSize) <= 0.5;
        }, 2000, "capsule morphs onto the newly current element; the old shrinks to a dot");
    }

    function test_addDesktopAddsDot() {
        const vdi = makeMock([ids[0], ids[1]], ids[0]);
        const indicator = makeIndicator(vdi);
        compare(collectDots(indicator).length, 2, "two dots initially");

        vdi.desktopIds = [ids[0], ids[1], ids[2]];   // a desktop was appended

        tryVerify(function () {
            return collectDots(indicator).length === 3;
        }, 2000, "a third dot appears");
        compare(indicator.activeIndex, 0, "current desktop's index is unchanged by an append");
    }

    function test_removeDesktopRemovesDot() {
        const vdi = makeMock(ids, ids[2]);   // current is the last desktop
        const indicator = makeIndicator(vdi);
        compare(collectDots(indicator).length, 3, "three dots initially");

        vdi.desktopIds = [ids[1], ids[2]];   // the first desktop was removed; current survives

        tryVerify(function () {
            return collectDots(indicator).length === 2;
        }, 2000, "a dot is removed");
        compare(indicator.activeIndex, 1, "the surviving current desktop is re-found at its new index");
        tryVerify(function () {
            return Elements.isCapsule(dotByUuid(indicator, ids[2]), indicator.pillWidth);
        }, 2000, "the surviving current desktop is the capsule");
    }

    function test_animateLatchedOnValidStart() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.animate, true, "morph latched on a valid initial placement");
    }

    function test_animateDefersFromInvalidStart() {
        const indicator = makeIndicator(null);
        compare(indicator.animate, false, "morph disabled while there is no active element");

        indicator.virtualDesktopInfo = makeMock(ids, currentUuid);   // as if a frame late
        tryCompare(indicator, "animate", true, 2000, "morph enables once a valid element first appears");
    }

    function test_animateIsOneWayLatch() {
        const vdi = makeMock(ids, currentUuid);
        const indicator = makeIndicator(vdi);
        compare(indicator.animate, true, "latched true at start");

        vdi.currentDesktop = staleUuid;   // current momentarily not in ids
        compare(indicator.activeIndex, -1, "no active element now");
        wait(0);
        compare(indicator.animate, true, "animate never returns to false");
    }

    function test_firstPlacementIsImmediate() {
        const indicator = makeIndicator(makeMock(ids, ids[2]));
        fuzzyCompare(dotByUuid(indicator, ids[2]).width, indicator.pillWidth, 0.5,
                     "active element is already a capsule on first placement");
    }

    function test_activeIndex_data() {
        return [
            { tag: "empty-ids", desktops: [], current: "uuid-x", expected: -1 },
            { tag: "empty-current", desktops: ids, current: "", expected: -1 },
            { tag: "first", desktops: ids, current: ids[0], expected: 0 },
            { tag: "last", desktops: ids, current: ids[2], expected: 2 }
        ];
    }

    function test_activeIndex(data) {
        const indicator = makeIndicator(makeMock(data.desktops, data.current));
        compare(indicator.activeIndex, data.expected, data.tag);
    }

    // geometry
    function test_noClipAtEnds() {
        const many = [ids[0], ids[1], ids[2], "uuid-d", "uuid-e", "uuid-f"];

        const atFirst = makeIndicator(makeMock(many, many[0]));
        const firstDots = dotsByIndex(atFirst);
        const firstLeft = firstDots[0].mapToItem(atFirst, 0, 0).x;
        verify(firstLeft >= -0.5, "first element does not clip past the left edge");

        const atLast = makeIndicator(makeMock(many, many[many.length - 1]));
        const lastDots = dotsByIndex(atLast);
        const last = lastDots[lastDots.length - 1];
        const lastRight = last.mapToItem(atLast, last.width, 0).x;
        verify(lastRight <= atLast.width + 0.5, "last element does not clip past the right edge");
    }

    function test_singleDesktop() {
        const indicator = makeIndicator(makeMock(["uuid-solo"], "uuid-solo"));
        compare(collectDots(indicator).length, 1, "exactly one element");
        compare(indicator.activeIndex, 0, "the only desktop is active");
        fuzzyCompare(dotByUuid(indicator, "uuid-solo").width, indicator.pillWidth, 0.5, "the sole element is the capsule");
        fuzzyCompare(indicator.implicitWidth, indicator.pillWidth + 2 * indicator.hoverPadding, 0.5, "cell is one capsule wide");
    }

    // A real click this time, which also proves the whole pill takes it.
    function test_clickActiveCapsuleEmitsActiveClicked() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();
        activeSpy.target = indicator;
        activeSpy.clear();

        const capsule = dotByUuid(indicator, currentUuid);
        const p = Elements.centerOf(capsule, indicator);
        mouseClick(indicator, p.x, p.y);

        compare(activeSpy.count, 1, "clicking the active capsule raises the pill-click action");
        compare(switchSpy.count, 0, "and does NOT switch (you are already on it)");
    }

    function test_morphGateFlowsThroughToDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { animationDuration: 200 });
        compare(indicator.animate, true, "latch is on for a valid initial placement");
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            compare(dots[i].morphEnabled, indicator.animate && dots[i].effectiveDuration > 0,
                    "dot " + i + " morph gate matches latch && duration");
    }

    // An empty list rather than a missing source.
    function test_emptyDesktopIdsArrayProducesNoDots() {
        const indicator = makeIndicator(makeMock([], ""));
        compare(collectDots(indicator).length, 0, "an empty desktopIds array yields no dots");
        compare(indicator.activeIndex, -1, "no active index for an empty set");
        fuzzyCompare(indicator.naturalStripLength, indicator.naturalDotSize, 0.5, "strip length holds one dot, not 0");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalDotSize + 2 * indicator.hoverPadding, 0.5, "the cell stays one dot wide");
        verify(isFinite(indicator.dotSize) && indicator.dotSize > 0, "effective dot size stays finite/positive (no NaN)");
    }

    function test_manyDesktopsRenderAllDots() {
        const big = manyIds(20);
        const indicator = makeIndicator(makeMock(big, big[0]));
        compare(collectDots(indicator).length, 20, "all 20 dots render");
        compare(indicator.activeIndex, 0, "the first desktop is active");
        const nd = indicator.naturalDotSize;
        const expected = Logic.lineExtent(20, nd, nd * indicator.spacingFactor, nd * indicator.pillWidthFactor);
        fuzzyCompare(indicator.naturalStripLength, expected, 0.5, "natural strip length matches the formula for 20 desktops");
    }

    function test_rapidSwitchingConvergesToOneCapsule() {
        const indicator = makeIndicator(makeMock(fiveIds, fiveIds[0]), { animationDuration: 200 });
        const vdi = indicator.virtualDesktopInfo;
        for (let n = 0; n < 12; n++)
            vdi.currentDesktop = fiveIds[n % fiveIds.length];   // no time to settle in between
        vdi.currentDesktop = fiveIds[3];
        tryCompare(indicator, "activeIndex", 3, 2000, "activeIndex converges to the final target");
        tryVerify(() => {
            const dots = collectDots(indicator);
            let caps = 0;
            for (let i = 0; i < dots.length; i++)
                if (dots[i].active)
                    caps++;
            return caps === 1;
        }, 2000, "exactly one capsule after the burst");
        tryVerify(() => Elements.isCapsule(dotByUuid(indicator, fiveIds[3]), indicator.pillWidth),
                  2000, "the final desktop morphs to the capsule width");
    }

    // The panel cell mustn't jump on a switch.
    function test_implicitWidthConservedAcrossSwitch() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        const before = indicator.implicitWidth;
        verify(before > 0, "has a positive content width");

        vdi.currentDesktop = ids[2];
        tryCompare(indicator, "activeIndex", 2, 2000, "the switch registered");
        fuzzyCompare(indicator.implicitWidth, before, 0.5, "advertised width is conserved across the switch");
    }

    // A strip sized by its content shrank halfway through a switch between rows and dragged every dot as
    // it re-centred. Dot 3 never morphs and sits left of the growing dot 5, so only the strip can move it.
    function test_crossRowMorphDoesNotDriftOtherDots() {
        const vdi = makeMock(sixIds, sixIds[0], [], 2);   // 2 rows → lines [0,1,2],[3,4,5]
        const indicator = makeIndicator(vdi, { animationDuration: 600, width: 400, height: 200, dotSizeRequest: 16, pillWidthFactor: 4 });
        const ref = dotsByIndex(indicator)[3];            // a switch doesn't destroy it, so it can be held
        const before = ref.mapToItem(indicator, 0, 0).x;

        vdi.currentDesktop = sixIds[5];
        let maxDrift = 0;
        for (let i = 0; i < 8; i++) {                     // through the middle of the morph, where the dip was
            wait(50);
            maxDrift = Math.max(maxDrift, Math.abs(ref.mapToItem(indicator, 0, 0).x - before));
        }
        verify(maxDrift <= 0.75, "a non-morphing dot stays put during a cross-row morph (max drift " + maxDrift.toFixed(2) + " px)");
    }

    function test_transientEmptyIdsThenRepopulate() {
        const vdi = makeMock(ids, currentUuid);
        const indicator = makeIndicator(vdi);
        compare(collectDots(indicator).length, 3, "three dots at start");
        compare(indicator.animate, true, "latched at a valid start");

        vdi.desktopIds = [];
        compare(collectDots(indicator).length, 0, "no dots while ids are empty");
        verify(isFinite(indicator.dotSize) && indicator.dotSize > 0, "dot size stays finite/positive on the empty frame");
        compare(indicator.animate, true, "the one-way latch survives the empty frame");

        vdi.desktopIds = ids;
        tryVerify(() => collectDots(indicator).length === 3, 2000, "dots return when ids repopulate");
        tryVerify(() => Elements.countCapsules(collectDots(indicator), indicator.pillWidth) === 1,
                  2000, "exactly one capsule after repopulation");
    }
}
