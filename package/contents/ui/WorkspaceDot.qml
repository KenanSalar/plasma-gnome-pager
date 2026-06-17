/*
 * GNOME Workspace Switcher — WorkspaceDot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One GNOME-style workspace dot. Milestone 1: a clickable dot that highlights
 * when it is the active desktop. The full GNOME look (dim dots + sliding pill)
 * arrives in Milestone 2; config-driven colors/opacity in Milestone 5.
 *
 * TODO(M2):  inactive opacity / pill styling refinements.
 * TODO(M3):  hover brighten on containsMouse.
 * TODO(M5):  honour plasmoid.configuration.followThemeColors / activeColor /
 *            inactiveColor / inactiveOpacity instead of the theme defaults below.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: dot

    // Input supplied by WorkspaceIndicator's Repeater delegate.
    property bool active: false

    // Emitted on click; the indicator turns this into a switch request.
    signal activated

    implicitWidth: Kirigami.Units.iconSizes.small / 2
    implicitHeight: implicitWidth
    radius: height / 2

    // Declarative bindings keep the look reactive to theme + active changes.
    color: dot.active ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
    opacity: dot.active ? 1.0 : 0.45

    MouseArea {
        anchors.fill: parent
        onClicked: dot.activated()
    }
}
