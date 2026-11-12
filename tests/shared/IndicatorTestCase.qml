/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The base of the tst_indicator_* suites, which qmltestrunner imports from here but never runs: the
 * factory, the VirtualDesktopInfo doubles, the signal spies, the desktop fixtures and the locators.
 */
import QtQuick
import QtTest
import "../../package/contents/ui" as Pager
import "treewalk.js" as TreeWalk
import "elements.js" as Elements

TestCase {
    id: root
    when: windowShown
    visible: true   // otherwise every child reports visible as false
    width: 200
    height: 50

    readonly property var ids: ["uuid-a", "uuid-b", "uuid-c"]
    readonly property string currentUuid: "uuid-b"
    readonly property string staleUuid: "uuid-gone"  // in no fixture

    readonly property var fourIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d"]
    readonly property var fiveIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d", "uuid-e"]
    readonly property var sixIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d", "uuid-e", "uuid-f"]

    function manyIds(n) {
        const out = [];
        for (let i = 0; i < n; i++)
            out.push("uuid-" + i);
        return out;
    }

    Component {
        id: indicatorComponent
        Pager.WorkspaceIndicator {}
    }

    Component {
        id: vdiMockComponent
        VdiMock {}
    }

    // Plasma before 6.7 and 6.5: no currentDesktopByScreenName and no desktopPositionsChanged. The
    // per-screen signal stays, so the missing method is the one difference the typeof guard meets.
    Component {
        id: legacyVdiComponent
        QtObject {
            property var desktopIds: []
            property string currentDesktop: ""
            property var desktopNames: []
            property int desktopLayoutRows: 1
            signal currentDesktopForScreenChanged(string screenName)
        }
    }

    // Aliased because an id doesn't reach the deriving files; each test re-targets and clears them.
    SignalSpy {
        id: switchRequestedSpy
        signalName: "switchRequested"
    }
    property alias switchSpy: switchRequestedSpy

    SignalSpy {
        id: activeClickedSpy
        signalName: "activeClicked"
    }
    property alias activeSpy: activeClickedSpy

    // A currentDesktop missing from desktopIds is the state a desktop add or remove passes through.
    function makeMock(desktopIds, currentDesktop, desktopNames, desktopLayoutRows) {
        // Copies, so VdiMock.reorder's in-place re-sort can't leak into the shared fixtures.
        return createTemporaryObject(vdiMockComponent, root, {
            desktopIds: desktopIds.slice(),
            currentDesktop: currentDesktop,
            desktopNames: (desktopNames || []).slice(),
            desktopLayoutRows: desktopLayoutRows || 1
        });
    }

    function makeLegacyVdi(props) {
        return createTemporaryObject(legacyVdiComponent, root, props || {});
    }

    // Any warning inside a test fails it. A binding error during a re-layout, or a Connections
    // handler an older source has no signal for, otherwise only shows up in the log.
    function init() {
        failOnWarning(/.?/);
    }

    function makeIndicator(vdi, props) {
        const p = props || {};
        p.virtualDesktopInfo = vdi;
        return createTemporaryObject(indicatorComponent, root, p);
    }

    function collectDots(indicator) {
        return TreeWalk.collect(indicator, Elements.isDot);
    }

    function dotByUuid(indicator, uuid) {
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === uuid)
                return dots[i];
        return null;
    }

    // In desktop order, so a walk over neighbours crosses from one line to the next.
    function dotsByIndex(indicator) {
        const dots = collectDots(indicator);
        dots.sort((a, b) => a.globalIndex - b.globalIndex);
        return dots;
    }

    function circleOf(dot) {
        return Elements.circleOf(dot);
    }

    function hoverBackgroundOf(indicator) {
        return Elements.hoverBackgroundOf(indicator);
    }

    // Scale-to-fit's promise: the last dot ends inside the allocation. The axis is named because the
    // cross-axis tests constrain the one across the strip.
    function lastElementFits(indicator, axis) {
        const dots = dotsByIndex(indicator);
        const last = dots[dots.length - 1];
        return axis === "y"
            ? last.mapToItem(indicator, 0, last.height).y <= indicator.height + 0.5
            : last.mapToItem(indicator, last.width, 0).x <= indicator.width + 0.5;
    }
}
