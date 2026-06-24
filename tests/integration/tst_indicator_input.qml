/*
 * Plasma Gnome Pager — tst_indicator_input.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Input: scroll/wheel switching (handleWheel + real mouseWheel), the wheel accumulator, and the
 * live scroll-setting toggles.
 * Derives from the shared IndicatorTestCase (tests/shared/) for the fixtures: the component
 * factory, the VirtualDesktopInfo doubles, the switchRequested spy, and the dot-tree locators.
 */
import "../shared"
import "../shared/elements.js" as Elements

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

    // invertScroll flips the mapping: wheel DOWN → previous, wheel UP → next. Default off.
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

    // Touchpad/hi-res wheels report sub-notch deltas that must accumulate to a full notch before stepping.
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

    // Real wheel EVENTS (not just handleWheel) — the path broken in-shell: a MouseArea behind the dots
    // receives the wheel because the dots have no onWheel, so it propagates down.
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

    // Wheel events must not block clicks: the wheel MouseArea is NoButton, so press/release pass through.
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

    // Scrolling while the current desktop is stale (activeIndex == -1, a transient add/remove
    // state) is a no-op — stepIndex returns -1, so handleWheel emits nothing. Covers the
    // next<0 guard via both the handler and a real wheel event.
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

    // Negative (wheel-up) remainder persists across events: -200 steps once and carries -80, so a
    // following -40 completes the next notch (a dropped remainder would never switch).
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

    // scroll: positive (wheel-up) remainder carry — symmetric to the negative case: +200 steps once and
    // carries +80, so a following +40 completes the next notch (we assert the count and carried remainder).
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

        indicator.enableScroll = true;   // user enables scrolling mid-session
        indicator.handleWheel(-120);
        compare(switchSpy.count, 1, "enabling scroll at runtime makes the wheel step");
        compare(switchSpy.signalArguments[0][0], ids[1], "and it steps to the next desktop");

        indicator.enableScroll = false;  // ...and disables it again
        indicator.handleWheel(-120);
        compare(switchSpy.count, 1, "disabling scroll again stops further steps");
    }

    function test_invertScrollToggledLive() {
        // current stays ids[1] throughout, so both steps compute from the middle — only the direction flips.
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

        indicator.scrollWrap = true;   // user enables wrap mid-session
        indicator.handleWheel(-120);   // down from the last desktop, wrapping → first
        compare(switchSpy.count, 1, "enabling wrap at runtime wraps past the end");
        compare(switchSpy.signalArguments[0][0], ids[0], "and it wraps to the first desktop");
    }
}
