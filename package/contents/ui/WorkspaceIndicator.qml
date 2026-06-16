/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * SCAFFOLD ONLY. Renders a placeholder so the widget loads and claims panel space.
 *
 * TODO(impl):
 *   - Row (horizontal panel) / Column (vertical panel) of WorkspaceDot via a
 *     Repeater bound to vdi.desktopIds.
 *   - A single "pill" overlay Rectangle positioned over the active dot, animated
 *     with Behavior on x / Behavior on width for the GNOME slide effect.
 *   - MouseArea { onWheel: ... } to scroll between desktops (gated by config).
 *   - Spacing/size driven by plasmoid.configuration.* and Kirigami.Units.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: indicator

    // Placeholder footprint so the empty scaffold is visible in the panel / plasmawindowed.
    implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.largeSpacing * 2
    implicitHeight: Kirigami.Units.iconSizes.small

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "user-desktop"
        opacity: 0.5
    }
}
