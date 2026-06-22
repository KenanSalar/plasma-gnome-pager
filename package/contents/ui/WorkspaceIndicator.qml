/*
 * Plasma Gnome Pager — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip — the signature GNOME look via a REFLOW model. Each WorkspaceDot is a dim dot when
 * inactive and morphs into a longer highlighted "capsule" (the pill) along the major axis when active;
 * there is no overlay. A switch morphs two elements at once and the line reflows between them with a
 * SINGLE UNIFORM spacing, so the capsule can never overlap/clip a neighbour and the pill-to-dot gap
 * equals the dot-to-dot gap. No clip/layer is needed (qml-performance.md).
 *
 * This component is layout + scroll + wiring. Two concerns are extracted into their own units:
 *   - IndicatorMetrics — the sizing engine (natural/floor/effective dot+pill sizes, scale-to-fit). Fed
 *     the config requests + grid shape + live panel allocation; the indicator reads its sizes back.
 *   - ScreenCurrentDesktop — resolves the current desktop FOR THIS SCREEN (Plasma 6.7 per-output).
 * Data + DBus live in main.qml; this binds live to VirtualDesktopInfo (read) and reports clicks/scroll
 * up via switchRequested (main.qml owns the KWin write). It imports no org.kde.plasma.*, so it and the
 * dots stay headless-testable.
 *
 * Layout follows the panel and KWin's grid: `vertical` (Plasmoid.formFactor, via main.qml) picks the
 * major axis (Row on a horizontal panel, Column on a vertical one), and KWin's row count
 * (desktopLayoutRows) splits the desktops into that many independent single-line reflow strips stacked
 * on the cross axis — a multi-row grid is just lineCount of those (mirrors KWin, no widget setting).
 *
 * Sizing is advertised via Layout.* hints (NOT implicitWidth alone — a panel otherwise gives the inline
 * full-representation a default square cell and the dots overflow onto the neighbours). The major (line)
 * axis pins preferred == maximum to one line's NATURAL length so the cell stays put during a morph, with
 * the MINIMUM dropped to a floor so the panel can COMPRESS the strip (the dots then scale to fit). The
 * cross axis carries the lines with its maximum left FREE (-1) to fill the panel thickness, its minimum
 * likewise dropped to a floor. All hints are natural/floor-based, so the allocation never feeds back into
 * them (no binding loop). Which axis is major swaps with `vertical`.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

Item {
    id: indicator

    // Reactive read-only desktop state, supplied by main.qml (a VirtualDesktopInfo). NOT `required`:
    // Plasma instantiates representations via its own loader, where a required property on the
    // representation root fails creation silently. Default null + guard instead (robustness.md).
    property var virtualDesktopInfo: null

    // Null-safe live views of the reactive state. The desktop SET (ids/names/count/rows) is global;
    // only "which is current" is per-screen (resolved by ScreenCurrentDesktop below).
    readonly property var desktopIds: virtualDesktopInfo?.desktopIds ?? []
    readonly property var desktopNames: virtualDesktopInfo?.desktopNames ?? []

    // Per-desktop tooltip subText (the rich-text window list), index-aligned with desktopIds, supplied
    // by main.qml. Default [] → each dot falls back to a name-only tooltip (standalone/headless).
    property var desktopTooltips: []

    // This panel's physical output (KWin connector name, e.g. "DP-1"), read live from the QtQuick Screen
    // attached property of the placed representation so it reflects THIS monitor, and injected into the
    // resolver. Tests override it to drive per-screen scenarios; "" falls back to the global current.
    property string screenName: Screen.name

    // The current desktop FOR THIS SCREEN (a UUID), resolved by ScreenCurrentDesktop. activeIndex and
    // each dot's `active` bind off it.
    readonly property string currentDesktop: screenCurrent.currentDesktop

    ScreenCurrentDesktop {
        id: screenCurrent
        virtualDesktopInfo: indicator.virtualDesktopInfo
        screenName: indicator.screenName
    }

    // Behaviour flags, supplied by main.qml from plasmoid.configuration (defaults match the schema).
    property bool enableScroll: Logic.DEFAULTS.enableScroll
    property bool scrollWrap: Logic.DEFAULTS.scrollWrap
    property bool invertScroll: Logic.DEFAULTS.invertScroll   // flip the wheel-sign → direction mapping
    property bool showTooltips: Logic.DEFAULTS.showTooltips   // passed down to each dot's tooltip

    // Panel orientation, from Plasmoid.formFactor. false = horizontal row (also the Planar/floating
    // default); true = vertical column.
    property bool vertical: false

    // Running total of hi-res/touchpad wheel deltas; whole notches become steps (the remainder carries).
    property real wheelAccumulator: 0
    readonly property int wheelNotchDelta: Logic.DEFAULTS.wheelNotchDelta

    readonly property int desktopCount: desktopIds.length

    // KWin's desktop-grid row count, read live (null-guarded, clamped >= 1). We MIRROR KWin's grid rather
    // than add our own setting, so changing "Rows" in System Settings re-lays out reactively.
    readonly property int desktopRows: virtualDesktopInfo?.desktopLayoutRows > 0 ? virtualDesktopInfo.desktopLayoutRows : 1

    // Desktops per line (KWin columns = ceil(count / rows)) and the row-major split into lines.
    readonly property int perLine: Logic.gridColumns(desktopCount, desktopRows)
    readonly property var lines: Logic.chunk(desktopIds, perLine)
    readonly property int lineCount: lines.length

    // Index of the active element, or -1 for every transient state (empty ids, empty/absent
    // currentDesktop) — meaning no element is a capsule.
    readonly property int activeIndex: desktopIds.indexOf(currentDesktop)

    // ── Visual metrics ─────────────────────────────────────────────────────────────────────────────
    // Config requests fed to the sizing engine. dotSize/pillSize are `0 = auto` requests, resolved in
    // IndicatorMetrics (not main.qml) so the sentinel resolution stays headless-tested. Defaults match
    // the schema so the indicator renders sensibly standalone and under qmltestrunner.
    property int dotSizeRequest: Logic.DEFAULTS.dotSize    // px override; 0 = auto
    property int pillSizeRequest: Logic.DEFAULTS.pillSize  // px pill thickness; 0 = auto (match dots)
    property real spacingFactor: Logic.DEFAULTS.spacingFactor      // uniform gap as a multiple of a dot
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor  // active capsule length, × the pill thickness
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity        // inactive-dot hover brighten target

    // The sizing engine: requests + grid shape + live panel allocation → effective sizes + extents.
    // availableMajor/Cross are this Item's live geometry (the major axis swaps with `vertical`). The
    // forwarded readonly properties below expose its outputs to the dots, the Grid, the Layout hints, and
    // the tests — the names match the pre-extraction surface, so nothing downstream changed.
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
    property int animationDuration: Logic.DEFAULTS.animationDuration   // ms; 0 = follow the theme (longDuration)

    // Raised on a click or scroll; main.qml turns the UUID into a KWin switch.
    signal switchRequested(string uuid)

    // Translate a wheel event into a switch. Thin wrapper: the branching (notch accumulation, clamp/wrap,
    // the -1 ignore states) is in logic.js and unit-tested.
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

    // Advertise size so the panel allocates space. Major (line) axis: preferred == maximum ==
    // naturalStripLength (the cell stays put during a morph) with the MINIMUM dropped to floorStripLength
    // so the panel can compress us (dots then scale to fit). Cross axis: preferred == naturalCrossThickness
    // with maximum reset to -1 (Qt's unconstrained +∞) so the panel stretches it to the panel thickness,
    // and the minimum dropped to floorCrossThickness. All natural/floor-based → no binding loop. The major
    // axis swaps with `vertical`.
    implicitWidth: vertical ? naturalCrossThickness : naturalStripLength
    implicitHeight: vertical ? naturalStripLength : naturalCrossThickness
    Layout.minimumWidth: vertical ? floorCrossThickness : floorStripLength
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: vertical ? -1 : naturalStripLength
    Layout.minimumHeight: vertical ? floorStripLength : floorCrossThickness
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: vertical ? naturalStripLength : -1

    // Gate the morph so the FIRST valid placement is instant (the active element is already a capsule on
    // frame 0 — no grow-in on shell reload) while later switches animate. ScreenCurrentDesktop (a child)
    // resolves currentDesktop in its own Component.onCompleted, which runs before this one, so activeIndex
    // is already valid here.
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
    // no buttons and does not enable hover, so clicks/right-clicks/hover pass through to the dots; a wheel
    // over a dot (which has no onWheel) propagates down to this handler. (KWin keyboard-layout switcher pattern.)
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => indicator.handleWheel(wheel.angleDelta.y)
    }

    // Two nested positioners mirror KWin's grid: the OUTER stacks the lines along the cross axis (KWin
    // rows), the INNER lays each line's dots along the major axis. Each inner line is the single-line
    // reflow strip, so a multi-row grid is just lineCount of those stacked — no column-alignment math. Grid
    // (a plain positioner, no Layout solver — qml-performance.md) fixes only the line dimension to 1, the
    // other -1 (auto) so it tracks the live child count; the 1/-1 pair flips with `vertical`.
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
                // capsule when pillSize > dotSize), so without this the positioner top/left-aligns the
                // smaller inactive dots against the taller pill. Flips with `vertical`.
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

                        // Feed each dot its tooltip name + window-list subText (|| "" guards the transient
                        // frame where names/tooltips lag ids — robustness.md) and the showTooltips flag.
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
