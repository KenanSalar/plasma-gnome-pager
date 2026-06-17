/*
 * GNOME Workspace Switcher — WorkspaceDot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One GNOME-style workspace slot. Milestone 2: a slot (the footprint a desktop occupies
 * in the strip) holding a centred dim circle. Every dot looks the same dim circle — the
 * active desktop is rendered by the single sliding "pill" overlay that WorkspaceIndicator
 * draws on top of the active dot, NOT by recolouring the dot. The slot defaults to the
 * circle size; the indicator sets the spacing and the (wider) pill geometry around it.
 *
 * `active` is still set by the indicator (it drives the test invariant and will gate
 * M3 hover-brighten on the current dot) but intentionally no longer changes the dot's
 * appearance in M2 — the pill owns the active look.
 *
 * Sizing/colour come in as properties from the indicator (one source of truth), with
 * Kirigami-derived defaults so a dot still renders standalone and under qmltestrunner.
 *
 * TODO(M3):  hover brighten on containsMouse (suppressed while `active`).
 * TODO(M5):  honour plasmoid.configuration.followThemeColors / activeColor /
 *            inactiveColor / inactiveOpacity instead of the theme defaults below.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: dot

    // Inputs supplied by WorkspaceIndicator's Repeater delegate (with sane defaults).
    property bool active: false
    property real dotSize: Kirigami.Units.iconSizes.small / 2   // visible circle diameter
    property real slotWidth: dotSize                            // footprint in the strip; defaults to the circle size
    property real inactiveOpacity: 0.45

    // Emitted on click; the indicator turns this into a switch request.
    signal activated

    // Footprint advertised to the Row: a uniform slot, dotSize tall.
    implicitWidth: slotWidth
    implicitHeight: dotSize

    // The dim circle, centred in the slot. Always the inactive style in M2 — the
    // active state is the pill overlay drawn by the indicator over this slot.
    Rectangle {
        id: circle
        width: dot.dotSize
        height: dot.dotSize
        radius: dot.dotSize / 2
        x: (dot.width - dot.dotSize) / 2
        anchors.verticalCenter: parent.verticalCenter
        color: Kirigami.Theme.textColor
        opacity: dot.inactiveOpacity
    }

    // The whole slot is the click target (bigger, GNOME-style hit area).
    MouseArea {
        anchors.fill: parent
        onClicked: dot.activated()
    }
}
