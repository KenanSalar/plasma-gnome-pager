/*
 * Plasma Gnome Pager — tst_indicator_morph.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Reflow / morph: dot↔capsule mapping, the active-element capsule invariants, switch/add/remove,
 * and the animate latch.
 * Derives from the shared IndicatorTestCase (tests/shared/) for the fixtures: the component
 * factory, the VirtualDesktopInfo doubles, the switchRequested spy, and the dot-tree locators.
 */
import "../shared"
import "../../package/contents/ui/logic.js" as Logic
import "../shared/elements.js" as Elements

IndicatorTestCase {
    id: morphCase
    name: "IndicatorMorph"

    // One dot per desktop UUID in the source.
    function test_dotCountMatchesDesktops() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator, "indicator created");
        compare(collectDots(indicator).length, ids.length);
    }

    // robustness.md: a null source (transient) must yield an empty strip, never an error or stray dot.
    function test_nullSourceProducesNoDots() {
        const indicator = makeIndicator(null);
        verify(indicator, "indicator created");
        compare(collectDots(indicator).length, 0);
    }

    // Exactly the dot whose UUID equals currentDesktop is active.
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

    // Clicking a dot must forward switchRequested(uuid) up to main.qml unchanged.
    function test_clickForwardsUuid() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        switchSpy.target = indicator;
        switchSpy.clear();

        // Pick an inactive dot (ids[0]) so a stale/no-op binding couldn't accidentally pass.
        const dots = collectDots(indicator);
        let target = null;
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === ids[0])
                target = dots[i];
        verify(target, "found the first dot");

        target.activated();   // signals are callable — emits without flaky headless mouse sim
        compare(switchSpy.count, 1, "switchRequested fired once");
        compare(switchSpy.signalArguments[0][0], ids[0], "forwarded the clicked UUID");
    }

    // The reflow capsule (the active element morphs to a pill)

    // activeIndex maps currentDesktop to its position in desktopIds.
    function test_activeIndexMapping() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.activeIndex, 1, "middle desktop (uuid-b) is index 1");
    }

    // The active element is the wide capsule (pillWidth); every inactive element is a dot.
    function test_activeElementIsCapsuleInactiveAreDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            const expected = (ids[i] === currentUuid) ? indicator.pillWidth : indicator.dotSize;
            fuzzyCompare(dot.width, expected, 0.5, "width of " + ids[i]);
        }
    }

    // Exactly one element is the capsule; the rest are dots.
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

    // robustness.md: a null source yields no elements, and the cell falls back to one dot wide (not 0).
    function test_nullSourceNoCapsule() {
        const indicator = makeIndicator(null);
        compare(indicator.activeIndex, -1, "no active index without a source");
        compare(collectDots(indicator).length, 0, "no elements");
        fuzzyCompare(indicator.implicitWidth, indicator.dotSize, 0.5, "cell falls back to one dot wide");
    }

    // robustness.md: currentDesktop not (yet) in desktopIds → no capsule, and the advertised width stays
    // at the steady-state value so the panel cell does NOT jitter while the active element is unknown.
    function test_transientStaleNoCapsuleWidthStable() {
        const indicator = makeIndicator(makeMock(ids, staleUuid));
        compare(indicator.activeIndex, -1, "stale currentDesktop maps to -1");
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            fuzzyCompare(dots[i].width, indicator.dotSize, 0.5, "no capsule while stale: " + dots[i].modelData);
        const steady = Logic.lineExtent(ids.length, indicator.dotSize, indicator.dotSpacing, indicator.pillWidth);
        fuzzyCompare(indicator.implicitWidth, steady, 0.5, "cell stays at the steady-state width");
    }

    // Uniform spacing: the gap between EVERY adjacent pair (dot-dot and capsule-dot) equals the Row
    // spacing (the GNOME look; positive gaps also prove no overlap).
    function test_uniformSpacing() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));   // middle is the capsule
        const dots = dotsByIndex(indicator);
        for (let i = 0; i < dots.length - 1; i++) {
            const rightEdge = dots[i].mapToItem(indicator, dots[i].width, 0).x;
            const nextLeft = dots[i + 1].mapToItem(indicator, 0, 0).x;
            fuzzyCompare(nextLeft - rightEdge, indicator.dotSpacing, 0.5, "uniform gap after element " + i);
        }
    }

    // Reactivity: the "bind, don't cache" contract. The indicator reads desktop state live, so a change
    // by ANY means (modelled by mutating the mock) must update the UI — these fail if a binding is cached.

    // Switching the current desktop moves the `active` flag to the new dot (and only it).
    function test_switchUpdatesActiveDot() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        verify(dotByUuid(indicator, ids[0]).active, "first dot active initially");
        verify(!dotByUuid(indicator, ids[2]).active, "third dot inactive initially");

        vdi.currentDesktop = ids[2];   // e.g. a keyboard switch reported by VirtualDesktopInfo

        compare(dotByUuid(indicator, ids[0]).active, false, "old dot deactivates");
        compare(dotByUuid(indicator, ids[2]).active, true, "new dot activates");
    }

    // Switching morphs the capsule: the new current grows to pillWidth, the old shrinks to dotSize.
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

    // Adding a desktop (desktopIds grows) adds a dot reactively; the current index is kept.
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

    // Removing a desktop drops a dot; the capsule re-tracks the still-current desktop at its new index.
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

    // Plasma 6.7: per-screen current desktop. Each output can show a different current; the indicator
    // resolves the current FOR ITS screen (currentDesktopByScreenName, falling back to global). These
    // prove the active dot reflects this screen, another screen's switch doesn't move this pill, and this
    // screen's own switch is reactive.

    // Created with a valid current desktop: the latch is already set (Component.onCompleted).
    function test_animateLatchedOnValidStart() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.animate, true, "morph latched on a valid initial placement");
    }

    // No active element, then a source arrives: the latch enables via the onActiveIndexChanged +
    // Qt.callLater deferral (first placement still instant).
    function test_animateDefersFromInvalidStart() {
        const indicator = makeIndicator(null);   // no source → activeIndex -1
        compare(indicator.animate, false, "morph disabled while there is no active element");

        indicator.virtualDesktopInfo = makeMock(ids, currentUuid);   // source populates a frame later
        tryCompare(indicator, "animate", true, 2000, "morph enables once a valid element first appears");
    }

    // Once latched true, a transient loss of the active element must NOT reset the latch to false.
    function test_animateIsOneWayLatch() {
        const vdi = makeMock(ids, currentUuid);
        const indicator = makeIndicator(vdi);
        compare(indicator.animate, true, "latched true at start");

        vdi.currentDesktop = staleUuid;   // current momentarily not in ids
        compare(indicator.activeIndex, -1, "no active element now");
        wait(0);
        compare(indicator.animate, true, "animate never returns to false");
    }

    // First placement is instant: created at the LAST desktop, that element is a capsule on frame 0.
    function test_firstPlacementIsImmediate() {
        const indicator = makeIndicator(makeMock(ids, ids[2]));
        fuzzyCompare(dotByUuid(indicator, ids[2]).width, indicator.pillWidth, 0.5,
                     "active element is already a capsule on first placement");
    }

    // activeIndex edge cases (data-driven): -1 for every transient/invalid state, the element index otherwise.
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

    // geometry edge cases

    // The advertised width holds the whole strip, so the end elements never clip past the edges.
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

    // A single desktop: one element, active, rendered as the capsule; the cell is one pill wide.
    function test_singleDesktop() {
        const indicator = makeIndicator(makeMock(["uuid-solo"], "uuid-solo"));
        compare(collectDots(indicator).length, 1, "exactly one element");
        compare(indicator.activeIndex, 0, "the only desktop is active");
        fuzzyCompare(dotByUuid(indicator, "uuid-solo").width, indicator.pillWidth, 0.5, "the sole element is the capsule");
        fuzzyCompare(indicator.implicitWidth, indicator.pillWidth, 0.5, "cell is one capsule wide");
    }

    // Clicking the active capsule raises activeClicked (the pill-click action), NOT a switch — and the
    // whole capsule is the hit area. Real synthesized click (the e2e variant of the input-suite signal test).
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

    // scroll-to-switch: the indicator forwards a wheel step as switchRequested(uuid); the index math is
    // unit-tested in tst_logic, so here we assert the wiring (direction, enable/wrap flags, clamped no-ops,
    // sub-notch accumulation). Wheel DOWN → next desktop; wheel UP → previous.

    // The animate latch gates each dot's morph: the latch + configured duration resolve into each dot's
    // morphEnabled (animate && effectiveDuration > 0). Wiring check.
    function test_morphGateFlowsThroughToDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { animationDuration: 200 });
        compare(indicator.animate, true, "latch is on for a valid initial placement");
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            compare(dots[i].morphEnabled, indicator.animate && dots[i].effectiveDuration > 0,
                    "dot " + i + " morph gate matches latch && duration");
    }

    // robustness.md: an empty desktopIds ARRAY (vs a null source) must yield no dots and a one-dot cell.
    function test_emptyDesktopIdsArrayProducesNoDots() {
        const indicator = makeIndicator(makeMock([], ""));
        compare(collectDots(indicator).length, 0, "an empty desktopIds array yields no dots");
        compare(indicator.activeIndex, -1, "no active index for an empty set");
        fuzzyCompare(indicator.naturalStripLength, indicator.naturalDotSize, 0.5, "strip length holds one dot, not 0");
        fuzzyCompare(indicator.implicitWidth, indicator.naturalDotSize, 0.5, "the cell stays one dot wide");
        verify(isFinite(indicator.dotSize) && indicator.dotSize > 0, "effective dot size stays finite/positive (no NaN)");
    }

    // Many desktops on a single line: every dot renders and the natural strip grows linearly.
    function test_manyDesktopsRenderAllDots() {
        const big = manyIds(20);
        const indicator = makeIndicator(makeMock(big, big[0]));
        compare(collectDots(indicator).length, 20, "all 20 dots render");
        compare(indicator.activeIndex, 0, "the first desktop is active");
        const nd = indicator.naturalDotSize;
        const expected = Logic.lineExtent(20, nd, nd * indicator.spacingFactor, nd * indicator.pillWidthFactor);
        fuzzyCompare(indicator.naturalStripLength, expected, 0.5, "natural strip length matches the formula for 20 desktops");
    }

    // Rapid back-to-back switches (a burst fired mid-morph) must converge to one capsule on the final
    // target and never throw (the one-way latch + idempotent recompute settle deterministically).
    function test_rapidSwitchingConvergesToOneCapsule() {
        const indicator = makeIndicator(makeMock(fiveIds, fiveIds[0]), { animationDuration: 200 });
        const vdi = indicator.virtualDesktopInfo;
        for (let n = 0; n < 12; n++)
            vdi.currentDesktop = fiveIds[n % fiveIds.length];   // storm of changes, no settle between
        vdi.currentDesktop = fiveIds[3];                        // final target
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

    // scale-to-fit: the floor clamp and the no-scale-up guarantee. These pin the two ends of
    // `dotSize = max(minDotSize, min(naturalDotSize, fitDotSize))`.

    // The advertised width is a position-independent FORMULA (a switch trades one growing element for a
    // shrinking one), so it must NOT change across a switch — the panel cell never jitters.
    function test_implicitWidthConservedAcrossSwitch() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        const before = indicator.implicitWidth;
        verify(before > 0, "has a positive content width");

        vdi.currentDesktop = ids[2];   // move the capsule to the far end
        tryCompare(indicator, "activeIndex", 2, 2000, "the switch registered");
        fuzzyCompare(indicator.implicitWidth, before, 0.5, "advertised width is conserved across the switch");
    }

    // Multi-row "breathing" fix, observed DURING the morph: a cross-row switch animates the capsule from line 0
    // to line 1; a non-morphing dot in the gaining line must hold its position the whole time. Reference dot[3]
    // is the leftmost of line 1 — never a capsule here (current goes 0 → 5) and left of the growing dot[5], so it
    // never reflows; its only possible motion source is the strip resizing+recentering. Before the fix the strip
    // dips by Δ/2 at the morph midpoint and the dot drifts ~Δ/4; after the fix the pinned strip never moves.
    function test_crossRowMorphDoesNotDriftOtherDots() {
        const vdi = makeMock(sixIds, sixIds[0], [], 2);   // 2 rows → lines [0,1,2],[3,4,5]
        const indicator = makeIndicator(vdi, { animationDuration: 600, width: 400, height: 200, dotSizeRequest: 16, pillWidthFactor: 4 });
        const ref = dotsByIndex(indicator)[3];            // leftmost of line 1 (cached; not destroyed by the switch)
        const before = ref.mapToItem(indicator, 0, 0).x;

        vdi.currentDesktop = sixIds[5];                   // cross-row switch: capsule line 0 → line 1
        let maxDrift = 0;
        for (let i = 0; i < 8; i++) {                     // sample ~400ms of the 600ms morph, incl. the f≈0.5 dip
            wait(50);
            maxDrift = Math.max(maxDrift, Math.abs(ref.mapToItem(indicator, 0, 0).x - before));
        }
        verify(maxDrift <= 0.75, "a non-morphing dot stays put during a cross-row morph (max drift " + maxDrift.toFixed(2) + " px)");
    }

    // robustness.md: a populated → empty → populated round-trip. No dots while empty, the size stays
    // finite, the one-way latch survives, and exactly one capsule returns on repopulation.
    function test_transientEmptyIdsThenRepopulate() {
        const vdi = makeMock(ids, currentUuid);
        const indicator = makeIndicator(vdi);
        compare(collectDots(indicator).length, 3, "three dots at start");
        compare(indicator.animate, true, "latched at a valid start");

        vdi.desktopIds = [];   // transient empty frame
        compare(collectDots(indicator).length, 0, "no dots while ids are empty");
        verify(isFinite(indicator.dotSize) && indicator.dotSize > 0, "dot size stays finite/positive on the empty frame");
        compare(indicator.animate, true, "the one-way latch survives the empty frame");

        vdi.desktopIds = ids;   // ids come back
        tryVerify(() => collectDots(indicator).length === 3, 2000, "dots return when ids repopulate");
        tryVerify(() => Elements.countCapsules(collectDots(indicator), indicator.pillWidth) === 1,
                  2000, "exactly one capsule after repopulation");
    }
}
