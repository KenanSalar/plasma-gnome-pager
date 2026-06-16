/*
 * GNOME Workspace Switcher — main.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * SCAFFOLD ONLY — structure is wired up, behavior is not implemented yet.
 * Implementation TODOs are marked inline.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Public, stable imports only (intentionally no org.kde.plasma.private.*):
// TODO(impl): import org.kde.taskmanager              // VirtualDesktopInfo (read state)
// TODO(impl): import org.kde.plasma.workspace.dbus as DBus  // KWin DBus (switch/add/remove)

PlasmoidItem {
    id: root

    Plasmoid.icon: "user-desktop"

    // A pager renders inline in the panel, so the compact representation IS the widget.
    preferredRepresentation: compactRepresentation
    compactRepresentation: WorkspaceIndicator {}

    // Form-factor helpers consumed by WorkspaceIndicator (Row vs Column) later.
    readonly property bool isHorizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // ---------------------------------------------------------------------------
    // TODO(impl): virtual-desktop data source (reactive, never cached)
    //   VirtualDesktopInfo { id: vdi }   // exposes desktopIds, currentDesktop, numberOfDesktops, desktopNames
    //
    // TODO(impl): DBus helper functions targeting org.kde.KWin.VirtualDesktopManager
    //   function switchTo(uuid)   { /* set "current" property to uuid */ }
    //   function addDesktop()     { /* createDesktop(position, name) */ }
    //   function removeDesktop(u) { /* removeDesktop(uuid) */ }
    // ---------------------------------------------------------------------------

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
