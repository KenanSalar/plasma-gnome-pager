/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A built WorkspaceIndicator on VdiMock, driven by real wheel and click events: what a scroll or a
 * click asks for, and the scroll settings changing at runtime.
 */
import "../shared"
import "../shared/elements.mjs" as Elements

IndicatorTestCase {
    id: inputCase
    name: "IndicatorInput"

    function test_scrollDownStepsNext() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);
        compare(switchSpy.count, 1, "one switch on a full notch down");
        compare(switchSpy.signalArguments[0][0], ids[1], "scroll down moves to the next desktop");
    }

    function test_scrollUpStepsPrevious() {
        const indicator = makeIndicator(makeMock(ids, ids[1]), { enableScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(120);
        compare(switchSpy.count, 1, "one switch on a full notch up");
        compare(switchSpy.signalArguments[0][0], ids[0], "scroll up moves to the previous desktop");
    }

    function test_invertScrollDownStepsPrevious() {
        const indicator = makeIndicator(makeMock(ids, ids[1]), { enableScroll: true, invertScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);
        compare(switchSpy.count, 1, "one switch on a full notch down");
        compare(switchSpy.signalArguments[0][0], ids[0], "inverted scroll down moves to the previous desktop");
    }

    function test_invertScrollUpStepsNext() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true, invertScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(120);
        compare(switchSpy.count, 1, "one switch on a full notch up");
        compare(switchSpy.signalArguments[0][0], ids[1], "inverted scroll up moves to the next desktop");
    }

    function test_scrollClampAtStartIsNoOp() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true, scrollWrap: false });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(120);   // up from the first desktop, no wrap
        compare(switchSpy.count, 0, "scrolling past the start without wrap is a no-op");
    }

    function test_scrollClampAtEndIsNoOp() {
        const indicator = makeIndicator(makeMock(ids, ids[2]), { enableScroll: true, scrollWrap: false });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);   // down from the last desktop, no wrap
        compare(switchSpy.count, 0, "scrolling past the end without wrap is a no-op");
    }

    function test_scrollWrapForwardAtEnd() {
        const indicator = makeIndicator(makeMock(ids, ids[2]), { enableScroll: true, scrollWrap: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);   // down from the last desktop, wrapping
        compare(switchSpy.count, 1, "wrap produces a switch at the end");
        compare(switchSpy.signalArguments[0][0], ids[0], "wraps forward to the first desktop");
    }

    function test_scrollWrapBackwardAtStart() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true, scrollWrap: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(120);   // up from the first desktop, wrapping
        compare(switchSpy.count, 1, "wrap produces a switch at the start");
        compare(switchSpy.signalArguments[0][0], ids[2], "wraps backward to the last desktop");
    }

    function test_scrollDisabledIsNoOp() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: false });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);
        compare(switchSpy.count, 0, "no switching when enableScroll is false");
    }

    // A touchpad reports deltas smaller than a notch.
    function test_scrollAccumulatesSubNotch() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-60);
        compare(switchSpy.count, 0, "half a notch does not switch yet");
        indicator.handleWheel(-60);
        compare(switchSpy.count, 1, "the second half completes a notch and switches");
        compare(switchSpy.signalArguments[0][0], ids[1], "accumulated notch moves to the next desktop");
    }

    // Real events, as the routing behind the dots is what broke in the shell while the handler worked.
    function test_wheelEventStepsNext() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true, width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);   // wheel down over the strip
        compare(switchSpy.count, 1, "a real wheel event switches");
        compare(switchSpy.signalArguments[0][0], ids[1], "wheel down moves to the next desktop");
    }

    function test_wheelEventInvertedStepsPrevious() {
        const indicator = makeIndicator(makeMock(ids, ids[1]), { enableScroll: true, invertScroll: true, width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);   // wheel down over the strip
        compare(switchSpy.count, 1, "a real wheel event switches when inverted");
        compare(switchSpy.signalArguments[0][0], ids[0], "inverted wheel down moves to the previous desktop");
    }

    function test_wheelEventDisabledIsNoOp() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: false, width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);
        compare(switchSpy.count, 0, "a real wheel event does nothing when scroll is disabled");
    }

    // Without wrap: wrapping from the stale first position landed on the same desktop and hid the defect.
    function test_wheelStepsThroughReorderedDesktops() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi, { enableScroll: true, scrollWrap: false, width: 200, height: 50 });
        vdi.reorder([ids[1], ids[2], ids[0]]);
        switchSpy.target = indicator;
        switchSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, 120);   // wheel up

        compare(switchSpy.count, 1, "wheel-up from the moved desktop switches");
        compare(switchSpy.signalArguments[0][0], ids[2], "it targets KWin's previous desktop, not the stale one");
    }

    function test_clickActiveDotEmitsActiveClicked() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        switchSpy.target = indicator;
        switchSpy.clear();
        activeSpy.target = indicator;
        activeSpy.clear();

        dotByUuid(indicator, currentUuid).activated();   // press the current desktop's pill
        compare(activeSpy.count, 1, "clicking the active pill raises activeClicked");
        compare(switchSpy.count, 0, "and does NOT emit a switch");
    }

    function test_clickInactiveDotEmitsSwitchRequested() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        switchSpy.target = indicator;
        switchSpy.clear();
        activeSpy.target = indicator;
        activeSpy.clear();

        dotByUuid(indicator, ids[0]).activated();   // ids[0] is inactive (current is ids[1])
        compare(switchSpy.count, 1, "clicking an inactive dot switches");
        compare(switchSpy.signalArguments[0][0], ids[0], "with that dot's UUID");
        compare(activeSpy.count, 0, "and does NOT fire the pill action");
    }

    // A scroll on a single wrapping desktop steps onto the current one, which a click would treat as the pill.
    function test_scrollNeverEmitsActiveClicked() {
        const single = makeIndicator(makeMock([ids[0]], ids[0]), { enableScroll: true, scrollWrap: true });
        switchSpy.target = single;
        switchSpy.clear();
        activeSpy.target = single;
        activeSpy.clear();

        single.handleWheel(-120);   // one desktop with wrap: the step lands back on it
        compare(activeSpy.count, 0, "wrap on a single desktop never fires the pill action");
        compare(switchSpy.count, 0, "and emits no switch either");
    }

    function test_clickBackgroundEmitsActiveClicked() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();
        activeSpy.target = indicator;
        activeSpy.clear();

        mouseClick(indicator, 5, indicator.height / 2);   // dot-free: the strip is centred and far narrower
        compare(activeSpy.count, 1, "clicking the background raises the pill action");
        compare(switchSpy.count, 0, "and never switches desktop");
    }

    function test_clickBackgroundIgnoredWhenDisabled() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50, pillClickAnywhere: false });
        activeSpy.target = indicator;
        activeSpy.clear();

        mouseClick(indicator, 5, indicator.height / 2);
        compare(activeSpy.count, 0, "the background is inert when the toggle is off");
    }

    function test_clickAnywhereDoesNotBlockDotClicks() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();
        activeSpy.target = indicator;
        activeSpy.clear();

        const c = Elements.centerOf(dotByUuid(indicator, ids[0]), indicator);
        mouseClick(indicator, c.x, c.y);
        compare(switchSpy.count, 1, "an inactive dot still switches");
        compare(switchSpy.signalArguments[0][0], ids[0], "with its own UUID");
        compare(activeSpy.count, 0, "the background action does not also fire");
    }

    function test_scrollStillWorksWithClickAreaEnabled() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true, width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();
        activeSpy.target = indicator;
        activeSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);
        compare(switchSpy.count, 1, "the wheel still switches with the click target enabled");
        compare(activeSpy.count, 0, "and scrolling never fires the pill action");
    }

    function test_wheelLayerDoesNotBlockClicks() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        const dot = dotByUuid(indicator, ids[0]);
        const c = Elements.centerOf(dot, indicator);
        mouseClick(indicator, c.x, c.y);
        compare(switchSpy.count, 1, "clicking a dot still works with the wheel layer present");
        compare(switchSpy.signalArguments[0][0], ids[0], "the clicked dot's UUID is forwarded");
    }

    // The current desktop missing from the list, as during an add or remove.
    function test_scrollWhileStaleIsNoOp() {
        const indicator = makeIndicator(makeMock(ids, staleUuid), { enableScroll: true, width: 200, height: 50 });
        compare(indicator.activeIndex, -1, "stale current → no active element");
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);
        compare(switchSpy.count, 0, "handler scroll is a no-op with no active element");

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);
        compare(switchSpy.count, 0, "a real wheel event is a no-op too");
    }

    // A dropped remainder would never complete the second notch.
    function test_wheelAccumulatorCarriesNegativeRemainder() {
        const indicator = makeIndicator(makeMock(ids, ids[1]), { enableScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-200);
        compare(switchSpy.count, 1, "one notch out of -200");
        compare(switchSpy.signalArguments[0][0], ids[2], "first step moves to the next desktop");
        fuzzyCompare(indicator.wheelAccumulator, -80, 0.001, "the -80 remainder is carried, not dropped");

        indicator.handleWheel(-40);   // -80 + -40 = -120 → exactly one more notch
        compare(switchSpy.count, 2, "the carried remainder completes a second notch");
    }

    function test_wheelPositiveRemainderCarry() {
        const indicator = makeIndicator(makeMock(ids, ids[2]), { enableScroll: true });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(200);
        compare(switchSpy.count, 1, "one notch out of +200");
        compare(switchSpy.signalArguments[0][0], ids[1], "wheel up steps to the previous desktop");
        fuzzyCompare(indicator.wheelAccumulator, 80, 0.001, "the +80 remainder is carried, not dropped");

        indicator.handleWheel(40);   // +80 + +40 = +120 → one more notch
        compare(switchSpy.count, 2, "the carried remainder completes a second notch");
    }

    function test_enableScrollToggledLive() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: false });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);
        compare(switchSpy.count, 0, "no switch while scrolling is disabled");

        indicator.enableScroll = true;
        indicator.handleWheel(-120);
        compare(switchSpy.count, 1, "enabling scroll at runtime makes the wheel step");
        compare(switchSpy.signalArguments[0][0], ids[1], "and it steps to the next desktop");

        indicator.enableScroll = false;
        indicator.handleWheel(-120);
        compare(switchSpy.count, 1, "disabling scroll again stops further steps");
    }

    function test_invertScrollToggledLive() {
        // The mock's current never moves, so both steps start from the middle.
        const indicator = makeIndicator(makeMock(ids, ids[1]), { enableScroll: true, invertScroll: false });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);   // default: wheel down → next
        compare(switchSpy.signalArguments[0][0], ids[2], "default mapping: scroll down → next desktop");

        indicator.invertScroll = true;
        switchSpy.clear();
        indicator.handleWheel(-120);   // inverted: wheel down → previous
        compare(switchSpy.signalArguments[0][0], ids[0], "after enabling invert at runtime, scroll down → previous");
    }

    function test_scrollWrapToggledLive() {
        const indicator = makeIndicator(makeMock(ids, ids[2]), { enableScroll: true, scrollWrap: false });
        switchSpy.target = indicator;
        switchSpy.clear();

        indicator.handleWheel(-120);   // down from the last desktop, no wrap → no-op
        compare(switchSpy.count, 0, "no wrap: scrolling past the end is a no-op");

        indicator.scrollWrap = true;
        indicator.handleWheel(-120);   // down from the last desktop, wrapping → first
        compare(switchSpy.count, 1, "enabling wrap at runtime wraps past the end");
        compare(switchSpy.signalArguments[0][0], ids[0], "and it wraps to the first desktop");
    }
}
