/*
 * GNOME Workspace Switcher — WorkspaceDot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One GNOME-style workspace slot. Milestone 2: a slot (the footprint a desktop occupies
 * in the strip) holding a centred dim circle. Every dot looks the same dim circle — the
 * active desktop is rendered by the single sliding "pill" overlay that WorkspaceIndicator
 * draws on top of the active dot, NOT by recolouring the dot. The slot defaults to the
 * circle size; the indicator sets the spacing and the (wider) pill geometry around it.
 *
 * `active` is set by the indicator and drives the test invariant; it intentionally does
 * NOT change the dot's appearance — the pill owns the active look — and it also suppresses
 * the M3 hover-brighten on the current dot (hovering the dot under the pill must not flicker
 * the dim circle, since the pill already highlights it).
 *
 * M3 adds hover feedback and a tooltip:
 *  - the circle brightens to `hoverOpacity` while the pointer is over the slot. The
 *    brighten/suppress decision lives in logic.js (Logic.dotOpacity) so it is unit-tested
 *    without a Plasma session; the dot just binds to it and animates the result.
 *  - a PlasmaCore.ToolTipArea wraps the slot and shows this desktop's `desktopName` on
 *    hover (gated by `showTooltips`). The tooltip lives per-dot — anchored to the slot it
 *    describes — rather than once at strip level, so it points at the right dot and follows
 *    the panel edge. This is the canonical Plasma idiom (icons/tasks wrap their content in a
 *    ToolTipArea); it loads and tracks hover under headless qmltestrunner.
 *
 * Sizing/colour come in as properties from the indicator (one source of truth), with
 * Kirigami-derived defaults so a dot still renders standalone and under qmltestrunner.
 *
 * TODO(M5):  honour plasmoid.configuration.followThemeColors / activeColor /
 *            inactiveColor / inactiveOpacity instead of the theme defaults below.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore        // ToolTipArea (themed, panel-aware tooltip)

import "logic.js" as Logic

Item {
    id: dot

    // Inputs supplied by WorkspaceIndicator's Repeater delegate (with sane defaults).
    property bool active: false
    property real dotSize: Kirigami.Units.iconSizes.small / 2   // visible circle diameter
    property real slotWidth: dotSize                            // footprint in the strip; defaults to the circle size
    property real inactiveOpacity: 0.45
    property real hoverOpacity: 0.8                             // dimensionless ratio; M5-configurable
    property string desktopName: ""                            // shown in the tooltip
    property bool showTooltips: true

    // True while the pointer is over the slot (qml.md: expose internals via alias).
    readonly property alias hovered: mouseArea.containsMouse

    // Emitted on click; the indicator turns this into a switch request.
    signal activated

    // Footprint advertised to the Row: a uniform slot, dotSize tall.
    implicitWidth: slotWidth
    implicitHeight: dotSize

    // Tooltip over the whole slot. Wrapping the content (rather than a sibling) is the
    // canonical usage and lets the ToolTipArea track hover even though the inner MouseArea
    // is also hover-enabled. Gated by showTooltips and a non-empty name (no empty tooltips
    // during the transient state where names lag ids — robustness.md).
    PlasmaCore.ToolTipArea {
        id: tooltip
        anchors.fill: parent
        active: dot.showTooltips && dot.desktopName !== ""
        mainText: dot.desktopName

        // The dim circle, centred in the slot. The active state is the pill overlay drawn by
        // the indicator over this slot, so the circle's only own variation is the hover
        // brighten — suppressed while `active` (Logic.dotOpacity) so the dot under the pill
        // stays steady.
        Rectangle {
            id: circle
            width: dot.dotSize
            height: dot.dotSize
            radius: dot.dotSize / 2
            x: (dot.width - dot.dotSize) / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Kirigami.Theme.textColor
            opacity: Logic.dotOpacity(dot.active, mouseArea.containsMouse, dot.inactiveOpacity, dot.hoverOpacity)

            // Smooth hover fade. Disabled (instant) when the user has turned animations off
            // (longDuration === 0), mirroring the pill's guard in WorkspaceIndicator.qml.
            Behavior on opacity {
                enabled: Kirigami.Units.longDuration > 0
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                }
            }
        }

        // The whole slot is the click and hover target (bigger, GNOME-style hit area).
        // acceptedButtons stays LeftButton (default) so a right-click falls through to the
        // applet for its context menu.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: dot.activated()
        }
    }
}
