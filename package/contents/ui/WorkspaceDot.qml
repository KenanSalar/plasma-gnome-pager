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
 *  - inactive:        dim circle, Kirigami.Theme.textColor @ inactiveOpacity, width dotSize.
 *  - inactive+hover:  brightened to hoverOpacity (Logic.dotOpacity); hover affects inactive only.
 *  - active:          capsule, Kirigami.Theme.highlightColor @ full opacity, width pillWidth.
 *
 * The morph (width + colour + opacity) animates via Behaviors, gated by `animate` so the FIRST
 * placement is instant (the active element is already a capsule on frame 0 — no grow-in on shell
 * reload) and by Kirigami.Units.longDuration > 0 (reduce-animations → instant). Each element also
 * carries its own PlasmaCore.ToolTipArea showing `desktopName` on hover.
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
    property real dotSize: Kirigami.Units.iconSizes.small / 2   // inactive circle diameter
    property real pillWidthFactor: 2.5                          // active capsule length, as a multiple of a dot
    readonly property real pillWidth: dot.dotSize * dot.pillWidthFactor
    property real inactiveOpacity: 0.45
    property real hoverOpacity: 0.8                             // dimensionless ratio; M5-configurable
    property string desktopName: ""                            // shown in the tooltip
    property bool showTooltips: true
    // Morph gate, latched by the indicator after the first valid placement so the active
    // element does not "grow in" from a dot on first render / shell reload.
    property bool animate: false

    // Whether the morph Behaviors below run: only after the first placement (animate) AND when
    // animations are enabled (longDuration > 0; reduce-animations → 0 → instant). One source of
    // truth for the three identical Behavior gates.
    readonly property bool morphEnabled: dot.animate && Kirigami.Units.longDuration > 0

    // True while the pointer is over the element (qml.md: expose internals via alias).
    readonly property alias hovered: mouseArea.containsMouse

    // Emitted on click; the indicator turns this into a switch request.
    signal activated

    // Footprint advertised to the Row tracks the (possibly animating) capsule width, so the
    // Row reflows smoothly as the element morphs. Height is uniform (a dot tall) for all states.
    implicitWidth: capsule.width
    implicitHeight: dot.dotSize

    // Tooltip over the whole element. Wrapping the content (rather than a sibling) is the
    // canonical usage and lets the ToolTipArea track hover even though the inner MouseArea is
    // also hover-enabled. Gated by showTooltips and a non-empty name (no empty tooltips during
    // the transient state where names lag ids — robustness.md).
    PlasmaCore.ToolTipArea {
        id: tooltip
        anchors.fill: parent
        active: dot.showTooltips && dot.desktopName !== ""
        mainText: dot.desktopName

        // The dot/capsule. Inactive: a dim circle (width == height == dotSize). Active: a wider
        // highlighted capsule (width == pillWidth, radius keeps the stadium ends). The width
        // binding is an independent ternary so there is no loop with implicitWidth: capsule.width.
        Rectangle {
            id: capsule
            width: dot.active ? dot.pillWidth : dot.dotSize
            height: dot.dotSize
            radius: height / 2
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: dot.active ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
            opacity: Logic.dotOpacity(dot.active, mouseArea.containsMouse, dot.inactiveOpacity, dot.hoverOpacity)

            // The morph. Gated by dot.morphEnabled (off on first placement, and when the user has
            // turned animations off → instant). Initial property values never animate, so an
            // element born active is a capsule on frame 0 regardless.
            Behavior on width {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on color {
                enabled: dot.morphEnabled
                ColorAnimation {
                    duration: Kirigami.Units.longDuration
                }
            }
            Behavior on opacity {
                enabled: dot.morphEnabled
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
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
