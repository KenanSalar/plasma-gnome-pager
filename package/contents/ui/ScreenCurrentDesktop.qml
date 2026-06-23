/*
 * Plasma Gnome Pager — ScreenCurrentDesktop.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Resolves the current desktop FOR ONE SCREEN (Plasma 6.7 per-output), extracted from WorkspaceIndicator
 * (unit-tested by tst_screencurrentdesktop). currentDesktopByScreenName is a METHOD + change SIGNAL, not a
 * notifying property, so currentDesktop is recomputed imperatively (a plain binding evaluates once). The
 * prefer-per-screen / fall-back-to-global decision is pure Logic.resolveCurrentDesktop. See CLAUDE.md.
 */
pragma ComponentBehavior: Bound

import QtQuick

import "logic.js" as Logic

Item {
    id: resolver

    // Inputs (injected by WorkspaceIndicator).
    property var virtualDesktopInfo: null
    property string screenName: ""

    // Output: the current-desktop UUID for screenName (the global current when there is no per-screen info).
    property string currentDesktop: ""

    function updateCurrentDesktop() {
        const vdi = resolver.virtualDesktopInfo;
        const globalCurrent = vdi?.currentDesktop ?? "";
        let perScreen;   // stays undefined unless we have a screen AND the 6.7 API
        if (vdi && resolver.screenName && typeof vdi.currentDesktopByScreenName === "function")
            perScreen = vdi.currentDesktopByScreenName(resolver.screenName);
        resolver.currentDesktop = Logic.resolveCurrentDesktop(perScreen, globalCurrent);
    }

    // Recompute on every external change (global current, this screen's current, a desktop add/remove, the
    // source swapping in, or this panel moving outputs). "Bind, don't cache." The always-present signals
    // keep their own block (no ignoreUnknownSignals) so a typo here still warns.
    Connections {
        target: resolver.virtualDesktopInfo
        function onCurrentDesktopChanged() {
            resolver.updateCurrentDesktop();
        }
        function onDesktopIdsChanged() {
            resolver.updateCurrentDesktop();
        }
    }
    // The per-screen current signal is Plasma 6.7+ only; on 6.5/6.6 it is absent, so ignoreUnknownSignals
    // keeps the Connections quiet (no "no matching signal" warning) — the resolver already degrades to the
    // global current via the typeof guard in updateCurrentDesktop().
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
