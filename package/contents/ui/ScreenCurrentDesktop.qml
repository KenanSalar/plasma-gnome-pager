/*
 * Plasma Gnome Pager — ScreenCurrentDesktop.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Resolves the current desktop FOR ONE SCREEN, extracted from WorkspaceIndicator so the per-screen
 * logic is one single-responsibility, headless-testable unit (tst_screencurrentdesktop). A non-visual
 * zero-size Item (it hosts a Connections, which needs a QQuickItem host — same pattern as the other
 * controllers here).
 *
 * Plasma 6.7 lets each output show a different current desktop via
 * VirtualDesktopInfo.currentDesktopByScreenName, which is a METHOD + change SIGNAL, not a notifying
 * property — so a plain binding would evaluate once and never refresh. Instead currentDesktop is a
 * mutable source-of-truth recomputed imperatively in updateCurrentDesktop(), driven by the Connections
 * below; the indicator binds activeIndex off it.
 *
 * screenName is read on the indicator (a placed visual Item — the QtQuick Screen attached property only
 * reflects the output for an on-screen item) and injected IN, so this never reads Screen itself. The
 * perScreen-vs-global decision is the pure Logic.resolveCurrentDesktop (prefer per-screen, fall back to
 * global), so it degrades to single-desktop behaviour when the feature is off, the screen is unknown,
 * or the API is absent (older Plasma — the typeof guard).
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

    // Recompute on every external change: the global current, THIS screen's current, a desktop
    // add/remove (a screen's current may have been removed), the source swapping in, or this panel
    // moving to another output. "Bind, don't cache": every external change re-resolves.
    Connections {
        target: resolver.virtualDesktopInfo
        function onCurrentDesktopChanged() {
            resolver.updateCurrentDesktop();
        }
        function onCurrentDesktopForScreenChanged(screenName) {
            if (screenName === resolver.screenName)
                resolver.updateCurrentDesktop();
        }
        function onDesktopIdsChanged() {
            resolver.updateCurrentDesktop();
        }
    }
    onScreenNameChanged: resolver.updateCurrentDesktop()
    onVirtualDesktopInfoChanged: resolver.updateCurrentDesktop()
    Component.onCompleted: resolver.updateCurrentDesktop()
}
