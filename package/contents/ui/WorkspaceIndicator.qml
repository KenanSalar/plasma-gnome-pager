/*
 * Plasma Gnome Pager — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip (GNOME REFLOW model — see CLAUDE.md "Representation"/"Visual model"). Layout + scroll +
 * wiring only: delegates size math to IndicatorMetrics and the per-screen current to ScreenCurrentDesktop,
 * binds live to VirtualDesktopInfo (read), reports clicks/scroll via switchRequested. Imports no
 * org.kde.plasma.*, so it stays headless-testable. Layout follows the panel (`vertical`) and KWin's grid
 * (desktopLayoutRows). Size is advertised via Layout.* hints (NOT implicitWidth alone, or the panel gives
 * a square cell and the dots overflow); hints are natural/floor-based only, never the effective size → no loop.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

Item {
    id: indicator

    // Reactive read-only desktop state, supplied by main.qml (a VirtualDesktopInfo). NOT `required`:
    // Plasma's representation loader fails creation SILENTLY on a required root property. Null + guard
    // instead (robustness.md).
    property var virtualDesktopInfo: null

    // Null-safe live views. The desktop SET is global; only "which is current" is per-screen (below).
    readonly property var desktopIds: virtualDesktopInfo?.desktopIds ?? []
    readonly property var desktopNames: virtualDesktopInfo?.desktopNames ?? []

    // Per-desktop tooltip subText (window list), index-aligned with desktopIds, supplied by main.qml.
    // Default [] → each dot falls back to a name-only tooltip.
    property var desktopTooltips: []

    // This panel's output (KWin connector name, e.g. "DP-1"), read live from the placed representation's
    // Screen attached property so it reflects THIS monitor. Tests override it; "" falls back to global.
    property string screenName: Screen.name

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

    // Running total of hi-res/touchpad wheel deltas; whole notches become steps (the remainder carries).
    property real wheelAccumulator: 0
    readonly property int wheelNotchDelta: Logic.DEFAULTS.wheelNotchDelta

    readonly property int desktopCount: desktopIds.length

    // KWin's grid row count, read live (null-guarded, >= 1). We MIRROR KWin's grid rather than add a
    // setting, so changing "Rows" in System Settings re-lays out reactively.
    readonly property int desktopRows: virtualDesktopInfo?.desktopLayoutRows > 0 ? virtualDesktopInfo.desktopLayoutRows : 1

    // Desktops per line (columns = ceil(count / rows)) and the row-major split into lines.
    readonly property int perLine: Logic.gridColumns(desktopCount, desktopRows)
    readonly property var lines: Logic.chunk(desktopIds, perLine)
    readonly property int lineCount: lines.length

    // Active element index, or -1 for any transient state (empty ids, empty/absent current) → no capsule.
    readonly property int activeIndex: desktopIds.indexOf(currentDesktop)

    // Config requests fed to the sizing engine; dotSize/pillSize `0 = auto` resolved in IndicatorMetrics.
    property int dotSizeRequest: Logic.DEFAULTS.dotSize    // px override; 0 = auto
    property int pillSizeRequest: Logic.DEFAULTS.pillSize  // px pill thickness; 0 = auto (match dots)
    property real spacingFactor: Logic.DEFAULTS.spacingFactor      // uniform gap as a multiple of a dot
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor  // active capsule length, × the pill thickness
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity        // inactive-dot hover brighten target

    // The sizing engine: requests + grid shape + live geometry → effective sizes + extents (forwarded below).
    IndicatorMetrics {
        id: metrics
        dotSizeRequest: indicator.dotSizeRequest
        pillSizeRequest: indicator.pillSizeRequest
        spacingFactor: indicator.spacingFactor
        pillWidthFactor: indicator.pillWidthFactor
        availableMajor: indicator.vertical ? indicator.height : indicator.width
        availableCross: indicator.vertical ? indicator.width : indicator.height
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
    property int animationDuration: Logic.DEFAULTS.animationDuration   // ms; 0 = follow the theme

    // Raised on a click or scroll; main.qml turns the UUID into a KWin switch.
    signal switchRequested(string uuid)

    // Wheel → switch. Thin wrapper: the branching (notch accumulation, clamp/wrap, -1 ignore states) is in
    // logic.js and unit-tested.
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

    // Size hints (see file header). Major axis: preferred==max==naturalStripLength, min dropped to
    // floorStripLength (panel can compress → dots scale to fit). Cross axis: preferred==natural, max==-1
    // (fill the panel thickness), min==floor. Natural/floor-based → no loop. Major axis swaps with `vertical`.
    implicitWidth: vertical ? naturalCrossThickness : naturalStripLength
    implicitHeight: vertical ? naturalStripLength : naturalCrossThickness
    Layout.minimumWidth: vertical ? floorCrossThickness : floorStripLength
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: vertical ? -1 : naturalStripLength
    Layout.minimumHeight: vertical ? floorStripLength : floorCrossThickness
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: vertical ? naturalStripLength : -1

    // Gate the morph so the FIRST valid placement is instant (active element already a capsule on frame 0 —
    // no grow-in on reload) and later switches animate. ScreenCurrentDesktop (a child) resolves
    // currentDesktop in its own onCompleted, which runs first, so activeIndex is already valid here.
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

    // Scroll-to-switch over the whole strip. This MouseArea sits BEHIND the dots (declared first), accepts
    // no buttons and no hover, so clicks/right-clicks/hover pass through to the dots while a wheel over a
    // dot (no onWheel) propagates down here. (KWin keyboard-layout-switcher pattern.)
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => indicator.handleWheel(wheel.angleDelta.y)
    }

    // Two nested positioners mirror KWin's grid: OUTER stacks lines on the cross axis, INNER lays each
    // line's dots on the major axis (one 2-D Grid would fatten a whole column). Plain positioner, no Layout
    // solver (qml-performance.md); the 1/-1 pair flips with `vertical`.
    Grid {
        id: strip
        anchors.centerIn: parent
        spacing: indicator.dotSpacing
        rows: indicator.vertical ? 1 : -1
        columns: indicator.vertical ? -1 : 1

        Repeater {
            // `lines` is [] while the source is transiently null/empty, so the outer Repeater is empty.
            model: indicator.lines

            delegate: Grid {
                id: lineStrip

                required property var modelData    // this line's UUIDs (a row-major chunk)
                required property int index        // line index (KWin row)

                spacing: indicator.dotSpacing
                rows: indicator.vertical ? -1 : 1
                columns: indicator.vertical ? 1 : -1
                // Centre every element on the CROSS axis: the line is as thick as its tallest element (the
                // capsule when pillSize > dotSize), else the positioner aligns the smaller dots against it.
                verticalItemAlignment: indicator.vertical ? Grid.AlignTop : Grid.AlignVCenter
                horizontalItemAlignment: indicator.vertical ? Grid.AlignHCenter : Grid.AlignLeft

                Repeater {
                    model: lineStrip.modelData

                    delegate: WorkspaceDot {
                        id: workspaceDot

                        required property string modelData
                        required property int index

                        // Position in the flat desktopIds/desktopNames: earlier lines are full at perLine.
                        readonly property int globalIndex: lineStrip.index * indicator.perLine + workspaceDot.index

                        vertical: indicator.vertical
                        dotSize: indicator.dotSize
                        pillSize: indicator.pillSize
                        pillWidthFactor: indicator.pillWidthFactor
                        inactiveOpacity: indicator.inactiveOpacity
                        hoverOpacity: indicator.hoverOpacity
                        followThemeColors: indicator.followThemeColors
                        activeColor: indicator.activeColor
                        inactiveColor: indicator.inactiveColor
                        animationDuration: indicator.animationDuration
                        active: indicator.currentDesktop === workspaceDot.modelData
                        animate: indicator.animate

                        // Each dot's tooltip name + window-list subText (|| "" guards the transient frame
                        // where names/tooltips lag ids — robustness.md) plus the showTooltips flag.
                        desktopName: indicator.desktopNames[workspaceDot.globalIndex] || ""
                        tooltipText: indicator.desktopTooltips[workspaceDot.globalIndex] || ""
                        showTooltips: indicator.showTooltips

                        onActivated: indicator.switchRequested(workspaceDot.modelData)
                    }
                }
            }
        }
    }
}
