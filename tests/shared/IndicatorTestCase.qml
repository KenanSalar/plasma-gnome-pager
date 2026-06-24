/*
 * Plasma Gnome Pager — tests/shared/IndicatorTestCase.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shared base TestCase for the WorkspaceIndicator integration suite. The indicator tests were split by
 * concern into several tst_indicator_*.qml files (morph / layout / input / content); each derives from this
 * so the fixtures live in ONE place: the component-under-test factory, the VirtualDesktopInfo doubles (the
 * shared VdiMock + a pre-6.7 legacy double), the switchRequested spy, and the dot-tree locators.
 *
 * Headless-testable: the indicator depends only on QtQuick/Layouts/Kirigami (+ logic.js) and reads desktop
 * state through a duck-typed `virtualDesktopInfo` (a VdiMock stands in for VirtualDesktopInfo). main.qml/
 * PlasmoidItem is NOT tested here (needs plasmashell/KWin/a session bus). Lives in tests/shared/ so
 * qmltestrunner IMPORTS but never EXECUTES it (only tests/unit + tests/integration are run as -input).
 */
import QtQuick
import QtTest
import "../../package/contents/ui" as Pager
import "treewalk.js" as TreeWalk
import "elements.js" as Elements

TestCase {
    id: root
    when: windowShown
    visible: true   // so children report effective `visible` (else it's always false)
    width: 200
    height: 50

    // Shared fixtures so the desktop set and UUIDs live in one place (the tests assert
    // against these, not against scattered literals).
    readonly property var ids: ["uuid-a", "uuid-b", "uuid-c"]
    readonly property string currentUuid: "uuid-b"   // ids[1], the middle desktop
    readonly property string staleUuid: "uuid-gone"  // intentionally NOT in ids

    // Larger desktop sets for the multi-row grid / scale-to-fit / many-desktops cases (no scattered literals).
    readonly property var fourIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d"]
    readonly property var fiveIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d", "uuid-e"]
    readonly property var sixIds: ["uuid-a", "uuid-b", "uuid-c", "uuid-d", "uuid-e", "uuid-f"]

    // Build an N-desktop UUID list for the many-desktops cases.
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

    // Stands in for TaskManager.VirtualDesktopInfo — the shared, canonical double (duck-typed to the
    // members the indicator reads; see tests/shared/VdiMock.qml). Built per test via makeMock(...);
    // per-screen tests set perScreenCurrent and emit currentDesktopForScreenChanged.
    Component {
        id: vdiMockComponent
        VdiMock {}
    }

    // A pre-6.7 VirtualDesktopInfo: the desktop set + global current, but NO currentDesktopByScreenName
    // method, so the indicator's `typeof … === "function"` guard must fall back to the global current
    // (the graceful-degradation path for an older Plasma — robustness.md). It DOES carry the per-screen
    // signal so the indicator's Connections stays warning-free; only the METHOD is absent, which is what
    // the typeof guard tests. Built via makeLegacyVdi(...).
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

    // The indicator's switchRequested spy, exposed to derived pages by name (an inner id would not cross
    // the file boundary). A test re-targets it per case: switchSpy.target = indicator; switchSpy.clear().
    SignalSpy {
        id: switchRequestedSpy
        signalName: "switchRequested"
    }
    property alias switchSpy: switchRequestedSpy

    // A duck-typed VirtualDesktopInfo mock. A currentDesktop outside desktopIds (the staleUuid) exercises
    // the transient add/remove state; desktopNames is optional (needed only by the tooltip tests).
    function makeMock(desktopIds, currentDesktop, desktopNames, desktopLayoutRows) {
        return createTemporaryObject(vdiMockComponent, root, {
            desktopIds: desktopIds,
            currentDesktop: currentDesktop,
            desktopNames: desktopNames || [],
            desktopLayoutRows: desktopLayoutRows || 1
        });
    }

    // A pre-6.7 VirtualDesktopInfo double (no per-screen method) for the graceful-degradation test.
    function makeLegacyVdi(props) {
        return createTemporaryObject(legacyVdiComponent, root, props || {});
    }

    // The single point that instantiates the component under test (auto-cleaned). Extra props can be
    // passed for the interaction tests; virtualDesktopInfo is always set.
    function makeIndicator(vdi, props) {
        const p = props || {};
        p.virtualDesktopInfo = vdi;
        return createTemporaryObject(indicatorComponent, root, p);
    }

    // Collect the WorkspaceDot delegates from the indicator's visual tree (locators shared with the unit
    // tier, tests/shared/elements.js).
    function collectDots(indicator) {
        return TreeWalk.collect(indicator, Elements.isDot);
    }

    // Find the dot delegate for a given desktop UUID (or null).
    function dotByUuid(indicator, uuid) {
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            if (dots[i].modelData === uuid)
                return dots[i];
        return null;
    }

    // The dots in flat desktop order (sorted by globalIndex), so geometry tests can walk neighbours
    // correctly across multiple grid lines.
    function dotsByIndex(indicator) {
        const dots = collectDots(indicator);
        dots.sort((a, b) => a.globalIndex - b.globalIndex);
        return dots;
    }

    // The dim circle/capsule Rectangle inside a given dot (shared locator). Used by the colour test.
    function circleOf(dot) {
        return Elements.circleOf(dot);
    }

    // The trailing edge of the last dot must land within the allocation on the named axis — the
    // scale-to-fit invariant (never overflow). `axis` is explicit ("x"/"y"), since the cross-fit tests
    // constrain the axis OPPOSITE the strip orientation.
    function lastElementFits(indicator, axis) {
        const dots = dotsByIndex(indicator);
        const last = dots[dots.length - 1];
        return axis === "y"
            ? last.mapToItem(indicator, 0, last.height).y <= indicator.height + 0.5
            : last.mapToItem(indicator, last.width, 0).x <= indicator.width + 0.5;
    }
}
