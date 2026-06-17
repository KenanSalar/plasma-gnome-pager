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
import "../package/contents/ui" as Pager

TestCase {
    id: testCase
    name: "WorkspaceIndicator"
    when: windowShown
    width: 200
    height: 50

    // Stands in for TaskManager.VirtualDesktopInfo (duck-typed: the indicator only
    // reads .desktopIds and .currentDesktop). Three desktops, the middle one current.
    QtObject {
        id: vdiMock
        property var desktopIds: ["uuid-a", "uuid-b", "uuid-c"]
        property string currentDesktop: "uuid-b"
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
        const indicator = createTemporaryObject(indicatorComponent, testCase, { virtualDesktopInfo: vdiMock });
        verify(indicator, "indicator created");
        compare(collectDots(indicator, []).length, vdiMock.desktopIds.length);
    }

    // robustness.md: a null source (transient during desktop add/remove or shell
    // reload) must yield an empty strip, never an error or a stray dot.
    function test_nullSourceProducesNoDots() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, { virtualDesktopInfo: null });
        verify(indicator, "indicator created");
        compare(collectDots(indicator, []).length, 0);
    }

    // Exactly the dot whose UUID equals currentDesktop is active.
    function test_activeMapping() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, { virtualDesktopInfo: vdiMock });
        const dots = collectDots(indicator, []);
        let activeCount = 0;
        for (let i = 0; i < dots.length; i++) {
            compare(dots[i].active, dots[i].modelData === vdiMock.currentDesktop,
                    "active flag matches currentDesktop for " + dots[i].modelData);
            if (dots[i].active)
                activeCount++;
        }
        compare(activeCount, 1, "exactly one dot is active");
    }

    // Clicking a dot must forward switchRequested(uuid) up to main.qml unchanged.
    function test_clickForwardsUuid() {
        const indicator = createTemporaryObject(indicatorComponent, testCase, { virtualDesktopInfo: vdiMock });
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
}
