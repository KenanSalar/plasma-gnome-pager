/*
 * GNOME Workspace Switcher — tst_workspaceindicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Unit test for WorkspaceIndicator — the only Milestone-1 behaviour that spans
 * files and exercises the documented robustness guards (see .claude/rules/
 * robustness.md). It is testable headless because the indicator only depends on
 * QtQuick + Kirigami and reads desktop state through a duck-typed
 * `virtualDesktopInfo` property — so a plain QtObject stands in for
 * TaskManager.VirtualDesktopInfo with zero Plasma dependencies.
 *
 * main.qml / PlasmoidItem is intentionally NOT tested here: it needs plasmashell,
 * KWin and a session bus, which don't exist under qmltestrunner. See tests/README.md.
 *
 * Run with `make check` (sets QT_QPA_PLATFORM=offscreen so Kirigami initialises
 * without a display).
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager

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

    // Stands in for TaskManager.VirtualDesktopInfo (duck-typed: the indicator only reads
    // .desktopIds and .currentDesktop). Built per test via makeMock(...).
    Component {
        id: vdiMockComponent
        QtObject {
            property var desktopIds: []
            property string currentDesktop: ""
        }
    }

    SignalSpy {
        id: switchSpy
        signalName: "switchRequested"
    }

    // A duck-typed VirtualDesktopInfo mock. Pass a currentDesktop outside desktopIds (the
    // staleUuid) to exercise the transient add/remove state the indicator must tolerate.
    function makeMock(desktopIds, currentDesktop) {
        return createTemporaryObject(vdiMockComponent, testCase, {
            desktopIds: desktopIds,
            currentDesktop: currentDesktop
        });
    }

    // The single point that instantiates the component under test (auto-cleaned).
    function makeIndicator(vdi) {
        return createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdi
        });
    }

    // Collect the WorkspaceDot delegates from the indicator's visual tree. A dot is
    // uniquely identified by its required `modelData` (the desktop UUID) plus the
    // `active` bool — no other item in the tree carries both.
    function collectDots(item, acc) {
        acc = acc || [];
        const kids = item.children;
        for (let i = 0; i < kids.length; i++) {
            const child = kids[i];
            if (child.modelData !== undefined && typeof child.active === "boolean")
                acc.push(child);
            collectDots(child, acc);
        }
        return acc;
    }

    // Find the dot delegate for a given desktop UUID (or null) — used by the
    // reactivity/geometry tests below to locate a specific slot.
    function dotByUuid(indicator, uuid) {
        const dots = collectDots(indicator, []);
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === uuid)
                return dots[i];
        return null;
    }

    // One dot per desktop UUID in the source.
    function test_dotCountMatchesDesktops() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator, "indicator created");
        compare(collectDots(indicator, []).length, ids.length);
    }

    // robustness.md: a null source (transient during desktop add/remove or shell
    // reload) must yield an empty strip, never an error or a stray dot.
    function test_nullSourceProducesNoDots() {
        const indicator = makeIndicator(null);
        verify(indicator, "indicator created");
        compare(collectDots(indicator, []).length, 0);
    }

    // Exactly the dot whose UUID equals currentDesktop is active.
    function test_activeMapping() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        const dots = collectDots(indicator, []);
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
        const dots = collectDots(indicator, []);
        let target = null;
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === ids[0])
                target = dots[i];
        verify(target, "found the first dot");

        target.activated();   // signals are callable — emits without flaky headless mouse sim
        compare(switchSpy.count, 1, "switchRequested fired once");
        compare(switchSpy.signalArguments[0][0], ids[0], "forwarded the clicked UUID");
    }

    // --- Milestone 2: the sliding pill --------------------------------------------

    // activeIndex maps currentDesktop to its position in desktopIds.
    function test_activeIndexMapping() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.activeIndex, 1, "middle desktop (uuid-b) is index 1");
    }

    // The pill is shown only when there is an active slot to highlight.
    function test_pillVisibleWhenActive() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        verify(indicator.pill.visible, "pill is visible when a desktop is current");
    }

    // robustness.md: a null source (transient) yields no active slot, so no pill.
    function test_pillHiddenOnNullSource() {
        const indicator = makeIndicator(null);
        compare(indicator.activeIndex, -1, "no active index without a source");
        verify(!indicator.pill.visible, "pill is hidden with a null source");
    }

    // robustness.md: currentDesktop not (yet) in desktopIds during an add/remove must
    // hide the pill rather than indexing out of range.
    function test_pillHiddenWhenCurrentNotInIds() {
        const indicator = makeIndicator(makeMock(ids, staleUuid));
        compare(indicator.activeIndex, -1, "stale currentDesktop maps to -1");
        verify(!indicator.pill.visible, "pill is hidden when current desktop is unknown");
    }

    // The pill is horizontally centred over the active dot's slot — asserted in
    // derived geometry (no literal px), so it holds across HiDPI / theme metrics.
    function test_pillCenteredOverActiveDot() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        const dots = collectDots(indicator, []);
        let activeDot = null;
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === currentUuid)
                activeDot = dots[i];
        verify(activeDot, "found the active dot");

        const dotCenter = activeDot.mapToItem(indicator, activeDot.width / 2, 0).x;
        const pillCenter = indicator.pill.x + indicator.pill.width / 2;
        fuzzyCompare(pillCenter, dotCenter, 0.5, "pill centre aligns with the active slot centre");
    }

    // The pill is wider than a dot, so the decoupled spacing must keep it clear of the
    // neighbouring dots — it may reach toward them but must never cover them.
    function test_pillDoesNotCoverNeighbours() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        const dots = collectDots(indicator, []);
        const byUuid = {};
        for (let i = 0; i < dots.length; i++)
            byUuid[dots[i].modelData] = dots[i];

        // ids: a(0) b(1, active) c(2). Pill covers b; a and c must stay uncovered.
        const leftNeighbour = byUuid[ids[0]];
        const rightNeighbour = byUuid[ids[2]];
        const leftEdge = indicator.pill.x;
        const rightEdge = indicator.pill.x + indicator.pill.width;
        const leftNeighbourRight = leftNeighbour.mapToItem(indicator, leftNeighbour.width, 0).x;
        const rightNeighbourLeft = rightNeighbour.mapToItem(indicator, 0, 0).x;

        verify(leftEdge >= leftNeighbourRight, "pill does not cover the left neighbour");
        verify(rightEdge <= rightNeighbourLeft, "pill does not cover the right neighbour");
    }

    // The pill follows the colour scheme (Kirigami.Theme.highlightColor), not a literal.
    function test_pillColorFollowsTheme() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.pill.color, Kirigami.Theme.highlightColor, "pill uses the theme highlight colour");
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

    // Switching the current desktop slides the pill onto the new active dot. tryVerify
    // polls so it tolerates the slide animation's duration and sub-pixel rounding.
    function test_switchMovesPill() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);
        const activeDot = dotByUuid(indicator, ids[2]);   // the dot we're about to switch to (it doesn't move)
        const dotCenter = activeDot.mapToItem(indicator, activeDot.width / 2, 0).x;

        vdi.currentDesktop = ids[2];

        tryVerify(function () {
            return Math.abs((indicator.pill.x + indicator.pill.width / 2) - dotCenter) <= 0.5;
        }, 2000, "pill ends up centred over the newly current dot");
    }

    // Adding a desktop (desktopIds grows) adds a dot reactively; the current index is kept.
    function test_addDesktopAddsDot() {
        const vdi = makeMock([ids[0], ids[1]], ids[0]);
        const indicator = makeIndicator(vdi);
        compare(collectDots(indicator, []).length, 2, "two dots initially");

        vdi.desktopIds = [ids[0], ids[1], ids[2]];   // a desktop was appended

        tryVerify(function () {
            return collectDots(indicator, []).length === 3;
        }, 2000, "a third dot appears");
        compare(indicator.activeIndex, 0, "current desktop's index is unchanged by an append");
    }

    // Removing a desktop (desktopIds shrinks) drops a dot; the pill re-tracks the
    // still-current desktop at its new index rather than disappearing.
    function test_removeDesktopRemovesDot() {
        const vdi = makeMock(ids, ids[2]);   // current is the last desktop
        const indicator = makeIndicator(vdi);
        compare(collectDots(indicator, []).length, 3, "three dots initially");

        vdi.desktopIds = [ids[1], ids[2]];   // the first desktop was removed; current survives

        tryVerify(function () {
            return collectDots(indicator, []).length === 2;
        }, 2000, "a dot is removed");
        compare(indicator.activeIndex, 1, "pill re-tracks the surviving current desktop at its new index");
        verify(indicator.pill.visible, "pill stays visible for the surviving current desktop");
    }

    // --- slideEnabled: jump on first placement, animate thereafter ----------------
    // slideEnabled is a one-way latch that gates the slide animation so the FIRST valid
    // placement is an instant jump (no slide-in from x=0 on shell reload) — see the
    // gotcha in CLAUDE.md / WorkspaceIndicator.qml.

    // Created with a valid current desktop: the latch is already set (Component.onCompleted).
    function test_slideEnabledLatchedOnValidStart() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        compare(indicator.slideEnabled, true, "slide latched on a valid initial placement");
    }

    // Created with no active slot, then a source arrives: the latch enables via the
    // onActiveIndexChanged + Qt.callLater deferral path (so the first placement jumps).
    function test_slideEnabledDefersFromInvalidStart() {
        const indicator = makeIndicator(null);   // no source → activeIndex -1
        compare(indicator.slideEnabled, false, "slide disabled while there is no active slot");

        indicator.virtualDesktopInfo = makeMock(ids, currentUuid);   // source populates a frame later
        tryCompare(indicator, "slideEnabled", true, 2000, "slide enables once a valid slot first appears");
    }

    // Once latched true, a transient loss of the active slot (current drops out of ids
    // during an add/remove) must NOT reset the latch back to false.
    function test_slideEnabledIsOneWayLatch() {
        const vdi = makeMock(ids, currentUuid);
        const indicator = makeIndicator(vdi);
        compare(indicator.slideEnabled, true, "latched true at start");

        vdi.currentDesktop = staleUuid;   // current momentarily not in ids
        compare(indicator.activeIndex, -1, "no active slot now");
        wait(0);
        compare(indicator.slideEnabled, true, "slideEnabled never returns to false");
    }

    // First placement is an immediate jump: created already at the LAST desktop, the pill
    // is centred there on the first frame (synchronous — no slide-in from x=0).
    function test_firstPlacementIsImmediate() {
        const indicator = makeIndicator(makeMock(ids, ids[2]));
        const activeDot = dotByUuid(indicator, ids[2]);
        const dotCenter = activeDot.mapToItem(indicator, activeDot.width / 2, 0).x;
        const pillCenter = indicator.pill.x + indicator.pill.width / 2;
        fuzzyCompare(pillCenter, dotCenter, 0.5, "pill is already centred on first placement");
    }

    // --- activeIndex edge cases (data-driven) -------------------------------------
    // activeIndex is the guard the pill's visibility/position hang off; it must be -1 for
    // every transient/invalid state and the correct slot otherwise.
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

    // The implicitWidth reserves a half-pill overhang at each end, so the pill never
    // clips past the strip even at the first or last desktop.
    function test_noClipAtEnds() {
        const many = [ids[0], ids[1], ids[2], "uuid-d", "uuid-e", "uuid-f"];

        const atFirst = makeIndicator(makeMock(many, many[0]));
        verify(atFirst.pill.x >= -0.5, "pill does not clip past the left edge at the first desktop");

        const atLast = makeIndicator(makeMock(many, many[many.length - 1]));
        verify(atLast.pill.x + atLast.pill.width <= atLast.width + 0.5,
               "pill does not clip past the right edge at the last desktop");
    }

    // A single desktop: one dot, active, with the pill centred and visible (no neighbours).
    function test_singleDesktop() {
        const indicator = makeIndicator(makeMock(["uuid-solo"], "uuid-solo"));
        compare(collectDots(indicator, []).length, 1, "exactly one dot");
        compare(indicator.activeIndex, 0, "the only desktop is active");
        verify(indicator.pill.visible, "pill is visible for the single desktop");

        const dot = collectDots(indicator, [])[0];
        const dotCenter = dot.mapToItem(indicator, dot.width / 2, 0).x;
        const pillCenter = indicator.pill.x + indicator.pill.width / 2;
        fuzzyCompare(pillCenter, dotCenter, 0.5, "pill centred on the single dot");
    }

    // The pill has no MouseArea, so a click at its centre must fall THROUGH to the active
    // dot beneath and still emit switchRequested(currentUuid). This is the one test that
    // needs a real synthesized click — direct signal emission would bypass the hit-test
    // that proves click-through works.
    function test_clickThroughPill() {
        const indicator = makeIndicator(makeMock(ids, currentUuid));
        switchSpy.target = indicator;
        switchSpy.clear();

        const p = indicator.pill.mapToItem(indicator, indicator.pill.width / 2, indicator.pill.height / 2);
        mouseClick(indicator, p.x, p.y);

        compare(switchSpy.count, 1, "click through the pill reaches the dot beneath");
        compare(switchSpy.signalArguments[0][0], currentUuid, "the covered (active) desktop's UUID is forwarded");
    }
}
