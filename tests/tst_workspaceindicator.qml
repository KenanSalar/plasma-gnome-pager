/*
 * GNOME Workspace Switcher — tst_workspaceindicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
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
import "../package/contents/ui" as Pager

TestCase {
    id: testCase
    name: "WorkspaceIndicator"
    when: windowShown
    visible: true   // so children report effective `visible` (else it's always false)
    width: 200
    height: 50

    // Stands in for TaskManager.VirtualDesktopInfo (duck-typed: the indicator only
    // reads .desktopIds and .currentDesktop). Three desktops, the middle one current.
    QtObject {
        id: vdiMock
        property var desktopIds: ["uuid-a", "uuid-b", "uuid-c"]
        property string currentDesktop: "uuid-b"
    }

    // A source whose currentDesktop is not among desktopIds — a transient state during
    // a desktop add/remove. The indicator must treat it as "no active slot".
    QtObject {
        id: vdiMockStale
        property var desktopIds: ["uuid-a", "uuid-b", "uuid-c"]
        property string currentDesktop: "uuid-gone"
    }

    Component {
        id: indicatorComponent
        Pager.WorkspaceIndicator {}
    }

    SignalSpy {
        id: switchSpy
        signalName: "switchRequested"
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

    // One dot per desktop UUID in the source.
    function test_dotCountMatchesDesktops() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        verify(indicator, "indicator created");
        compare(collectDots(indicator, []).length, vdiMock.desktopIds.length);
    }

    // robustness.md: a null source (transient during desktop add/remove or shell
    // reload) must yield an empty strip, never an error or a stray dot.
    function test_nullSourceProducesNoDots() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: null
        });
        verify(indicator, "indicator created");
        compare(collectDots(indicator, []).length, 0);
    }

    // Exactly the dot whose UUID equals currentDesktop is active.
    function test_activeMapping() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        const dots = collectDots(indicator, []);
        let activeCount = 0;
        for (let i = 0; i < dots.length; i++) {
            compare(dots[i].active, dots[i].modelData === vdiMock.currentDesktop, "active flag matches currentDesktop for " + dots[i].modelData);
            if (dots[i].active)
                activeCount++;
        }
        compare(activeCount, 1, "exactly one dot is active");
    }

    // Clicking a dot must forward switchRequested(uuid) up to main.qml unchanged.
    function test_clickForwardsUuid() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        switchSpy.target = indicator;
        switchSpy.clear();

        // Pick an inactive dot so a stale/no-op binding couldn't accidentally pass.
        const dots = collectDots(indicator, []);
        let target = null;
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === "uuid-a")
                target = dots[i];
        verify(target, "found the uuid-a dot");

        target.activated();   // signals are callable — emits without flaky headless mouse sim
        compare(switchSpy.count, 1, "switchRequested fired once");
        compare(switchSpy.signalArguments[0][0], "uuid-a", "forwarded the clicked UUID");
    }

    // --- Milestone 2: the sliding pill --------------------------------------------

    // activeIndex maps currentDesktop to its position in desktopIds.
    function test_activeIndexMapping() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        compare(indicator.activeIndex, 1, "middle desktop (uuid-b) is index 1");
    }

    // The pill is shown only when there is an active slot to highlight.
    function test_pillVisibleWhenActive() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        verify(indicator.pill.visible, "pill is visible when a desktop is current");
    }

    // robustness.md: a null source (transient) yields no active slot, so no pill.
    function test_pillHiddenOnNullSource() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: null
        });
        compare(indicator.activeIndex, -1, "no active index without a source");
        verify(!indicator.pill.visible, "pill is hidden with a null source");
    }

    // robustness.md: currentDesktop not (yet) in desktopIds during an add/remove must
    // hide the pill rather than indexing out of range.
    function test_pillHiddenWhenCurrentNotInIds() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMockStale
        });
        compare(indicator.activeIndex, -1, "stale currentDesktop maps to -1");
        verify(!indicator.pill.visible, "pill is hidden when current desktop is unknown");
    }

    // The pill is horizontally centred over the active dot's slot — asserted in
    // derived geometry (no literal px), so it holds across HiDPI / theme metrics.
    function test_pillCenteredOverActiveDot() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        const dots = collectDots(indicator, []);
        let activeDot = null;
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === vdiMock.currentDesktop)
                activeDot = dots[i];
        verify(activeDot, "found the active dot");

        const dotCenter = activeDot.mapToItem(indicator, activeDot.width / 2, 0).x;
        const pillCenter = indicator.pill.x + indicator.pill.width / 2;
        fuzzyCompare(pillCenter, dotCenter, 0.5, "pill centre aligns with the active slot centre");
    }

    // The pill is wider than a dot, so the decoupled spacing must keep it clear of the
    // neighbouring dots — it may reach toward them but must never cover them.
    function test_pillDoesNotCoverNeighbours() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        const dots = collectDots(indicator, []);
        const byUuid = {};
        for (let i = 0; i < dots.length; i++)
            byUuid[dots[i].modelData] = dots[i];

        // vdiMock: a(0) b(1, active) c(2). Pill covers b; a and c must stay uncovered.
        const leftEdge = indicator.pill.x;
        const rightEdge = indicator.pill.x + indicator.pill.width;
        const leftNeighbourRight = byUuid["uuid-a"].mapToItem(indicator, byUuid["uuid-a"].width, 0).x;
        const rightNeighbourLeft = byUuid["uuid-c"].mapToItem(indicator, 0, 0).x;

        verify(leftEdge >= leftNeighbourRight, "pill does not cover the left neighbour");
        verify(rightEdge <= rightNeighbourLeft, "pill does not cover the right neighbour");
    }

    // The pill follows the colour scheme (Kirigami.Theme.highlightColor), not a literal.
    function test_pillColorFollowsTheme() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, {
            virtualDesktopInfo: vdiMock
        });
        compare(indicator.pill.color, Kirigami.Theme.highlightColor, "pill uses the theme highlight colour");
    }
}
