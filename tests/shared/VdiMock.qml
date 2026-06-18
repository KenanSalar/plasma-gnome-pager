/*
 * Plasma Gnome Pager — tests/shared/VdiMock.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shared test double for TaskManager.VirtualDesktopInfo. Duck-typed: it exposes exactly the
 * members WorkspaceIndicator reads — .desktopIds, .currentDesktop, .desktopNames,
 * .desktopLayoutRows, and the Plasma 6.7 per-screen current API
 * (.currentDesktopByScreenName(name) + the .currentDesktopForScreenChanged(screenName) signal).
 *
 * Defaults model a single desktop set on one line with the per-screen feature OFF (perScreenCurrent
 * empty → every screen equals the global currentDesktop), so screen-agnostic tests stay valid.
 * Per-screen tests set `perScreenCurrent` and emit `currentDesktopForScreenChanged` to mimic a
 * single output switching. Lives in tests/shared/ so it is the ONE canonical mock (not a tst_*.qml,
 * so qmltestrunner never runs it as a test); a test imports the directory (`import "../shared"`)
 * and instantiates `VdiMock {}`.
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
