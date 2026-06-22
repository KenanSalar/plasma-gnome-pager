/*
 * Plasma Gnome Pager — tests/shared/VdiMock.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shared test double for TaskManager.VirtualDesktopInfo. Duck-typed: exposes exactly the members
 * WorkspaceIndicator reads (.desktopIds/.currentDesktop/.desktopNames/.desktopLayoutRows + the Plasma 6.7
 * per-screen API). Defaults model one desktop set with the per-screen feature OFF (every screen == the
 * global currentDesktop), so screen-agnostic tests stay valid; per-screen tests set `perScreenCurrent` and
 * emit `currentDesktopForScreenChanged`. In tests/shared/ as the ONE canonical mock (not a tst_*.qml).
 */
import QtQuick

QtObject {
    property var desktopIds: []
    property string currentDesktop: ""
    property var desktopNames: []
    property int desktopLayoutRows: 1   // KWin's row count; 1 = single line (default)

    // Maps a screen name -> its current desktop UUID; an absent screen falls back to the global
    // currentDesktop. Empty by default (the per-screen feature OFF).
    property var perScreenCurrent: ({})
    signal currentDesktopForScreenChanged(string screenName)
    function currentDesktopByScreenName(name) {
        return perScreenCurrent[name] !== undefined ? perScreenCurrent[name] : currentDesktop;
    }
}
