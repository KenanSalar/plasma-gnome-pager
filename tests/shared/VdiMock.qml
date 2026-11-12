/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The stand-in for TaskManager.VirtualDesktopInfo, duck-typed to the members the code reads. By default
 * every screen shows the global current desktop, so a test that ignores screens needs nothing more.
 */
import QtQuick

QtObject {
    property var desktopIds: []
    property string currentDesktop: ""
    property var desktopNames: []
    property int desktopLayoutRows: 1

    // Screen name to current desktop; a screen missing from it shows the global one.
    property var perScreenCurrent: ({})
    signal currentDesktopForScreenChanged(string screenName)
    function currentDesktopByScreenName(name) {
        return perScreenCurrent[name] !== undefined ? perScreenCurrent[name] : currentDesktop;
    }

    // As libtaskmanager does when KWin moves a desktop: both lists re-sorted in place, so neither of
    // their changed signals fires, then desktopPositionsChanged alone.
    signal desktopPositionsChanged()
    function reorder(order) {
        const names = order.map(id => desktopNames[desktopIds.indexOf(id)]);
        desktopIds.splice(0, desktopIds.length, ...order);
        if (desktopNames.length)
            desktopNames.splice(0, desktopNames.length, ...names);
        desktopPositionsChanged();
    }
}
