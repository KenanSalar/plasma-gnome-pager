/*
 * Plasma Gnome Pager — tst_workspaceindicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Integration test for WorkspaceIndicator — the composed dot strip + reflow + reactive
 * wiring, exercising the documented robustness guards (see .claude/rules/robustness.md).
 * It is testable headless because the indicator depends only on QtQuick / QtQuick.Layouts /
 * Kirigami (+ logic.js) and reads desktop state through a duck-typed `virtualDesktopInfo`
 * property — a plain QtObject stands in for TaskManager.VirtualDesktopInfo. Its WorkspaceDot
 * delegates pull in org.kde.plasma.core for their per-dot ToolTipArea, which loads fine under
 * offscreen qmltestrunner.
 *
 * main.qml / PlasmoidItem is intentionally NOT tested here: it needs plasmashell,
 * KWin and a session bus, which don't exist under qmltestrunner. See tests/README.md.
 *
 * Run with `make check` (sets QT_QPA_PLATFORM=offscreen so Kirigami initialises
 * without a display).
 */
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager
import "../shared"                          // VdiMock.qml (the shared VirtualDesktopInfo double)
import "../shared/treewalk.js" as TreeWalk
import "../shared/elements.js" as Elements

TestCase {
    id: testCase
    name: "WorkspaceIndicator"
    when: windowShown
    visible: true   // so children report effective `visible` (else it's always false)
    width: 200
    height: 50

    // Shared fixtures so the desktop set and UUIDs live in one place (the tests assert
    // against these, not against scattered literals).
    readonly property var ids: ["uuid-a", "uuid-b", "uuid-c"]
    readonly property string currentUuid: "uuid-b"   // ids[1], the middle desktop
    readonly property string staleUuid: "uuid-gone"  // intentionally NOT in ids

    Component {
        id: indicatorComponent
        Pager.WorkspaceIndicator {}
    }

    // Stands in for TaskManager.VirtualDesktopInfo — the shared, canonical double (duck-typed to the
    // members the indicator reads; see tests/shared/VdiMock.qml). Built per test via makeMock(...);
    // per-screen tests set perScreenCurrent and emit currentDesktopForScreenChanged.
    Component {
        id: vdiMockComponent
        VdiMock {}
    }

    SignalSpy {
        id: switchSpy
        signalName: "switchRequested"
    }

    // A duck-typed VirtualDesktopInfo mock. Pass a currentDesktop outside desktopIds (the
    // staleUuid) to exercise the transient add/remove state the indicator must tolerate.
    // desktopNames is optional (defaults []), needed only by the tooltip tests.
    function makeMock(desktopIds, currentDesktop, desktopNames, desktopLayoutRows) {
        return createTemporaryObject(vdiMockComponent, testCase, {
            desktopIds: desktopIds,
            currentDesktop: currentDesktop,
            desktopNames: desktopNames || [],
            desktopLayoutRows: desktopLayoutRows || 1
        });
    }

    // The single point that instantiates the component under test (auto-cleaned). Extra
    // props (e.g. enableScroll/scrollWrap, an explicit width) can be passed for the
    // interaction tests; virtualDesktopInfo is always set.
    function makeIndicator(vdi, props) {
        const p = props || {};
        p.virtualDesktopInfo = vdi;
        return createTemporaryObject(indicatorComponent, testCase, p);
    }

    // Collect the WorkspaceDot delegates from the indicator's visual tree. A dot is uniquely
    // identified by its required `modelData` (the desktop UUID) plus the `active` bool — no other
    // item in the tree carries both. The walk + duck-type predicates are shared with the unit tier
    // (tests/shared/elements.js).
    function collectDots(indicator) {
        return TreeWalk.collect(indicator, Elements.isDot);
    }

    // Find the dot delegate for a given desktop UUID (or null) — used by the
    // reactivity/geometry tests below to locate a specific element.
    function dotByUuid(indicator, uuid) {
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === uuid)
                return dots[i];
        return null;
    }

    // The dots in flat desktop order, so geometry tests can walk neighbours. Sort by globalIndex
    // (line * perLine + position) so it stays correct across multiple grid lines; for a single
    // line globalIndex == the per-line index, so single-line tests are unaffected.
    function dotsByIndex(indicator) {
        const dots = collectDots(indicator);
        dots.sort((a, b) => a.globalIndex - b.globalIndex);
        return dots;
    }

    // The dim circle/capsule Rectangle inside a given dot (shared locator, tests/shared/elements.js).
    // Used by the colour flow-through test.
    function circleOf(dot) {
        return Elements.circleOf(dot);
    }

    // One dot per desktop UUID in the source.
    function test_dotCountMatchesDesktops() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator, "indicator created");
        compare(collectDots(indicator).length, ids.length);
    }

    // robustness.md: a null source (transient during desktop add/remove or shell
    // reload) must yield an empty strip, never an error or a stray dot.
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

    // --- The reflow capsule (the active element morphs to a pill) ------------------

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
        let capsules = 0, plain = 0;
        for (let i = 0; i < dots.length; i++) {
            if (Math.abs(dots[i].width - indicator.pillWidth) <= 0.5)
                capsules++;
            else if (Math.abs(dots[i].width - indicator.dotSize) <= 0.5)
                plain++;
        }
        compare(capsules, 1, "exactly one capsule");
        compare(plain, ids.length - 1, "all other elements are dots");
    }

    // robustness.md: a null source (transient) yields no elements, and the cell falls back
    // to a sane minimum (one dot wide) rather than collapsing to 0.
    function test_nullSourceNoCapsule() {
        const indicator = makeIndicator(null);
        compare(indicator.activeIndex, -1, "no active index without a source");
        compare(collectDots(indicator).length, 0, "no elements");
        fuzzyCompare(indicator.implicitWidth, indicator.dotSize, 0.5, "cell falls back to one dot wide");
    }

    // robustness.md: currentDesktop not (yet) in desktopIds during an add/remove → no
    // capsule (all dots), and the advertised width stays at the steady-state (one-capsule)
    // value so the panel cell does NOT jitter while the active element is momentarily unknown.
    function test_transientStaleNoCapsuleWidthStable() {
        const indicator = makeIndicator(makeMock(ids, staleUuid));
        compare(indicator.activeIndex, -1, "stale currentDesktop maps to -1");
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            fuzzyCompare(dots[i].width, indicator.dotSize, 0.5, "no capsule while stale: " + dots[i].modelData);
        const steady = indicator.pillWidth + (ids.length - 1) * (indicator.dotSize + indicator.dotSpacing);
        fuzzyCompare(indicator.implicitWidth, steady, 0.5, "cell stays at the steady-state width");
    }

    // Uniform spacing: the gap between EVERY adjacent pair — dot-dot and capsule-dot alike —
    // equals the single Row spacing (the GNOME look; positive gaps also prove no overlap).
    function test_uniformSpacing() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));   // middle is the capsule
        const dots = dotsByIndex(indicator);
        for (let i = 0; i < dots.length - 1; i++) {
            const rightEdge = dots[i].mapToItem(indicator, dots[i].width, 0).x;
            const nextLeft = dots[i + 1].mapToItem(indicator, 0, 0).x;
            fuzzyCompare(nextLeft - rightEdge, indicator.dotSpacing, 0.5, "uniform gap after element " + i);
        }
    }

    // --- Reactivity: the "bind, don't cache" contract -----------------------------
    // The indicator reads desktop state live, so a change by ANY means (keyboard, another
    // pager, settings) — modelled here by mutating the mock — must update the UI without
    // a manual refresh. These tests fail if a binding is ever replaced by a cached value.

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

    // Switching morphs the capsule: the new current element grows to pillWidth while the old
    // shrinks back to dotSize. tryVerify polls so it tolerates the morph animation.
    function test_morphOnSwitch() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        verify(Math.abs(dotByUuid(indicator, ids[0]).width - indicator.pillWidth) <= 0.5, "ids[0] starts as the capsule");

        vdi.currentDesktop = ids[2];

        tryVerify(function () {
            return Math.abs(dotByUuid(indicator, ids[2]).width - indicator.pillWidth) <= 0.5
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

    // Removing a desktop (desktopIds shrinks) drops a dot; the capsule re-tracks the
    // still-current desktop at its new index rather than disappearing.
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
            return Math.abs(dotByUuid(indicator, ids[2]).width - indicator.pillWidth) <= 0.5;
        }, 2000, "the surviving current desktop is the capsule");
    }

    // --- Plasma 6.7: per-screen current desktop -----------------------------------
    // "Switch desktops independently for each screen": each output can show a different current
    // desktop. The indicator resolves the current FOR ITS screen (screenName) via the mock's
    // currentDesktopByScreenName, falling back to the global currentDesktop when there is no
    // per-screen entry. These prove (a) the active dot reflects this screen, not the global current;
    // (b) a switch on ANOTHER screen does not move this strip's pill (the reported bug); and
    // (c) this screen's own switch is reactive.

    // The active dot follows THIS screen's current desktop, not the global one.
    function test_perScreenActiveFollowsOwnScreen() {
        const vdi = makeMock(ids, ids[0]);              // global current = first desktop
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[2], "resolves this screen's current, not the global one");
        verify(dotByUuid(indicator, ids[2]).active, "this screen's current desktop is the active dot");
        verify(!dotByUuid(indicator, ids[0]).active, "the global current is NOT active on this screen");
    }

    // The reported bug: switching ANOTHER monitor's desktop must NOT move this strip's pill.
    function test_perScreenIgnoresOtherScreenSwitch() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[2]).active, "starts on this screen's current (uuid-c)");

        // Monitor DP-1 switches to uuid-b: its per-screen current and the global current both move.
        vdi.perScreenCurrent = { "DP-1": ids[1], "DP-2": ids[2] };
        vdi.currentDesktop = ids[1];                    // global follows the active output (DP-1)
        vdi.currentDesktopForScreenChanged("DP-1");

        compare(indicator.currentDesktop, ids[2], "this screen's current is unchanged");
        verify(dotByUuid(indicator, ids[2]).active, "this screen's pill stays put when ANOTHER screen switches");
        verify(!dotByUuid(indicator, ids[1]).active, "it does not follow the other screen's new desktop");
    }

    // This screen's own switch updates the active dot reactively (bind, don't cache).
    function test_perScreenReactiveToOwnScreenSwitch() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-2": ids[0] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[0]).active, "starts on uuid-a");

        vdi.perScreenCurrent = { "DP-2": ids[1] };
        vdi.currentDesktopForScreenChanged("DP-2");     // this output switched

        compare(indicator.currentDesktop, ids[1], "current re-resolves to this screen's new desktop");
        verify(dotByUuid(indicator, ids[1]).active, "the active dot moves to the new current");
        verify(!dotByUuid(indicator, ids[0]).active, "the old dot deactivates");
    }

    // An unknown screen falls back to the global current (matches the mock's by-name fallback, and
    // models a screen the per-screen API doesn't know — e.g. the feature off).
    function test_perScreenFallsBackToGlobalWhenScreenUnknown() {
        const vdi = makeMock(ids, ids[1]);
        vdi.perScreenCurrent = { "DP-1": ids[2] };       // only DP-1 has an entry
        const indicator = makeIndicator(vdi, { screenName: "DP-UNKNOWN" });
        compare(indicator.currentDesktop, ids[1], "unknown screen falls back to the global current");
        verify(dotByUuid(indicator, ids[1]).active, "global current is active when this screen is unknown");
    }

    // Empty screenName (representation not yet placed) → global current, exercising the screenName guard.
    function test_perScreenEmptyScreenNameUsesGlobal() {
        const vdi = makeMock(ids, ids[2]);
        vdi.perScreenCurrent = { "DP-1": ids[0] };
        const indicator = makeIndicator(vdi, { screenName: "" });
        compare(indicator.currentDesktop, ids[2], "empty screenName uses the global current");
        verify(dotByUuid(indicator, ids[2]).active, "global current is active with no screen name");
    }

    // --- animate latch: instant first placement, morph thereafter -----------------
    // `animate` is a one-way latch that gates the per-dot morph so the FIRST valid placement
    // is instant (the active element is already a capsule, no grow-in on shell reload) — see
    // the gotcha in CLAUDE.md / WorkspaceIndicator.qml.

    // Created with a valid current desktop: the latch is already set (Component.onCompleted).
    function test_animateLatchedOnValidStart() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.animate, true, "morph latched on a valid initial placement");
    }

    // Created with no active element, then a source arrives: the latch enables via the
    // onActiveIndexChanged + Qt.callLater deferral path (so the first placement is instant).
    function test_animateDefersFromInvalidStart() {
        const indicator = makeIndicator(null);   // no source → activeIndex -1
        compare(indicator.animate, false, "morph disabled while there is no active element");

        indicator.virtualDesktopInfo = makeMock(ids, currentUuid);   // source populates a frame later
        tryCompare(indicator, "animate", true, 2000, "morph enables once a valid element first appears");
    }

    // Once latched true, a transient loss of the active element (current drops out of ids
    // during an add/remove) must NOT reset the latch back to false.
    function test_animateIsOneWayLatch() {
        const vdi = makeMock(ids, currentUuid);
        const indicator = makeIndicator(vdi);
        compare(indicator.animate, true, "latched true at start");

        vdi.currentDesktop = staleUuid;   // current momentarily not in ids
        compare(indicator.activeIndex, -1, "no active element now");
        wait(0);
        compare(indicator.animate, true, "animate never returns to false");
    }

    // First placement is instant: created already at the LAST desktop, that element is a
    // capsule on the first frame (synchronous — no grow-in from a dot).
    function test_firstPlacementIsImmediate() {
        const indicator = makeIndicator(makeMock(ids, ids[2]));
        fuzzyCompare(dotByUuid(indicator, ids[2]).width, indicator.pillWidth, 0.5,
                     "active element is already a capsule on first placement");
    }

    // --- activeIndex edge cases (data-driven) -------------------------------------
    // activeIndex is the guard the capsule hangs off; it must be -1 for every transient/
    // invalid state and the correct element index otherwise.
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

    // --- geometry edge cases ------------------------------------------------------

    // The advertised width holds the whole strip, so the end elements never clip past the
    // edges — whether the capsule is at the first or the last desktop.
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

    // Clicking the active capsule switches (the whole capsule is the hit area). Needs a real
    // synthesized click — direct signal emission would bypass the hit-test.
    function test_clickActiveCapsuleSwitches() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        const capsule = dotByUuid(indicator, currentUuid);
        const p = capsule.mapToItem(indicator, capsule.width / 2, capsule.height / 2);
        mouseClick(indicator, p.x, p.y);

        compare(switchSpy.count, 1, "clicking the active capsule emits a switch");
        compare(switchSpy.signalArguments[0][0], currentUuid, "the active desktop's UUID is forwarded");
    }

    // --- Milestone 3: scroll-to-switch --------------------------------------------
    // The indicator forwards a wheel step as switchRequested(uuid); the index math
    // (clamp/wrap/accumulate) is unit-tested in tst_logic, so here we assert the wiring:
    // direction, the enable/wrap flags, the clamped no-ops, and sub-notch accumulation.
    // Wheel DOWN (negative angleDelta) → next desktop; wheel UP (positive) → previous.

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

    // Touchpad/hi-res wheels report sub-notch deltas that must accumulate to a full notch
    // before stepping (and not be lost in between).
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

    // Real wheel EVENTS (not just calling handleWheel) — these exercise the actual path
    // that was broken in-shell: a MouseArea behind the dots receives the wheel because the
    // dots have no onWheel, so it propagates down. mouseWheel(item, x, y, xDelta, yDelta).
    function test_wheelEventStepsNext() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: true, width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);   // wheel down over the strip
        compare(switchSpy.count, 1, "a real wheel event switches");
        compare(switchSpy.signalArguments[0][0], ids[1], "wheel down moves to the next desktop");
    }

    function test_wheelEventDisabledIsNoOp() {
        const indicator = makeIndicator(makeMock(ids, ids[0]), { enableScroll: false, width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        mouseWheel(indicator, indicator.width / 2, indicator.height / 2, 0, -120);
        compare(switchSpy.count, 0, "a real wheel event does nothing when scroll is disabled");
    }

    // Wheel events must not block clicks: clicking a dot still switches to it (the wheel
    // MouseArea is NoButton, so press/release pass through to the dot beneath).
    function test_wheelLayerDoesNotBlockClicks() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        switchSpy.target = indicator;
        switchSpy.clear();

        const dot = dotByUuid(indicator, ids[0]);
        const c = dot.mapToItem(indicator, dot.width / 2, dot.height / 2);
        mouseClick(indicator, c.x, c.y);
        compare(switchSpy.count, 1, "clicking a dot still works with the wheel layer present");
        compare(switchSpy.signalArguments[0][0], ids[0], "the clicked dot's UUID is forwarded");
    }

    // --- Milestone 3: panel sizing ------------------------------------------------
    // The applet collapsed to a square cell in-shell (dots overflowed the neighbours) when
    // the representation advertised only implicitWidth. The indicator must expose its
    // content width through Layout.* hints so the panel allocates the right space.
    function test_advertisesWidthViaLayout() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator.implicitWidth > 0, "indicator has a positive content width");
        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth advertises the natural content width");
        compare(indicator.Layout.maximumWidth, indicator.implicitWidth, "maximumWidth pins the natural width (a pager does not stretch past it)");
        // M6 scale-to-fit: the MINIMUM drops to the floor (one line at minDotSize) so the panel can
        // compress us and the dots shrink to fit instead of overflowing the neighbours.
        verify(indicator.minDotSize < indicator.naturalDotSize, "the legible floor dot is smaller than natural");
        verify(indicator.Layout.minimumWidth < indicator.implicitWidth, "minimumWidth drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorStripLength, 0.5, "minimumWidth is the floor (strip at the minimum legible dot)");
    }

    // --- Milestone 4: vertical form factor ----------------------------------------
    // On a vertical (side) panel the strip becomes a single COLUMN: dots stack along Y, the
    // capsule grows TALL, and the pinned/free Layout axes swap (height pinned, width free to fill
    // the panel thickness). `vertical` defaults false, so every test above stays horizontal; these
    // mirror the horizontal geometry/sizing assertions onto the Y / height axis. Like the other
    // geometry tests they pass no explicit size, so the Item auto-sizes to its implicit extents.

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

    // Uniform spacing along Y: the vertical gap between EVERY adjacent pair equals the single
    // strip spacing (capsule-dot and dot-dot alike; positive gaps also prove no overlap).
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

    // Vertical sizing: the HEIGHT axis is pinned to the strip length (min == preferred == max),
    // while the WIDTH axis is left free (preferred == one dot, maximum unconstrained) so the panel
    // can stretch the strip to its thickness. Mirror of test_advertisesWidthViaLayout.
    function test_verticalAdvertisesHeightViaLayout() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        verify(indicator.implicitHeight > 0, "indicator has a positive content height");
        compare(indicator.Layout.preferredHeight, indicator.implicitHeight, "preferredHeight advertises the natural content length");
        compare(indicator.Layout.maximumHeight, indicator.implicitHeight, "maximumHeight pins the natural length (a pager does not stretch past it)");
        // M6 scale-to-fit: the MAJOR (height) minimum drops to the floor so a short panel compresses
        // the column and the dots shrink to fit.
        verify(indicator.Layout.minimumHeight < indicator.implicitHeight, "minimumHeight drops below natural so the panel can compress us");
        fuzzyCompare(indicator.Layout.minimumHeight, indicator.floorStripLength, 0.5, "minimumHeight is the floor (column at the minimum legible dot)");

        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth is one dot thick");
        const maxW = indicator.Layout.maximumWidth;
        verify(maxW < 0 || maxW > indicator.implicitWidth, "width axis is free (max unconstrained), so the panel fills the thickness");
        // Cross (width) MINIMUM drops to floorCrossThickness too (cross scale-to-fit), so an ultra-thin
        // side panel can compress the thickness and the dot shrinks rather than overflowing it.
        fuzzyCompare(indicator.Layout.minimumWidth, indicator.floorCrossThickness, 0.5, "cross (width) min is the floor");
    }

    // The cross axis is one dot thick.
    function test_verticalImplicitCrossAxis() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { vertical: true });
        fuzzyCompare(indicator.implicitWidth, indicator.dotSize, 0.5, "vertical strip is one dot wide");
        const steady = indicator.pillWidth + (ids.length - 1) * (indicator.dotSize + indicator.dotSpacing);
        fuzzyCompare(indicator.implicitHeight, steady, 0.5, "vertical strip length is the steady-state formula");
    }

    // Switching morphs the capsule along the height: the new current grows tall while the old
    // shrinks back to a dot. tryVerify polls so it tolerates the morph animation.
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

    // The advertised length holds the whole column, so the end elements never clip past the
    // top/bottom edges — whether the capsule is at the first or the last desktop.
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

    // --- Milestone 4: multi-row grid (mirrors KWin's desktopLayoutRows) -----------
    // When KWin's desktop grid has more than one row, the strip splits the desktops into that many
    // LINES, each an independent single-line reflow strip. Driven live by desktopLayoutRows on the
    // mock; defaults to 1 (single line) so every test above is unaffected. Horizontal panel: lines
    // stack vertically (rows of dots); the per-line count is ceil(count / rows).

    readonly property var fourIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d"]
    readonly property var fiveIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d", "uuid-e"]

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

    // Default / 1 row stays a single line — the M3/M4 single-line behaviour.
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
        const major = indicator.pillWidth + (indicator.perLine - 1) * (indicator.dotSize + indicator.dotSpacing);
        const cross = indicator.lineCount * indicator.dotSize + (indicator.lineCount - 1) * indicator.dotSpacing;
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

    // --- Milestone 3: per-dot tooltip data ----------------------------------------
    // Tooltips live per-dot now; the indicator feeds each dot its name and the flag.

    function test_dotsReceiveDesktopName() {
        const names = ["One", "Two", "Three"];
        const indicator = makeIndicator(makeMock(ids, currentUuid, names));
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            compare(dot.desktopName, names[i], "dot " + i + " gets its index-aligned name");
        }
    }

    // robustness.md: names can lag ids during an add/remove — the dot gets "" (no OOB).
    function test_dotDesktopNameGuardsShortNames() {
        const indicator = makeIndicator(makeMock(ids, currentUuid, ["One"]));   // names shorter than ids
        compare(dotByUuid(indicator, ids[2]).desktopName, "", "missing name resolves to empty string");
    }

    function test_showTooltipsPropagatesToDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid, ["One", "Two", "Three"]), { showTooltips: false });
        verify(!dotByUuid(indicator, ids[0]).showTooltips, "showTooltips=false reaches the dots");

        indicator.showTooltips = true;
        verify(dotByUuid(indicator, ids[0]).showTooltips, "toggling showTooltips updates the dots reactively");
    }

    // --- window-list tooltip: per-dot subText, index-aligned with desktopIds -----------
    // main.qml builds the window-list subText per desktop and hands the indicator an array parallel
    // to desktopNames; the indicator feeds each dot its entry by globalIndex (exactly like the name).

    function test_dotsReceiveTooltipText() {
        const tips = ["win-a", "win-b", "win-c"];
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: tips });
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            compare(dot.tooltipText, tips[i], "dot " + i + " gets its index-aligned window-list subText");
        }
    }

    // robustness.md: the tooltip array can lag ids during an add/remove — the dot gets "" (no OOB).
    function test_dotTooltipTextGuardsShortArray() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: ["win-a"] });
        compare(dotByUuid(indicator, ids[2]).tooltipText, "", "missing tooltip resolves to empty string");
    }

    // Index-aligned across the whole flat list, not reset per line (mirrors test_gridNamesMapAcrossLines).
    function test_tooltipTextMapsAcrossLines() {
        const tips = ["w0", "w1", "w2", "w3"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { desktopTooltips: tips });
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).tooltipText, tips[i], "dot " + i + " keeps its global window-list subText");
    }

    // --- Milestone 5: appearance / colour / animation config flow through ----------
    // main.qml feeds the indicator the Appearance keys; the indicator forwards them per-dot. These
    // assert the wiring (the values reach the derived metrics + the dots); the look itself is
    // covered by the dot unit tests and the logic tier.

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

    // Custom colours flow through: with followThemeColors off, each dot's circle uses the
    // configured colours (active vs inactive).
    function test_colorsFlowThrough() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            followThemeColors: false,
            activeColor: "#ff0000",
            inactiveColor: "#00ff00"
        });
        const activeDot = dotByUuid(indicator, currentUuid);
        const inactiveDot = dotByUuid(indicator, ids[0]);
        compare(circleOf(activeDot).color, indicator.activeColor, "active dot uses the custom active colour");
        compare(circleOf(inactiveDot).color, indicator.inactiveColor, "inactive dot uses the custom inactive colour");
    }

    // animationDuration flows through to each dot and resolves there.
    function test_animationDurationFlowsThrough() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { animationDuration: 250 });
        const dot = dotByUuid(indicator, ids[0]);
        compare(dot.animationDuration, 250, "dot gets the configured duration");
        compare(dot.effectiveDuration, 250, "dot resolves it to effectiveDuration");
    }

    // --- Per-screen current: re-resolution paths beyond the initial placement ------
    // The per-screen tests above set screenName at creation. These exercise the two Connections
    // that re-resolve a LIVE indicator: onScreenNameChanged (the panel moved to another output)
    // and onDesktopIdsChanged (a desktop the screen was on got removed and KWin reassigned it).

    // The panel is dragged to another monitor: screenName changes on a live indicator, so the
    // current must re-resolve to the new output's per-screen current (exercises onScreenNameChanged).
    function test_perScreenReactiveToScreenNameChange() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-1" });
        verify(dotByUuid(indicator, ids[0]).active, "starts on DP-1's current (uuid-a)");

        indicator.screenName = "DP-2";   // the widget's panel moved to the other monitor

        compare(indicator.currentDesktop, ids[2], "current re-resolves to the new screen's current");
        verify(dotByUuid(indicator, ids[2]).active, "the active dot follows the new output");
        verify(!dotByUuid(indicator, ids[0]).active, "the old output's dot deactivates");
    }

    // A desktop add/remove can change THIS screen's current; onDesktopIdsChanged must re-resolve
    // the per-screen current (the existing add/remove tests use a global-current mock).
    function test_perScreenReResolvesOnDesktopRemoval() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[2]).active, "starts on this screen's current (uuid-c)");

        // uuid-c is removed; KWin moves this screen to uuid-b. Update the per-screen map first, then
        // shrink desktopIds — the ids change fires onDesktopIdsChanged, which re-resolves the current.
        vdi.perScreenCurrent = { "DP-2": ids[1] };
        vdi.desktopIds = [ids[0], ids[1]];

        tryCompare(indicator, "currentDesktop", ids[1], 2000, "re-resolves this screen's current after the removal");
        verify(dotByUuid(indicator, ids[1]).active, "the surviving per-screen current is the active dot");
        verify(!dotByUuid(indicator, ids[2]), "the removed desktop's dot is gone");
    }

    // --- Scroll edge: no active element, and remainder sign across events -----------

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

    // Negative (wheel-up) remainder persists in wheelAccumulator across events with the right sign:
    // a -200 delta steps once and carries -80, so a following -40 completes the next notch. If the
    // remainder were dropped (reset to 0), the -40 would be sub-notch and never switch.
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

    // --- desktopRows clamp guard ---------------------------------------------------

    // The indicator clamps a transient 0/undefined desktopLayoutRows to a single line (its own
    // ternary, separate from Logic.gridColumns). makeMock's `|| 1` default hides a literal 0, so
    // set it post-construction.
    function test_gridRowsClampGuard() {
        const vdi = makeMock(fourIds, fourIds[0]);   // defaults to 1 row
        const indicator = makeIndicator(vdi);
        vdi.desktopLayoutRows = 0;                   // transient/invalid value from KWin

        compare(indicator.desktopRows, 1, "a 0 row count clamps to a single line");
        compare(indicator.lineCount, 1, "everything stays on one line");
        compare(indicator.perLine, fourIds.length, "the single line holds all desktops");
    }

    // --- Hover passes through the wheel layer (composed strip) ---------------------

    // The behind-dots wheelArea (NoButton, no hover) must not swallow hover: hovering an inactive
    // dot in the REAL composition brightens it to hoverOpacity. This is the hover analogue of
    // test_wheelLayerDoesNotBlockClicks (hover is only otherwise tested on a standalone dot).
    function test_hoverBrightensDotInComposedStrip() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        const dot = dotByUuid(indicator, ids[0]);   // inactive (current is uuid-b)
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, indicator.inactiveOpacity, 0.001, "inactive dot starts dim");

        const c = dot.mapToItem(indicator, dot.width / 2, dot.height / 2);
        mouseMove(indicator, c.x, c.y);
        tryCompare(circle, "opacity", indicator.hoverOpacity, 2000, "hover brightens through the wheel layer");

        mouseMove(indicator, -5, -5);   // pointer leaves the strip
        tryCompare(circle, "opacity", indicator.inactiveOpacity, 2000, "returns to dim when not hovered");
    }

    // --- The animate latch gates each dot's morph ----------------------------------

    // The indicator's animate latch + the configured duration resolve into each dot's morphEnabled
    // gate (animate && effectiveDuration > 0). Wiring check: with a valid start the latch is on,
    // and every dot's gate matches the resolved relationship (true unless animations are disabled).
    function test_morphGateFlowsThroughToDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { animationDuration: 200 });
        compare(indicator.animate, true, "latch is on for a valid initial placement");
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            compare(dots[i].morphEnabled, indicator.animate && dots[i].effectiveDuration > 0,
                    "dot " + i + " morph gate matches latch && duration");
    }

    // The animate latch's immediate-placement check runs AFTER the per-screen current is resolved
    // in Component.onCompleted: created already on this screen's per-screen current, that element is
    // a capsule on the first frame (no grow-in) — the per-screen variant of test_firstPlacementIsImmediate.
    function test_firstPlacementImmediatePerScreen() {
        const vdi = makeMock(ids, ids[0]);              // global current is uuid-a
        vdi.perScreenCurrent = { "DP-2": ids[2] };      // but THIS screen is on uuid-c
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[2], "onCompleted resolved the per-screen current");
        compare(indicator.animate, true, "the latch is on after a valid per-screen placement");
        fuzzyCompare(dotByUuid(indicator, ids[2]).width, indicator.pillWidth, 0.5,
                     "this screen's current is already a capsule on the first frame");
    }

    // --- Milestone 6: robustness hardening & edge cases ---------------------------
    // Scale-to-fit (overflow), the empty-array transient, many desktops, and rapid switching. The
    // Layout-hint side of scale-to-fit is asserted in test_advertisesWidthViaLayout /
    // test_verticalAdvertisesHeightViaLayout (minimum drops to the floor); these assert the rendered
    // RESULT — the dots actually shrink to fit a crowded allocation and grow back when there is room.

    readonly property var sixIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d", "uuid-e", "uuid-f"]

    // Build an N-desktop UUID list for the many-desktops cases (no scattered literals).
    function manyIds(n) {
        const out = [];
        for (let i = 0; i < n; i++)
            out.push("uuid-" + i);
        return out;
    }

    // A narrow allocation (half the natural strip) makes the dots shrink below natural so the line
    // still fits the allocated width instead of overflowing the neighbours. Setting indicator.width
    // directly replaces the implicitWidth binding — exactly how the panel constrains the applet.
    function test_scaleDotsShrinkOnNarrowWidth() {
        const indicator = makeIndicator(makeMock(sixIds, sixIds[0]));
        indicator.width = indicator.naturalStripLength * 0.6;   // panel grants 60% of the natural length
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "effective dot shrank below natural");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        fuzzyCompare(dotByUuid(indicator, sixIds[1]).dotSize, indicator.dotSize, 0.5, "each dot uses the effective size");
        // tryVerify: the rendered dot widths morph (Behavior on width), so wait for the reflow to settle.
        tryVerify(() => {
            const dots = dotsByIndex(indicator);
            const last = dots[dots.length - 1];
            return last.mapToItem(indicator, last.width, 0).x <= indicator.width + 0.5;
        }, 2000, "the shrunken line fits the allocated width");
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
        tryVerify(() => {
            const dots = dotsByIndex(indicator);
            const last = dots[dots.length - 1];
            return last.mapToItem(indicator, 0, last.height).y <= indicator.height + 0.5;
        }, 2000, "the shrunken column fits the allocated height");
    }

    // CROSS-axis scale-to-fit: a multi-row KWin grid (4 rows) on a THIN horizontal panel. The major
    // (width) axis has natural room, so only the cross (height) thickness is constrained — the dots must
    // shrink so the stacked lines fit the thickness instead of overflowing it. Setting height to a
    // fraction f of naturalCrossThickness yields an effective dotSize of f × naturalDotSize (the cross
    // fit is the exact inverse), so f == 0.6 stays comfortably above the legible floor (0.5 × natural).
    function test_scaleDotsShrinkOnThinCrossMultiRow() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));   // 4 lines of 3
        indicator.height = indicator.naturalCrossThickness * 0.6;        // panel thinner than the 4 stacked lines need
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "cross-fit shrank the dot below natural");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        // tryVerify: the rendered dot sizes morph, so wait for the reflow to settle; the last line (highest
        // globalIndex) sits in the bottom row, so its bottom must land within the allocated thickness.
        tryVerify(() => {
            const dots = dotsByIndex(indicator);
            const last = dots[dots.length - 1];
            return last.mapToItem(indicator, 0, last.height).y <= indicator.height + 0.5;
        }, 2000, "the shrunken grid fits the allocated cross thickness");
    }

    // With ample thickness the multi-row grid is unchanged: the cross fit exceeds natural, so the caller
    // keeps natural — the common case (a roomy panel) stays byte-for-byte as today.
    function test_scaleDotsCrossUnchangedWhenAmpleThickness() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4));
        indicator.height = indicator.naturalCrossThickness * 2;          // plenty of cross room
        fuzzyCompare(indicator.dotSize, indicator.naturalDotSize, 0.5, "no shrink when the thickness is ample");
    }

    // Vertical transpose of the cross-fit: on a side panel the cross axis is WIDTH, so a thin side panel
    // with a multi-row grid shrinks the dots to fit the width (the lines stack along x).
    function test_scaleDotsShrinkOnThinCrossVertical() {
        const big = manyIds(12);
        const indicator = makeIndicator(makeMock(big, big[0], [], 4), { vertical: true });
        indicator.width = indicator.naturalCrossThickness * 0.6;         // side panel thinner than the stacked lines need
        tryVerify(() => indicator.dotSize < indicator.naturalDotSize - 0.5, 2000, "cross-fit shrank the dot below natural (vertical)");
        verify(indicator.dotSize >= indicator.minDotSize - 0.001, "but never below the legible floor");
        tryVerify(() => {
            const dots = dotsByIndex(indicator);
            const last = dots[dots.length - 1];
            return last.mapToItem(indicator, last.width, 0).x <= indicator.width + 0.5;
        }, 2000, "the shrunken grid fits the allocated cross thickness (width)");
    }

    // robustness.md: an empty desktopIds ARRAY (distinct from a null source) during a transient
    // add/remove must yield no dots and a cell that holds one dot, never collapsing to 0.
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
        const expected = nd * indicator.pillWidthFactor + (20 - 1) * (nd + nd * indicator.spacingFactor);
        fuzzyCompare(indicator.naturalStripLength, expected, 0.5, "natural strip length matches the formula for 20 desktops");
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

    // Rapid back-to-back switches (a fast keyboard/scroll burst, fired mid-morph) must converge to
    // exactly one capsule on the final target and never throw — the one-way animate latch and the
    // idempotent updateCurrentDesktop() recompute settle deterministically.
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
        tryVerify(() => Math.abs(dotByUuid(indicator, fiveIds[3]).width - indicator.pillWidth) < 0.5,
                  2000, "the final desktop morphs to the capsule width");
    }
}
