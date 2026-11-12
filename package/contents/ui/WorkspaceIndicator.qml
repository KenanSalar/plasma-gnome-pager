/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip: one WorkspaceDot per desktop in KWin's rows, with scrolling and the hover background.
 * IndicatorMetrics sizes it and ScreenCurrentDesktop says which desktop is current on this screen.
 * Nothing from org.kde.plasma is imported, so it loads headless.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "logic.mjs" as Logic

Item {
    id: indicator

    // Not required: Plasma's representation loader fails without a word on a required property.
    property var virtualDesktopInfo: null

    // A reorder re-sorts both lists in place and emits only desktopPositionsChanged, so these read the
    // revision and return a copy. They stay here: read through a child, a dying dot evaluates
    // globalIndex after its line is gone on the next re-layout.
    property int positionsRevision: 0
    readonly property var desktopIds: {
        indicator.positionsRevision;
        return Array.from(indicator.virtualDesktopInfo?.desktopIds ?? []);
    }
    readonly property var desktopNames: {
        indicator.positionsRevision;
        return Array.from(indicator.virtualDesktopInfo?.desktopNames ?? []);
    }

    // desktopPositionsChanged is Plasma 6.5+; ignoreUnknownSignals keeps older shells quiet.
    Connections {
        target: indicator.virtualDesktopInfo
        ignoreUnknownSignals: true
        function onDesktopPositionsChanged() {
            ++indicator.positionsRevision;
        }
    }

    property var desktopTooltips: []

    // The output's name as KWin knows it (DP-1); empty falls back to the global current desktop.
    property string screenName: Screen.name

    // Screen has no geometry property; a zero rect counts windows on every screen.
    property rect screenRect: Qt.rect(Screen.virtualX, Screen.virtualY, Screen.width, Screen.height)

    // Differs from vdi.currentDesktop while KWin switches desktops per screen.
    readonly property string currentDesktop: screenCurrent.currentDesktop

    ScreenCurrentDesktop {
        id: screenCurrent
        virtualDesktopInfo: indicator.virtualDesktopInfo
        screenName: indicator.screenName
    }

    property bool enableScroll: Logic.DEFAULTS.enableScroll
    property bool scrollWrap: Logic.DEFAULTS.scrollWrap
    property bool invertScroll: Logic.DEFAULTS.invertScroll
    property bool showTooltips: Logic.DEFAULTS.showTooltips

    // The panel's orientation, read only by gridVertical.
    property bool vertical: false

    property bool singleLine: Logic.DEFAULTS.singleLine
    property bool matchDesktopGrid: Logic.DEFAULTS.matchDesktopGrid

    // Whether the lines run down the panel, the one orientation every piece of geometry below reads.
    readonly property bool gridVertical: vertical && !matchDesktopGrid

    // Wheel motion short of a notch, carried into the next event.
    property real wheelAccumulator: 0
    readonly property int wheelNotchDelta: Logic.DEFAULTS.wheelNotchDelta

    readonly property int desktopCount: desktopIds.length

    readonly property int desktopRows: singleLine ? 1 : (virtualDesktopInfo?.desktopLayoutRows > 0 ? virtualDesktopInfo.desktopLayoutRows : 1)

    readonly property int perLine: Logic.gridColumns(desktopCount, desktopRows)
    readonly property var lines: Logic.chunk(desktopIds, perLine)
    readonly property int lineCount: lines.length

    // -1 until the current desktop is in the list, which draws no pill.
    readonly property int activeIndex: desktopIds.indexOf(currentDesktop)

    // The ring style has no pill: a pill factor of 1 and an auto pill size make every element a dot,
    // in the metrics and in each dot alike.
    property int dotStyle: Logic.DEFAULTS.dotStyle
    readonly property bool ringStyle: Logic.isRingStyle(dotStyle)
    readonly property real effPillWidthFactor: ringStyle ? 1.0 : pillWidthFactor
    readonly property int effPillSizeRequest: ringStyle ? 0 : pillSizeRequest

    // No clearance while the hover background is off, so the metrics need no flag of their own.
    readonly property real effHoverLengthFactor: showHoverBackground ? hoverLengthFactor : 0
    readonly property real effHoverThicknessFactor: showHoverBackground ? hoverThicknessFactor : 0

    // 0 = auto, resolved by IndicatorMetrics.
    property int dotSizeRequest: Logic.DEFAULTS.dotSize
    property int pillSizeRequest: Logic.DEFAULTS.pillSize
    property real spacingFactor: Logic.DEFAULTS.spacingFactor
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity

    property bool showHoverBackground: Logic.DEFAULTS.showHoverBackground
    property real hoverBackgroundOpacity: Logic.DEFAULTS.hoverBackgroundOpacity
    property real hoverLengthFactor: Logic.DEFAULTS.hoverLengthFactor
    property real hoverThicknessFactor: Logic.DEFAULTS.hoverThicknessFactor
    property color hoverBackgroundColor: Kirigami.Theme.textColor

    property bool pillClickAnywhere: Logic.DEFAULTS.pillClickAnywhere

    property bool showOccupancy: Logic.DEFAULTS.showOccupancy
    property var desktopOccupancy: []   // this screen's, index-aligned with desktopIds
    property real occupiedOpacity: Logic.DEFAULTS.occupiedOpacity
    property int occupancyStyle: Logic.DEFAULTS.occupancyStyle

    IndicatorMetrics {
        id: metrics
        dotSizeRequest: indicator.dotSizeRequest
        pillSizeRequest: indicator.effPillSizeRequest
        spacingFactor: indicator.spacingFactor
        pillWidthFactor: indicator.effPillWidthFactor
        availableMajor: indicator.gridVertical ? indicator.height : indicator.width
        availableCross: indicator.gridVertical ? indicator.width : indicator.height
        perLine: indicator.perLine
        lineCount: indicator.lineCount
        hoverLengthFactor: indicator.effHoverLengthFactor
        hoverThicknessFactor: indicator.effHoverThicknessFactor
    }

    // Rendered sizes, shrunk to fit the panel.
    readonly property real dotSize: metrics.dotSize
    readonly property real pillSize: metrics.pillSize
    readonly property real pillWidth: metrics.pillWidth
    readonly property real dotSpacing: metrics.dotSpacing
    readonly property real lineThickness: metrics.lineThickness
    readonly property real stripLength: metrics.stripLength
    readonly property real crossThickness: metrics.crossThickness
    // Sizes from the settings alone, which the Layout hints read.
    readonly property real naturalDotSize: metrics.naturalDotSize
    readonly property real naturalPillSize: metrics.naturalPillSize
    readonly property real pillThicknessRatio: metrics.pillThicknessRatio
    readonly property real minDotSize: metrics.minDotSize
    readonly property real naturalStripLength: metrics.naturalStripLength
    readonly property real floorStripLength: metrics.floorStripLength
    readonly property real naturalCrossThickness: metrics.naturalCrossThickness
    readonly property real floorCrossThickness: metrics.floorCrossThickness
    // The padded extents feed the hints; the effective padding and the cross extent only the Rectangle.
    readonly property real hoverPadding: metrics.hoverPadding
    readonly property real hoverCrossPadding: metrics.hoverCrossPadding
    readonly property real hoverCrossPaddingEffective: metrics.hoverCrossPaddingEffective
    readonly property real paddedStripLength: metrics.paddedStripLength
    readonly property real paddedCrossThickness: metrics.paddedCrossThickness
    readonly property real hoverCrossExtent: metrics.hoverCrossExtent

    property bool followThemeColors: Logic.DEFAULTS.followThemeColors
    property color activeColor: Kirigami.Theme.highlightColor
    property color inactiveColor: Kirigami.Theme.textColor
    property color occupiedColor: Kirigami.Theme.highlightColor
    property int animationDuration: Logic.DEFAULTS.animationDuration

    // GNOME washes with the text colour; the accent would muddy the pill in front of it.
    readonly property color resolvedHoverBackground: followThemeColors ? Kirigami.Theme.textColor : hoverBackgroundColor
    readonly property int effectiveDuration: Logic.effectiveDuration(animationDuration, Kirigami.Units.longDuration)

    // The dots sit over wheelArea and take the hover from it, so the strip is hovered when either is.
    // A HoverHandler here would never fire: a hover-enabled child ends delivery before its ancestors.
    property int hoveredDotIndex: -1
    readonly property bool hovered: wheelArea.containsMouse || hoveredDotIndex >= 0
    // A dot reports its leave as it's destroyed, so this only covers one that doesn't. The new dot under
    // a still pointer reports no hover until the pointer moves.
    onDesktopIdsChanged: hoveredDotIndex = -1

    signal switchRequested(string uuid)

    // A click on this screen's current desktop, or anywhere with pillClickAnywhere; scrolling never raises it.
    signal activeClicked()

    function handleWheel(angleDeltaY: real) {
        if (!indicator.enableScroll)
            return;
        const acc = Logic.accumulateWheel(indicator.wheelAccumulator, angleDeltaY, indicator.wheelNotchDelta);
        indicator.wheelAccumulator = acc.remainder;
        if (acc.steps === 0)
            return;
        // Wheel up is positive and goes to the previous desktop.
        const dir = indicator.invertScroll ? acc.steps : -acc.steps;
        const step = indicator.scrollWrap ? Logic.wrappedStep : Logic.clampedStep;
        const next = step(indicator.activeIndex, indicator.desktopIds.length, dir);
        if (next < 0 || next === indicator.activeIndex)
            return;
        const uuid = indicator.desktopIds[next];
        if (!uuid)
            return;
        indicator.switchRequested(uuid);
    }

    // Only sizes from the settings, never rendered ones: those would loop through availableCross back
    // into dotSize. A panel that sized the representation by its implicit size alone would hand it a
    // square cell, drawing the dots over the neighbours. The minimum is the bare strip, so a cramped
    // panel squeezes out the hover clearance before the dots shrink.
    implicitWidth: gridVertical ? paddedCrossThickness : paddedStripLength
    implicitHeight: gridVertical ? paddedStripLength : paddedCrossThickness
    Layout.minimumWidth: gridVertical ? floorCrossThickness : floorStripLength
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: gridVertical ? -1 : paddedStripLength
    Layout.minimumHeight: gridVertical ? floorStripLength : floorCrossThickness
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: gridVertical ? paddedStripLength : -1

    // The first placement is instant, so a reload shows the pill already grown; later switches animate.
    // ScreenCurrentDesktop, a child, has resolved currentDesktop by the time this onCompleted runs.
    property bool animate: false
    onActiveIndexChanged: {
        if (activeIndex >= 0 && !animate) {
            Qt.callLater(() => indicator.animate = true);
        }
    }
    Component.onCompleted: {
        if (activeIndex >= 0) {
            animate = true;
        }
    }

    // Takes no input, so it can't come between a dot and the pointer; the clicks it invites are wheelArea's.
    Rectangle {
        id: hoverBackground
        anchors.centerIn: parent
        width: indicator.gridVertical ? indicator.hoverCrossExtent : indicator.width
        height: indicator.gridVertical ? indicator.height : indicator.hoverCrossExtent
        radius: Math.min(width, height) / 2
        color: indicator.resolvedHoverBackground
        opacity: Logic.hoverBackgroundAlpha(indicator.showHoverBackground, indicator.hovered, indicator.hoverBackgroundOpacity)
        visible: opacity > 0

        Behavior on opacity {
            enabled: indicator.effectiveDuration > 0
            NumberAnimation {
                duration: indicator.effectiveDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    // Behind the dots: a wheel over a dot falls through to here, while clicks and hover stay the dot's.
    // A WheelHandler didn't get the wheel reliably in a panel. The right button is never accepted, which
    // leaves the context menu to the applet.
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: indicator.pillClickAnywhere ? Qt.LeftButton : Qt.NoButton
        onWheel: wheel => indicator.handleWheel(wheel.angleDelta.y)
        onClicked: indicator.activeClicked()
    }

    // A Grid per line inside an outer Grid: one two-dimensional Grid would widen the pill's whole column.
    Grid {
        id: strip
        anchors.centerIn: parent
        // Pinned to a line holding the pill: sized by its content it would shrink midway through a switch
        // between lines, and re-centring would drag every dot.
        width: indicator.gridVertical ? indicator.crossThickness : indicator.stripLength
        height: indicator.gridVertical ? indicator.stripLength : indicator.crossThickness
        spacing: indicator.dotSpacing
        rows: indicator.gridVertical ? 1 : -1
        columns: indicator.gridVertical ? -1 : 1

        Repeater {
            model: indicator.lines

            delegate: Grid {
                id: lineStrip

                required property var modelData
                required property int index

                spacing: indicator.dotSpacing
                rows: indicator.gridVertical ? -1 : 1
                columns: indicator.gridVertical ? 1 : -1
                // A pill thicker than the dots makes the line thicker, so the dots centre across it.
                verticalItemAlignment: indicator.gridVertical ? Grid.AlignTop : Grid.AlignVCenter
                horizontalItemAlignment: indicator.gridVertical ? Grid.AlignHCenter : Grid.AlignLeft

                Repeater {
                    model: lineStrip.modelData

                    delegate: WorkspaceDot {
                        id: workspaceDot

                        required property string modelData
                        required property int index

                        // Every line before this one is full.
                        readonly property int globalIndex: lineStrip.index * indicator.perLine + workspaceDot.index

                        vertical: indicator.gridVertical
                        dotStyle: indicator.dotStyle
                        dotSize: indicator.dotSize
                        pillSize: indicator.pillSize
                        pillWidthFactor: indicator.effPillWidthFactor
                        inactiveOpacity: indicator.inactiveOpacity
                        hoverOpacity: indicator.hoverOpacity
                        // Gated here so a stale array does nothing while the markers are off.
                        occupied: indicator.showOccupancy && (indicator.desktopOccupancy[workspaceDot.globalIndex] ?? false)
                        occupiedOpacity: indicator.occupiedOpacity
                        occupancyStyle: indicator.occupancyStyle
                        followThemeColors: indicator.followThemeColors
                        activeColor: indicator.activeColor
                        inactiveColor: indicator.inactiveColor
                        occupiedColor: indicator.occupiedColor
                        animationDuration: indicator.animationDuration
                        active: indicator.currentDesktop === workspaceDot.modelData
                        animate: indicator.animate

                        // Names and tooltips can lag the ids for a frame.
                        desktopName: indicator.desktopNames[workspaceDot.globalIndex] || ""
                        tooltipText: indicator.desktopTooltips[workspaceDot.globalIndex] || ""
                        showTooltips: indicator.showTooltips

                        // Only the indicator knows this screen's current desktop, so it decides what a click means.
                        onActivated: workspaceDot.active ? indicator.activeClicked() : indicator.switchRequested(workspaceDot.modelData)

                        onHoveredChanged: indicator.hoveredDotIndex = Logic.nextHoveredIndex(indicator.hoveredDotIndex, workspaceDot.globalIndex, workspaceDot.hovered)
                    }
                }
            }
        }
    }
}
