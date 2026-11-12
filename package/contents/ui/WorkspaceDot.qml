/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One desktop: a dim dot that grows into the highlighted pill while its desktop is current. Sizes,
 * colours and the animation switch come from WorkspaceIndicator; the Kirigami defaults let a dot
 * render on its own in a test.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "logic.mjs" as Logic

Item {
    id: dot

    property bool active: false
    property int dotStyle: Logic.DEFAULTS.dotStyle
    property real dotSize: Kirigami.Units.iconSizes.small / 2
    property real pillSize: Kirigami.Units.iconSizes.small / 2
    property real pillWidth: dot.pillSize * Logic.DEFAULTS.pillWidthFactor
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity
    property bool occupied: false
    property real occupiedOpacity: Logic.DEFAULTS.occupiedOpacity
    property int occupancyStyle: Logic.DEFAULTS.occupancyStyle
    property string desktopName: ""
    property bool showTooltips: Logic.DEFAULTS.showTooltips
    property string tooltipText: ""   // the window list as rich text; empty shows the name alone
    property bool followThemeColors: Logic.DEFAULTS.followThemeColors
    property color activeColor: Kirigami.Theme.highlightColor
    property color inactiveColor: Kirigami.Theme.textColor
    property color occupiedColor: Kirigami.Theme.highlightColor
    property int animationDuration: Logic.DEFAULTS.animationDuration
    property bool vertical: false   // the pill grows down rather than across
    property bool animate: false    // false until the indicator's first placement, so a reload doesn't animate

    readonly property real longExtent: dot.active ? dot.pillWidth : dot.dotSize
    readonly property real crossExtent: dot.active ? dot.pillSize : dot.dotSize

    // Reading Kirigami.Theme here, not through the colour inputs, re-evaluates on a scheme change.
    readonly property color resolvedActive: dot.followThemeColors ? Kirigami.Theme.highlightColor : dot.activeColor
    readonly property color resolvedInactive: dot.followThemeColors ? Kirigami.Theme.textColor : dot.inactiveColor
    readonly property color resolvedOccupied: dot.followThemeColors ? Kirigami.Theme.highlightColor : dot.occupiedColor
    readonly property int effectiveOccupancyStyle: Logic.effectiveOccupancyStyle(dot.occupancyStyle, dot.dotStyle)
    readonly property int body: Logic.dotBody(dot.active, dot.occupied, dot.effectiveOccupancyStyle)
    readonly property var bodyColors: ({ active: dot.resolvedActive, inactive: dot.resolvedInactive, occupied: dot.resolvedOccupied })
    // Grouped once here, so the opacity binding, which re-runs on every hover, allocates nothing.
    readonly property var bodyOpacities: ({ inactive: dot.inactiveOpacity, hover: dot.hoverOpacity, occupied: dot.occupiedOpacity })
    readonly property bool showInnerDot: Logic.innerDotVisible(dot.active, dot.occupied, dot.effectiveOccupancyStyle)
    readonly property bool showRing: Logic.ringOverlayVisible(dot.active, dot.occupied, dot.effectiveOccupancyStyle)

    readonly property bool ringStyle: Logic.isRingStyle(dot.dotStyle)
    readonly property bool hasRing: Logic.dotHasRing(dot.dotStyle, dot.body)
    readonly property bool bodyIsHollow: Logic.dotBodyIsHollow(dot.dotStyle, dot.body)
    readonly property bool ringFilled: Logic.dotBodyFilled(dot.dotStyle, dot.body)
    // The occupied opacity goes into the fill, so the ring's border stays opaque.
    readonly property color filledBodyColor: Qt.rgba(dot.resolvedOccupied.r, dot.resolvedOccupied.g, dot.resolvedOccupied.b, dot.occupiedOpacity)

    readonly property int effectiveDuration: Logic.effectiveDuration(dot.animationDuration, Kirigami.Units.longDuration)
    readonly property bool morphEnabled: dot.animate && dot.effectiveDuration > 0

    readonly property alias hovered: mouseArea.containsMouse
    signal activated   // a click or an assistive technology's press

    // Every dot is the same kind of button to a screen reader, so the checked state tells the current one apart.
    Accessible.role: Accessible.Button
    Accessible.name: dot.desktopName
    Accessible.checkable: true
    Accessible.checked: dot.active
    Accessible.onPressAction: dot.activated()

    // Follows the animating capsule, so the line reflows through the morph.
    implicitWidth: capsule.width
    implicitHeight: capsule.height

    // A tooltip per dot: one around the whole strip showed over the pill and broke the applet's sizing.
    PlasmaCore.ToolTipArea {
        id: tooltip
        anchors.fill: parent
        active: dot.showTooltips && dot.desktopName !== ""
        mainText: dot.desktopName
        subText: dot.tooltipText
        textFormat: Text.RichText

        // Each size is a ternary over inputs, never its own or the parent's geometry, so it can't loop
        // with implicitWidth.
        Rectangle {
            id: capsule
            width: dot.vertical ? dot.crossExtent : dot.longExtent
            height: dot.vertical ? dot.longExtent : dot.crossExtent
            radius: Math.min(capsule.width, capsule.height) / 2
            anchors.centerIn: parent
            color: dot.bodyIsHollow ? "transparent"
                 : dot.ringFilled ? dot.filledBodyColor
                 : Logic.dotColor(dot.body, dot.bodyColors)
            border.width: dot.hasRing ? Logic.ringThickness(dot.dotSize) : 0
            border.color: dot.resolvedInactive
            // The ring style draws at full opacity for crisp rings; its occupied fill carries its own.
            opacity: dot.ringStyle ? 1.0 : Logic.dotOpacity(dot.body, mouseArea.containsMouse, dot.bodyOpacities)

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
            Behavior on border.width {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: dot.effectiveDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: dot.effectiveDuration
                }
            }
        }

        // Behind a Loader, so a dot without a marker builds neither one. A sibling of the capsule rather
        // than its child, to keep an opacity of its own.
        Loader {
            id: occupancyOverlay
            anchors.centerIn: capsule
            active: dot.showInnerDot || dot.showRing
            sourceComponent: dot.showRing ? ringComponent : innerDotComponent
        }

        Component {
            id: innerDotComponent
            Rectangle {
                width: Logic.innerDotDiameter(dot.dotSize)
                height: width
                radius: width / 2
                color: dot.resolvedOccupied
                opacity: dot.occupiedOpacity
            }
        }

        Component {
            id: ringComponent
            Rectangle {
                width: dot.dotSize
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Logic.ringThickness(dot.dotSize)
                border.color: dot.resolvedOccupied
                opacity: dot.occupiedOpacity
            }
        }

        // The left button only, so a right-click reaches the applet's context menu.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: dot.activated()
        }
    }
}
