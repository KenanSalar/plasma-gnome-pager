/*
 * GNOME Workspace Switcher — WorkspaceDot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * One workspace element. GNOME-style REFLOW model: this element IS the workspace — there is
 * no separate overlay. When inactive it is a dim circle; when active it morphs into a wider
 * highlighted "capsule" (the pill). Switching desktops thus morphs two elements at once — the
 * old active shrinks back to a dot while the new one grows into a capsule — and the parent Row
 * reflows around them. Because every element is a real, uniformly-spaced Row child, the capsule
 * can never overlap or clip a neighbour (no overhang/clearance math is needed); see
 * WorkspaceIndicator.qml.
 *
 * Three states drive the look:
 *  - inactive:        dim circle, inactive colour @ inactiveOpacity, dotSize across.
 *  - inactive+hover:  brightened to hoverOpacity (Logic.dotOpacity); hover affects inactive only.
 *  - active:          capsule, active colour @ full opacity, pillWidth along the MAJOR axis
 *                     (width on a horizontal strip, height on a vertical one — `vertical`).
 *
 * Colour follows the colour scheme by default (active = Kirigami.Theme.highlightColor, inactive =
 * textColor); when followThemeColors is false the configured activeColor/inactiveColor are used
 * instead (Logic.dotColor). The morph (the major-axis length + colour + opacity) animates via
 * Behaviors, gated by `animate` so the FIRST placement is instant (the active element is already a
 * capsule on frame 0 — no grow-in on shell reload) and by effectiveDuration > 0 (the configured
 * animationDuration, or the themed default; 0 when "reduce animations" is on → instant). Each
 * element also carries its own PlasmaCore.ToolTipArea showing `desktopName` on hover.
 *
 * Sizing/colour/animation come in as properties from the indicator (one source of truth, fed from
 * plasmoid.configuration via main.qml), with Kirigami-derived defaults so a dot still renders
 * standalone and under qmltestrunner.
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
    property real dotSize: Kirigami.Units.iconSizes.small / 2   // inactive circle diameter
    property real pillWidthFactor: 3.5                          // active capsule length, as a multiple of a dot
    readonly property real pillWidth: dot.dotSize * dot.pillWidthFactor
    property real inactiveOpacity: 0.45
    property real hoverOpacity: 0.8                             // dimensionless ratio
    property string desktopName: ""                            // shown in the tooltip
    property bool showTooltips: true
    // Colours. When followThemeColors is true (default) the element follows the colour scheme
    // (active = highlight, inactive = text); when false it uses activeColor/inactiveColor. The
    // defaults are the theme colours so a standalone/headless dot is unchanged. (Logic.dotColor.)
    property bool followThemeColors: true
    property color activeColor: Kirigami.Theme.highlightColor
    property color inactiveColor: Kirigami.Theme.textColor
    // Configured morph duration in ms (0 = follow the theme). Resolved with the reduce-animations
    // guard into effectiveDuration below.
    property int animationDuration: 0
    // Major-axis orientation, supplied by the indicator (one source of truth). false =
    // horizontal panel (the capsule widens); true = vertical panel (the capsule grows tall).
    property bool vertical: false
    // Morph gate, latched by the indicator after the first valid placement so the active
    // element does not "grow in" from a dot on first render / shell reload.
    property bool animate: false

    // The element's extent along the MAJOR (strip) axis: a capsule when active, a dot
    // otherwise. The cross axis is always dotSize, so the rounded ends stay circular both ways.
    readonly property real longExtent: dot.active ? dot.pillWidth : dot.dotSize

    // The morph duration actually used: the configured animationDuration, or the themed default
    // when unset (0), and 0 whenever "reduce animations" is on (Kirigami.Units.longDuration === 0
    // always wins). One source of truth for the four Behavior durations below. (Logic.effectiveDuration.)
    readonly property int effectiveDuration: Logic.effectiveDuration(dot.animationDuration, Kirigami.Units.longDuration)

    // Whether the morph Behaviors below run: only after the first placement (animate) AND when
    // animations are enabled (effectiveDuration > 0; reduce-animations → 0 → instant). One source
    // of truth for the four identical Behavior gates.
    readonly property bool morphEnabled: dot.animate && dot.effectiveDuration > 0

    // True while the pointer is over the element (qml.md: expose internals via alias).
    readonly property alias hovered: mouseArea.containsMouse

    // Emitted on click; the indicator turns this into a switch request.
    signal activated

    // Footprint advertised to the positioner tracks the (possibly animating) capsule on BOTH
    // axes, so the strip reflows smoothly as the element morphs — horizontally the width grows,
    // vertically the height grows; the cross axis stays a dot thick in either orientation.
    implicitWidth: capsule.width
    implicitHeight: capsule.height

    // Tooltip over the whole element. Wrapping the content (rather than a sibling) is the
    // canonical usage and lets the ToolTipArea track hover even though the inner MouseArea is
    // also hover-enabled. Gated by showTooltips and a non-empty name (no empty tooltips during
    // the transient state where names lag ids — robustness.md).
    PlasmaCore.ToolTipArea {
        id: tooltip
        anchors.fill: parent
        active: dot.showTooltips && dot.desktopName !== ""
        mainText: dot.desktopName

        // The dot/capsule. Inactive: a dim circle (width == height == dotSize). Active: a longer
        // highlighted capsule along the major axis (pillWidth) while the cross axis stays dotSize.
        // The size bindings are independent ternaries (no dependence on parent/own geometry), so
        // there is no loop with implicitWidth/Height: capsule.width/height. radius is pinned to the
        // constant cross-axis half-thickness (dotSize/2) so the ends stay stadium-round in BOTH
        // orientations (height/2 would round a tall vertical capsule into a lozenge).
        Rectangle {
            id: capsule
            width: dot.vertical ? dot.dotSize : dot.longExtent
            height: dot.vertical ? dot.longExtent : dot.dotSize
            radius: dot.dotSize / 2
            anchors.centerIn: parent
            color: Logic.dotColor(dot.active, dot.followThemeColors, Kirigami.Theme.highlightColor, Kirigami.Theme.textColor, dot.activeColor, dot.inactiveColor)
            opacity: Logic.dotOpacity(dot.active, mouseArea.containsMouse, dot.inactiveOpacity, dot.hoverOpacity)

            // The morph. Gated by dot.morphEnabled (off on first placement, and when the user has
            // turned animations off → instant). Initial property values never animate, so an
            // element born active is a capsule on frame 0 regardless.
            // One morph Behavior per axis (width for a horizontal strip, height for a vertical
            // one); in a given orientation only the major-axis dimension ever changes, so exactly
            // one of these fires. Both share the same morphEnabled gate.
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

        // The whole element is the click and hover target (so clicking anywhere on the active
        // capsule switches). acceptedButtons stays LeftButton (default) so a right-click falls
        // through to the applet for its context menu.
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: dot.activated()
        }
    }
}
