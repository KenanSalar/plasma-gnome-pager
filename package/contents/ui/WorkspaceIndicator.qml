/*
 * Plasma Gnome Pager — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip (GNOME REFLOW model). Layout + scroll + wiring only: delegates size math to
 * IndicatorMetrics and the per-screen current to ScreenCurrentDesktop, binds live to VirtualDesktopInfo,
 * reports clicks/scroll via switchRequested. Imports no org.kde.plasma.*, so it stays headless-testable.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

Item {
    id: indicator

    // Reactive read-only desktop state, supplied by main.qml. NOT `required` — Plasma's representation loader fails creation SILENTLY on that; null + guard instead.
    property var virtualDesktopInfo: null

    // Null-safe live views. The desktop SET is global; only "which is current" is per-screen (below).
    readonly property var desktopIds: virtualDesktopInfo?.desktopIds ?? []
    readonly property var desktopNames: virtualDesktopInfo?.desktopNames ?? []

    // Per-desktop tooltip subText (window list), index-aligned with desktopIds. Default [] → name-only tooltip.
    property var desktopTooltips: []

    // This panel's output (KWin connector name, e.g. "DP-1") from the Screen attached property so it reflects THIS monitor. Tests override; "" → global.
    property string screenName: Screen.name

    // This panel's output RECT in the virtual-desktop space (Screen has no `geometry`), read by main.qml to
    // drive per-screen occupancy. Tests override; a zero rect → occupancy degrades to global (single-monitor look).
    property rect screenRect: Qt.rect(Screen.virtualX, Screen.virtualY, Screen.width, Screen.height)

    // The current desktop FOR THIS SCREEN (Plasma 6.7 per-output), resolved by ScreenCurrentDesktop.
    readonly property string currentDesktop: screenCurrent.currentDesktop

    ScreenCurrentDesktop {
        id: screenCurrent
        virtualDesktopInfo: indicator.virtualDesktopInfo
        screenName: indicator.screenName
    }

    // Behaviour flags, supplied by main.qml (defaults match the schema).
    property bool enableScroll: Logic.DEFAULTS.enableScroll
    property bool scrollWrap: Logic.DEFAULTS.scrollWrap
    property bool invertScroll: Logic.DEFAULTS.invertScroll   // flip the wheel-sign → direction mapping
    property bool showTooltips: Logic.DEFAULTS.showTooltips

    // Panel orientation. false = horizontal row (also the Planar/floating default); true = vertical column.
    property bool vertical: false

    // When true on a vertical panel, lay the grid out in KWin's orientation (rows top-to-bottom) instead of
    // transposing it to run down the panel (the GNOME-reflow default). No effect on a horizontal panel.
    property bool matchDesktopGrid: Logic.DEFAULTS.matchDesktopGrid

    // Effective grid orientation: vertical panel AND not matching KWin's grid. ALL grid geometry below (the two
    // Grid flows, the metrics axis, the Layout hints, the dot's capsule axis) keys off THIS, not the raw `vertical`.
    readonly property bool gridVertical: vertical && !matchDesktopGrid

    // Running total of hi-res/touchpad wheel deltas; whole notches become steps (the remainder carries).
    property real wheelAccumulator: 0
    readonly property int wheelNotchDelta: Logic.DEFAULTS.wheelNotchDelta

    readonly property int desktopCount: desktopIds.length

    // KWin's grid row count, read live (null-guarded, >= 1). We MIRROR KWin rather than add a setting, so "Rows" re-lays out reactively.
    readonly property int desktopRows: virtualDesktopInfo?.desktopLayoutRows > 0 ? virtualDesktopInfo.desktopLayoutRows : 1

    // Desktops per line (columns = ceil(count / rows)) and the row-major split into lines.
    readonly property int perLine: Logic.gridColumns(desktopCount, desktopRows)
    readonly property var lines: Logic.chunk(desktopIds, perLine)
    readonly property int lineCount: lines.length

    // Active element index, or -1 for any transient state (empty ids, empty/absent current) → no capsule.
    readonly property int activeIndex: desktopIds.indexOf(currentDesktop)

    // Overall pager look (Logic.DOT_STYLE). The "Filled & ring" style has NO pill, so we neutralize the
    // pill params below: feeding pillWidthFactor=1 + pillSizeRequest=0 makes the metrics AND each dot size
    // every element uniformly (the active extent collapses to dotSize) without touching IndicatorMetrics.
    property int dotStyle: Logic.DEFAULTS.dotStyle
    readonly property bool ringStyle: Logic.isRingStyle(dotStyle)
    readonly property real effPillWidthFactor: ringStyle ? 1.0 : pillWidthFactor
    readonly property int effPillSizeRequest: ringStyle ? 0 : pillSizeRequest

    // Config requests fed to the sizing engine; dotSize/pillSize `0 = auto` resolved in IndicatorMetrics.
    property int dotSizeRequest: Logic.DEFAULTS.dotSize    // px override; 0 = auto
    property int pillSizeRequest: Logic.DEFAULTS.pillSize  // px pill thickness; 0 = auto (match dots)
    property real spacingFactor: Logic.DEFAULTS.spacingFactor      // uniform gap as a multiple of a dot
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor  // active capsule length, × the pill thickness
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity        // inactive-dot hover brighten target

    // Occupied-dot indicator: when showOccupancy, an occupied dot (desktopOccupancy[globalIndex]) is marked per occupancyStyle.
    property bool showOccupancy: Logic.DEFAULTS.showOccupancy
    property var desktopOccupancy: []                              // per-desktop bool[], index-aligned with desktopIds (per-screen, from main.qml)
    property real occupiedOpacity: Logic.DEFAULTS.occupiedOpacity  // marker opacity (all styles)
    property int occupancyStyle: Logic.DEFAULTS.occupancyStyle     // Filled/InnerDot/Ring (Logic.OCCUPANCY)

    // The sizing engine: requests + grid shape + live geometry → effective sizes + extents (forwarded below).
    IndicatorMetrics {
        id: metrics
        dotSizeRequest: indicator.dotSizeRequest
        pillSizeRequest: indicator.effPillSizeRequest   // ring style: 0 → pill thickness == dot (no pill)
        spacingFactor: indicator.spacingFactor
        pillWidthFactor: indicator.effPillWidthFactor   // ring style: 1 → active extent == dot (no pill)
        availableMajor: indicator.gridVertical ? indicator.height : indicator.width
        availableCross: indicator.gridVertical ? indicator.width : indicator.height
        perLine: indicator.perLine
        lineCount: indicator.lineCount
    }

    // Effective (rendered) sizes — scale-to-fit applied; == natural when there is room.
    readonly property real dotSize: metrics.dotSize
    readonly property real pillSize: metrics.pillSize          // effective pill thickness (tracks the dot)
    readonly property real pillWidth: metrics.pillWidth        // active capsule LENGTH (major axis)
    readonly property real dotSpacing: metrics.dotSpacing      // uniform gap between every element
    // Natural/floor extents (geometry-independent — feed the Layout hints; no loop).
    readonly property real naturalDotSize: metrics.naturalDotSize
    readonly property real naturalPillSize: metrics.naturalPillSize
    readonly property real pillThicknessRatio: metrics.pillThicknessRatio
    readonly property real minDotSize: metrics.minDotSize
    readonly property real naturalStripLength: metrics.naturalStripLength
    readonly property real floorStripLength: metrics.floorStripLength
    readonly property real naturalCrossThickness: metrics.naturalCrossThickness
    readonly property real floorCrossThickness: metrics.floorCrossThickness

    // Colour + animation config, passed straight through to each dot (the indicator draws nothing itself).
    property bool followThemeColors: Logic.DEFAULTS.followThemeColors
    property color activeColor: Kirigami.Theme.highlightColor
    property color inactiveColor: Kirigami.Theme.textColor
    property color occupiedColor: Kirigami.Theme.highlightColor   // occupied-marker colour (custom; theme accent when following the scheme)
    property int animationDuration: Logic.DEFAULTS.animationDuration   // ms; 0 = follow the theme

    // Raised on a click or scroll; main.qml turns the UUID into a KWin switch.
    signal switchRequested(string uuid)

    // Raised when the ALREADY-CURRENT desktop's dot (the pill) is clicked/pressed; main.qml maps it to the
    // configured pill-click action. Scroll never raises this (handleWheel only ever emits switchRequested).
    signal activeClicked()

    // Wheel → switch. Thin wrapper; the branching (notch accumulation, clamp/wrap, -1 ignore) is in logic.js and unit-tested.
    function handleWheel(angleDeltaY: real) {
        if (!indicator.enableScroll)
            return;
        const acc = Logic.accumulateWheel(indicator.wheelAccumulator, angleDeltaY, indicator.wheelNotchDelta);
        indicator.wheelAccumulator = acc.remainder;
        if (acc.steps === 0)
            return;   // sub-notch motion accumulated; nothing to do yet
        // Default: wheel up (+) → previous desktop; down (−) → next, so negate. invertScroll keeps the sign.
        const dir = indicator.invertScroll ? acc.steps : -acc.steps;
        const next = Logic.stepIndex(indicator.activeIndex, indicator.desktopIds.length, dir, indicator.scrollWrap);
        if (next < 0 || next === indicator.activeIndex)
            return;   // empty/unknown source, or a clamped no-op at an end
        const uuid = indicator.desktopIds[next];
        if (!uuid)
            return;   // transient empty id (robustness.md: guard before use)
        indicator.switchRequested(uuid);
    }

    // Size hints. Major axis: preferred==max==naturalStripLength, min==floorStripLength (panel can compress
    // → dots scale to fit). Cross axis: preferred==natural, max==-1 (fill thickness), min==floor. Swaps with `gridVertical`.
    implicitWidth: gridVertical ? naturalCrossThickness : naturalStripLength
    implicitHeight: gridVertical ? naturalStripLength : naturalCrossThickness
    Layout.minimumWidth: gridVertical ? floorCrossThickness : floorStripLength
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: gridVertical ? -1 : naturalStripLength
    Layout.minimumHeight: gridVertical ? floorStripLength : floorCrossThickness
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: gridVertical ? naturalStripLength : -1

    // Gate the morph so the FIRST valid placement is instant (no grow-in on reload), later switches animate.
    // ScreenCurrentDesktop (a child) resolves currentDesktop in its onCompleted first, so activeIndex is valid here.
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

    // Scroll-to-switch. This MouseArea sits BEHIND the dots, accepts no buttons/hover, so clicks/hover pass through while a wheel propagates here.
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => indicator.handleWheel(wheel.angleDelta.y)
    }

    // Two nested positioners mirror KWin's grid: OUTER stacks lines on the cross axis, INNER the dots on the major axis (one 2-D Grid would fatten a column).
    Grid {
        id: strip
        anchors.centerIn: parent
        spacing: indicator.dotSpacing
        rows: indicator.gridVertical ? 1 : -1
        columns: indicator.gridVertical ? -1 : 1

        Repeater {
            // `lines` is [] while the source is transiently null/empty, so the outer Repeater is empty.
            model: indicator.lines

            delegate: Grid {
                id: lineStrip

                required property var modelData    // this line's UUIDs (a row-major chunk)
                required property int index        // line index (KWin row)

                spacing: indicator.dotSpacing
                rows: indicator.gridVertical ? -1 : 1
                columns: indicator.gridVertical ? 1 : -1
                // Centre every element on the CROSS axis: the line is as thick as its tallest element (the capsule when pillSize > dotSize).
                verticalItemAlignment: indicator.gridVertical ? Grid.AlignTop : Grid.AlignVCenter
                horizontalItemAlignment: indicator.gridVertical ? Grid.AlignHCenter : Grid.AlignLeft

                Repeater {
                    model: lineStrip.modelData

                    delegate: WorkspaceDot {
                        id: workspaceDot

                        required property string modelData
                        required property int index

                        // Position in the flat desktopIds/desktopNames: earlier lines are full at perLine.
                        readonly property int globalIndex: lineStrip.index * indicator.perLine + workspaceDot.index

                        vertical: indicator.gridVertical
                        dotStyle: indicator.dotStyle
                        dotSize: indicator.dotSize
                        pillSize: indicator.pillSize                  // == dotSize in ring mode (no pill)
                        pillWidthFactor: indicator.effPillWidthFactor // == 1 in ring mode (active extent == dot)
                        inactiveOpacity: indicator.inactiveOpacity
                        hoverOpacity: indicator.hoverOpacity
                        // Gating on showOccupancy here keeps a stale/short desktopOccupancy array harmless when the feature is off.
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

                        // Each dot's tooltip name + window-list subText (|| "" guards the transient frame where names/tooltips lag ids).
                        desktopName: indicator.desktopNames[workspaceDot.globalIndex] || ""
                        tooltipText: indicator.desktopTooltips[workspaceDot.globalIndex] || ""
                        showTooltips: indicator.showTooltips

                        // Clicking the current desktop's pill runs the configured action; any other dot switches.
                        onActivated: workspaceDot.active ? indicator.activeClicked() : indicator.switchRequested(workspaceDot.modelData)
                    }
                }
            }
        }
    }
}
