/*
 * GNOME Workspace Switcher — main.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Root PlasmoidItem: owns the virtual-desktop data source (read) and the KWin
 * DBus helpers (write), and renders the dot strip inline in the panel.
 */
pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

// Public, stable imports only (intentionally no org.kde.plasma.private.*):
import org.kde.taskmanager as TaskManager        // VirtualDesktopInfo (read state)
import org.kde.plasma.workspace.dbus as DBus     // KWin DBus (switch/add/remove)

PlasmoidItem {
    id: root

    Plasmoid.icon: "user-desktop"

    // A pager renders inline in the panel. Plasma will not instantiate ANY
    // representation unless a fullRepresentation is defined (a compact-only applet
    // renders nothing at all), so the dot strip IS the full representation and we
    // force it to always show inline — never a popup or the default compact icon —
    // via preferredRepresentation. (verified against develop.kde.org/docs/plasma/widget)
    preferredRepresentation: fullRepresentation
    fullRepresentation: WorkspaceIndicator {
        virtualDesktopInfo: vdi
        onSwitchRequested: uuid => root.switchTo(uuid)
    }

    // Form-factor helpers consumed by WorkspaceIndicator (Row vs Column) later.
    readonly property bool isHorizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Reactive, read-only desktop state. Bind to it; never cache — it updates when
    // desktops change by ANY means (keyboard, another pager, settings). Writing
    // (switch/add/remove) goes through KWin DBus below. (see virtual-desktops.md)
    TaskManager.VirtualDesktopInfo {
        id: vdi
    }

    // Switch to a desktop by UUID via the VirtualDesktopManager "current" property.
    // Async fire-and-forget: issue the call and let `vdi` report the new state.
    function switchTo(uuid) {
        if (!uuid) {
            return; // robustness: desktopIds/currentDesktop can be transiently empty
        }
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/VirtualDesktopManager",
            "iface": "org.freedesktop.DBus.Properties",
            "member": "Set",
            "arguments": [new DBus.string("org.kde.KWin.VirtualDesktopManager"), new DBus.string("current"), new DBus.variant(uuid)]
        });

        // Proven legacy fallback (1-based index) if the property-set path ever fails:
        // DBus.SessionBus.asyncCall({
        //     "service": "org.kde.KWin", "path": "/KWin", "iface": "org.kde.KWin",
        //     "member": "setCurrentDesktop", "arguments": [ new DBus.int32(uiIndex + 1) ]
        // });
    }

    // TODO(M3): addDesktop() / removeDesktop(uuid) helpers + wire the contextual
    //           actions below to them (createDesktop / removeDesktop DBus).

    // Right-click menu — entries are wired; handlers are stubs for now.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Add Desktop")
            icon.name: "list-add"
            // TODO(impl): root.addDesktop()
            onTriggered: {}
        },
        PlasmaCore.Action {
            text: i18n("Remove Last Desktop")
            icon.name: "list-remove"
            // TODO(impl): root.removeDesktop(last uuid)
            onTriggered: {}
        }
    ]
}
