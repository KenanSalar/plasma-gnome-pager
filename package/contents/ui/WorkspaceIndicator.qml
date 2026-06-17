/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip. Milestone 1: a horizontal Row of WorkspaceDot, one per virtual
 * desktop, bound live to VirtualDesktopInfo (read state) and reporting clicks up
 * to main.qml (which owns the KWin DBus write). The Item root is kept as the
 * container that Milestone 2's sliding "pill" overlay will sit inside.
 *
 * Data + DBus live in main.qml (see CLAUDE.md architecture); this component only
 * lays out and forwards intent — it never caches or switches desktops itself.
 *
 * TODO(M2):  pill overlay Rectangle over the active dot, animated via Behavior.
 * TODO(M3):  MouseArea { onWheel: ... } scroll-to-switch (gated by config).
 * TODO(M4):  Row (horizontal) vs Column (vertical) on Plasmoid.formFactor.
 * TODO(M5):  size/spacing from plasmoid.configuration.* instead of Kirigami.Units.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: indicator

    // Reactive read-only desktop state, supplied by main.qml (a VirtualDesktopInfo).
    // NOT `required`: Plasma instantiates representations via its own loader, where a
    // required property on the representation root fails creation silently. Default
    // null + guard instead (robustness.md: guard transient null state).
    property var virtualDesktopInfo: null

    // Raised when a dot is clicked; main.qml turns the UUID into a KWin switch.
    signal switchRequested(string uuid)

    // Advertise size so the panel allocates space (count × dotSize + gaps).
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            // desktopIds can be momentarily null/empty during a desktop add/remove
            // or shell reload — guard before binding it as the model (robustness.md).
            model: indicator.virtualDesktopInfo ? indicator.virtualDesktopInfo.desktopIds : []

            delegate: WorkspaceDot {
                id: workspaceDot

                required property string modelData
                required property int index

                desktopId: workspaceDot.modelData
                desktopIndex: workspaceDot.index
                active: indicator.virtualDesktopInfo && indicator.virtualDesktopInfo.currentDesktop === workspaceDot.modelData

                onActivated: indicator.switchRequested(workspaceDot.modelData)
            }
        }
    }
}
