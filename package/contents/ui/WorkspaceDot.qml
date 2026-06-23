/*
 * Plasma Gnome Pager — WorkspaceDot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One workspace element (GNOME-style REFLOW model — see CLAUDE.md "Visual model"): the element IS
 * the workspace, no overlay. Inactive = dim circle; active = a wider highlighted capsule (the pill).
 * Three states: inactive / inactive+hover (Logic.dotOpacity) / active. Colour, sizing, and the morph
 * arrive as properties from the indicator, with Kirigami-derived defaults so a dot renders standalone
 * and under qmltestrunner.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore        // ToolTipArea

import "logic.js" as Logic

Item {
    id: dot

    // Inputs supplied by WorkspaceIndicator's Repeater delegate (with sane defaults).
    property bool active: false
    property real dotSize: Kirigami.Units.iconSizes.small / 2
    property real pillSize: Kirigami.Units.iconSizes.small / 2  // active-pill thickness, sized independently of the dot
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor   // capsule length / pill thickness
    readonly property real pillWidth: dot.pillSize * dot.pillWidthFactor
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity
    property string desktopName: ""                            // tooltip mainText
    property bool showTooltips: Logic.DEFAULTS.showTooltips
    property string tooltipText: ""                            // tooltip subText: HTML window list, pre-formatted by main.qml (empty = name-only)
    // Colours follow the scheme when followThemeColors (default), else activeColor/inactiveColor (Logic.dotColor).
    property bool followThemeColors: Logic.DEFAULTS.followThemeColors
    property color activeColor: Kirigami.Theme.highlightColor
    property color inactiveColor: Kirigami.Theme.textColor
    property int animationDuration: Logic.DEFAULTS.animationDuration  // ms; 0 = follow theme (resolved by effectiveDuration)
    property bool vertical: false   // major axis: false = horizontal panel (widen), true = vertical (grow tall)
    property bool animate: false    // morph gate, latched by the indicator after first valid placement (no grow-in on reload)

    // Extent along the MAJOR (strip) axis and the CROSS axis: capsule when active, dot otherwise.
    readonly property real longExtent: dot.active ? dot.pillWidth : dot.dotSize
    readonly property real crossExtent: dot.active ? dot.pillSize : dot.dotSize

    // Morph duration: configured value, else themed default, and 0 when "reduce animations" is on
    // (Kirigami.Units.longDuration === 0 always wins). One source of truth for the Behaviors below.
    readonly property int effectiveDuration: Logic.effectiveDuration(dot.animationDuration, Kirigami.Units.longDuration)
    readonly property bool morphEnabled: dot.animate && dot.effectiveDuration > 0

    readonly property alias hovered: mouseArea.containsMouse
    signal activated   // emitted on click; the indicator turns it into a switch request

    // Accessibility: announced to Orca etc. as a button named after the desktop, checkable/checked
    // mirroring `active` so an AT can tell WHICH dot is current; press routes through activated()
    // (same path as a click). Kept on the element so a11y stays headless-testable. See CLAUDE.md.
    Accessible.role: Accessible.Button
    Accessible.name: dot.desktopName
    Accessible.checkable: true
    Accessible.checked: dot.active
    Accessible.onPressAction: dot.activated()

    // Footprint tracks the (possibly animating) capsule on both axes so the strip reflows smoothly.
    implicitWidth: capsule.width
    implicitHeight: capsule.height

    // Per-dot tooltip (wrapping the content is the canonical usage). Gated by showTooltips + a
    // non-empty name (no empty tooltips while names lag ids — robustness.md).
    PlasmaCore.ToolTipArea {
        id: tooltip
        anchors.fill: parent
        active: dot.showTooltips && dot.desktopName !== ""
        mainText: dot.desktopName
        subText: dot.tooltipText
        textFormat: Text.RichText   // window list is an HTML <ul>, like the stock pager

        // The dot/capsule. radius is min(width,height)/2 — orientation-agnostic stadium ends that
        // never round a long capsule into a lozenge. Size bindings are independent ternaries (no
        // dependence on own/parent geometry), so no loop with implicitWidth/Height.
        Rectangle {
            id: capsule
            width: dot.vertical ? dot.crossExtent : dot.longExtent
            height: dot.vertical ? dot.longExtent : dot.crossExtent
            radius: Math.min(capsule.width, capsule.height) / 2
            anchors.centerIn: parent
            color: Logic.dotColor(dot.active, dot.followThemeColors, Kirigami.Theme.highlightColor, Kirigami.Theme.textColor, dot.activeColor, dot.inactiveColor)
            opacity: Logic.dotOpacity(dot.active, mouseArea.containsMouse, dot.inactiveOpacity, dot.hoverOpacity)

            // Morph, gated by morphEnabled (off on first placement / when animations are disabled).
            // The major-axis dimension always morphs; the cross axis morphs too when the pill is sized
            // independently of the dots (pillSize != dotSize), so one OR both of width/height fire.
            Behavior on width {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: dot.effectiveDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: dot.effectiveDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                enabled: dot.morphEnabled
                ColorAnimation {
                    duration: dot.effectiveDuration
                }
            }
            Behavior on opacity {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: dot.effectiveDuration
                }
            }
        }

        // Click/hover target. acceptedButtons stays LeftButton (default) so a right-click falls
        // through to the applet's context menu.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: dot.activated()
        }
    }
}
