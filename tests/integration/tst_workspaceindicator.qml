/*
 * GNOME Workspace Switcher — tst_workspaceindicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
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
import "../shared/treewalk.js" as TreeWalk

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

    // Stands in for TaskManager.VirtualDesktopInfo (duck-typed: the indicator reads
    // .desktopIds, .currentDesktop and — for tooltips — .desktopNames). Built per test
    // via makeMock(...).
    Component {
        id: vdiMockComponent
        QtObject {
            property var desktopIds: []
            property string currentDesktop: ""
            property var desktopNames: []
        }
    }

    SignalSpy {
        id: switchSpy
        signalName: "switchRequested"
    }

    // A duck-typed VirtualDesktopInfo mock. Pass a currentDesktop outside desktopIds (the
    // staleUuid) to exercise the transient add/remove state the indicator must tolerate.
    // desktopNames is optional (defaults []), needed only by the tooltip tests.
    function makeMock(desktopIds, currentDesktop, desktopNames) {
        return createTemporaryObject(vdiMockComponent, testCase, {
            desktopIds: desktopIds,
            currentDesktop: currentDesktop,
            desktopNames: desktopNames || []
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

    // Collect the WorkspaceDot delegates from the indicator's visual tree. A dot is
    // uniquely identified by its required `modelData` (the desktop UUID) plus the
    // `active` bool — no other item in the tree carries both. The subtree walk is shared
    // with the unit tier (tests/shared/treewalk.js); only the predicate is dot-specific.
    function isDot(c) {
        return c.modelData !== undefined && typeof c.active === "boolean";
    }
    function collectDots(indicator) {
        return TreeWalk.collect(indicator, isDot);
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

    // The dots in Repeater/index order (left→right), so geometry tests can walk neighbours.
    function dotsByIndex(indicator) {
        const dots = collectDots(indicator);
        dots.sort((a, b) => a.index - b.index);
        return dots;
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
        compare(indicator.Layout.preferredWidth, indicator.implicitWidth, "preferredWidth advertises the content width");
        compare(indicator.Layout.minimumWidth, indicator.implicitWidth, "minimumWidth advertises the content width");
        compare(indicator.Layout.maximumWidth, indicator.implicitWidth, "maximumWidth pins the width (a pager does not stretch)");
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
}
