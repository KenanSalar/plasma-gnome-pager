/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The current desktop on one screen. Plasma 6.7 offers it as a method with a change signal rather than
 * a property, and a binding to a method evaluates once, so currentDesktop is recomputed on the signals.
 */
pragma ComponentBehavior: Bound

import QtQuick

import "logic.mjs" as Logic

Item {
    id: resolver

    property var virtualDesktopInfo: null
    property string screenName: ""

    // The global current desktop while there is no screen or no per-screen API.
    property string currentDesktop: ""

    function updateCurrentDesktop() {
        const vdi = resolver.virtualDesktopInfo;
        const globalCurrent = vdi?.currentDesktop ?? "";
        let perScreen;
        if (vdi && resolver.screenName && typeof vdi.currentDesktopByScreenName === "function")
            perScreen = vdi.currentDesktopByScreenName(resolver.screenName);
        resolver.currentDesktop = Logic.resolveCurrentDesktop(perScreen, globalCurrent);
    }

    // Without ignoreUnknownSignals, so a typo in these always-present handlers still warns.
    Connections {
        target: resolver.virtualDesktopInfo
        function onCurrentDesktopChanged() {
            resolver.updateCurrentDesktop();
        }
        function onDesktopIdsChanged() {
            resolver.updateCurrentDesktop();
        }
    }
    // Plasma 6.7 and later only.
    Connections {
        target: resolver.virtualDesktopInfo
        ignoreUnknownSignals: true
        function onCurrentDesktopForScreenChanged(screenName) {
            if (screenName === resolver.screenName)
                resolver.updateCurrentDesktop();
        }
    }
    onScreenNameChanged: resolver.updateCurrentDesktop()
    onVirtualDesktopInfoChanged: resolver.updateCurrentDesktop()
    Component.onCompleted: resolver.updateCurrentDesktop()
}
