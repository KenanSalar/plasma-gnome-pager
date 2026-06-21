/*
 * Plasma Gnome Pager — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip — the signature GNOME look via a REFLOW model. Each WorkspaceDot renders as a dim
 * dot when inactive and morphs into a longer highlighted "capsule" (the pill) along the major axis
 * when active — there is no separate overlay. Switching morphs two elements (old capsule → dot, new
 * dot → capsule) and the line reflows between them with a SINGLE UNIFORM spacing between every pair,
 * so the capsule can NEVER overlap or clip a neighbour (no overhang/clearance math) and the
 * pill-to-dot gap equals the dot-to-dot gap. No clip / layer is needed (see qml-performance.md).
 *
 * Layout follows the panel and KWin's desktop grid. `vertical` (from Plasmoid.formFactor, via
 * main.qml) picks the major axis: a horizontal panel lays each line out as a Row, a vertical one as
 * a Column. KWin's row count (VirtualDesktopInfo.desktopLayoutRows) splits the desktops into that
 * many LINES — we mirror KWin's grid rather than add a widget setting — and each line is an
 * independent single-line reflow strip, so a multi-row grid is just `lineCount` of those stacked
 * along the cross axis. The default (1 row) is a single line. Lines are centred independently
 * (a shorter/last line is narrower than the line holding the pill); keeping each row's exact
 * dots+pill look is preferred over forcing column-alignment (which would need a wider active cell).
 *
 * Data + DBus live in main.qml (see CLAUDE.md architecture); this component only
 * lays out and forwards intent — it never caches or switches desktops itself. It
 * binds live to VirtualDesktopInfo (read state) and reports clicks/scroll up to main.qml
 * (which owns the KWin DBus write).
 *
 * Scroll uses a bottom MouseArea (behind the dots, acceptedButtons: NoButton, onWheel) —
 * the canonical Plasma pattern: wheel events over a dot propagate down to it (the dots have
 * no onWheel), while clicks, hover and right-clicks pass straight through to the dots / the
 * applet. The index math (clamp/wrap, hi-res wheel accumulation) lives in logic.js so it is
 * unit-tested without a Plasma session; this component stays a thin caller and keeps emitting
 * switchRequested(uuid) (main.qml owns the DBus write). Each dot carries its own tooltip
 * (showing desktopName); the indicator just feeds every dot its name + the showTooltips flag,
 * so it stays free of org.kde.plasma.* and remains headless-testable.
 *
 * Sizing: a panel allocates an applet's space from the representation's Layout.* hints. On the major
 * (line) axis the indicator pins preferred == maximum to one line's NATURAL length (a FORMULA: one
 * capsule + the rest of a full line's dots) so it never grows past that and the cell stays put during
 * a morph or when no element is active (a switch conserves total length: the shrinking and growing
 * elements cancel); the major MINIMUM drops to a smaller floor so the panel can COMPRESS the strip on
 * a crowded panel — and when it does, the dots scale down to fill the allocation exactly (fitDotSize)
 * instead of overflowing onto the neighbours (robustness.md). The cross axis carries the lines with
 * its maximum left FREE to fill the panel thickness (Layout.* hints, not implicitWidth alone — a panel
 * otherwise gives the inline full-representation a default square cell and the dots overflow). Which
 * axis is the major one swaps with `vertical` — width for a horizontal panel, height for a vertical one.
 *
 * The visual metrics + colours + animation duration are supplied by main.qml (read from
 * plasmoid.configuration); this component holds the same Kirigami-derived defaults so it still
 * renders sensibly standalone and under qmltestrunner. It forwards them per-dot unchanged — the
 * indicator draws nothing itself.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

Item {
    id: indicator

    // Reactive read-only desktop state, supplied by main.qml (a VirtualDesktopInfo).
    // NOT `required`: Plasma instantiates representations via its own loader, where a
    // required property on the representation root fails creation silently. Default
    // null + guard instead (robustness.md: guard transient null state).
    property var virtualDesktopInfo: null

    // Null-safe live views of the reactive desktop state — one source of truth that
    // the bindings below read, so the guard isn't repeated (virtualDesktopInfo can be
    // transiently null during a desktop add/remove or shell reload; see robustness.md).
    // The desktop SET (ids/names/count/rows) is global — only "which is current" is per-screen.
    readonly property var desktopIds: virtualDesktopInfo?.desktopIds ?? []
    // Display names, index-aligned with desktopIds. Null-safe like the views above
    // (VirtualDesktopInfo, or its desktopNames, can be transiently absent).
    readonly property var desktopNames: virtualDesktopInfo?.desktopNames ?? []

    // Per-desktop tooltip subText (the rich-text window list), index-aligned with desktopIds,
    // supplied by main.qml (which owns the TasksModel). Default [] keeps the standalone/headless
    // behaviour unchanged — each dot then falls back to "" (a name-only tooltip). Passed down to
    // each dot by global index, exactly like desktopNames.
    property var desktopTooltips: []

    // This panel's physical output (KWin connector name, e.g. "DP-1"), read live from the QtQuick
    // Screen attached property of the placed representation, so it reflects THIS monitor. Plasma 6.7
    // lets each output show a different current desktop; we resolve the current FOR this screen below.
    // Tests override it to drive per-screen scenarios; "" falls back to the global current.
    property string screenName: Screen.name

    // The current desktop FOR THIS SCREEN (a UUID), the one element that morphs into the capsule.
    // VirtualDesktopInfo.currentDesktopByScreenName is a METHOD with a per-screen change SIGNAL (not a
    // notifying property), so a plain binding would never re-evaluate — instead this is a mutable
    // source-of-truth property recomputed in updateCurrentDesktop() (driven by the Connections below).
    // activeIndex and each dot's `active` bind off it, so they stay declarative and per-screen-correct.
    property string currentDesktop: ""

    // Resolve currentDesktop for screenName, preferring the per-screen value (Plasma 6.7) and falling
    // back to the global current when there is no per-screen info — an unknown screen, the feature off,
    // or an older Plasma without currentDesktopByScreenName (the typeof guard; see robustness.md). The
    // perScreen-vs-global decision is the pure Logic.resolveCurrentDesktop (unit-tested).
    function updateCurrentDesktop() {
        const vdi = indicator.virtualDesktopInfo;
        const globalCurrent = vdi?.currentDesktop ?? "";
        let perScreen;   // stays undefined unless we have a screen AND the 6.7 API
        if (vdi && indicator.screenName && typeof vdi.currentDesktopByScreenName === "function")
            perScreen = vdi.currentDesktopByScreenName(indicator.screenName);
        indicator.currentDesktop = Logic.resolveCurrentDesktop(perScreen, globalCurrent);
    }

    // Recompute when the source's current changes (globally, or for THIS screen), when desktops are
    // added/removed (a screen's current may have been removed), when the source itself swaps in, and
    // when this panel moves to another output. "Bind, don't cache": every external change re-resolves.
    Connections {
        target: indicator.virtualDesktopInfo
        function onCurrentDesktopChanged() {
            indicator.updateCurrentDesktop();
        }
        function onCurrentDesktopForScreenChanged(screenName) {
            if (screenName === indicator.screenName)
                indicator.updateCurrentDesktop();
        }
        function onDesktopIdsChanged() {
            indicator.updateCurrentDesktop();
        }
    }
    onScreenNameChanged: indicator.updateCurrentDesktop()
    onVirtualDesktopInfoChanged: indicator.updateCurrentDesktop()

    // Behaviour flags, supplied by main.qml from plasmoid.configuration. Defaults match the
    // schema so the indicator behaves sensibly standalone (and under qmltestrunner).
    property bool enableScroll: Logic.DEFAULTS.enableScroll
    property bool scrollWrap: Logic.DEFAULTS.scrollWrap
    property bool invertScroll: Logic.DEFAULTS.invertScroll   // flip the wheel-sign → direction mapping
    property bool showTooltips: Logic.DEFAULTS.showTooltips   // passed down to each dot's tooltip

    // Panel orientation, supplied by main.qml from Plasmoid.formFactor. false = horizontal row
    // (also the Planar/desktop/floating default); true = vertical column. Default false keeps the
    // standalone/headless behaviour — and every existing horizontal test — unchanged.
    property bool vertical: false

    // Running total of hi-res/touchpad wheel deltas; whole notches become steps (the remainder
    // carries so sub-notch touchpad motion is not lost). See Logic.accumulateWheel.
    property real wheelAccumulator: 0

    // Standard Qt angleDelta units per wheel notch (QWheelEvent reports ±120 for one mouse
    // notch; touchpads send fractions of this that accumulate). Passed to Logic.accumulateWheel.
    readonly property int wheelNotchDelta: Logic.DEFAULTS.wheelNotchDelta

    // Number of desktops (drives the stable size formula below).
    readonly property int desktopCount: desktopIds.length

    // KWin's desktop-grid row count (System Settings → Virtual Desktops → "Rows"), read live
    // from VirtualDesktopInfo — null-guarded, and clamped to ≥1 so a transient 0/undefined reads
    // as a single line. We MIRROR KWin's grid rather than add our own setting: change "Rows" there
    // and the strip re-lays out reactively. The default (1) is a single line — today's behaviour.
    readonly property int desktopRows: virtualDesktopInfo?.desktopLayoutRows > 0 ? virtualDesktopInfo.desktopLayoutRows : 1

    // Desktops per line (KWin columns = ceil(count / rows)) and the row-major split of desktopIds
    // into lines. Each line is rendered as an independent single-line reflow strip below, so the
    // grid is just `lineCount` of those stacked — every row keeps the exact dots+pill look.
    readonly property int perLine: Logic.gridColumns(desktopCount, desktopRows)
    readonly property var lines: Logic.chunk(desktopIds, perLine)
    readonly property int lineCount: lines.length

    // Index of the active element, or -1 when there is none to highlight. indexOf returns
    // -1 for every transient state — empty desktopIds, empty currentDesktop, or a
    // currentDesktop not yet present during an add/remove — which means no element is a
    // capsule (robustness.md: guard the index before acting on it).
    readonly property int activeIndex: desktopIds.indexOf(currentDesktop)

    // Visual metrics, supplied by main.qml from plasmoid.configuration (Appearance keys), with the
    // Kirigami/dimensionless defaults below so the indicator renders sensibly standalone and under
    // qmltestrunner. Sizes go through Kirigami.Units (HiDPI); pillWidthFactor / inactiveOpacity /
    // hoverOpacity / spacingFactor are dimensionless ratios.
    //
    // dotSize is a `0 = auto` request: a positive value is the user's px override, 0 falls back to
    // the HiDPI-aware themed default (a fixed schema literal would bake a px value — see kirigami.md).
    // Resolving the sentinel here (not in main.qml) keeps it headless-testable and main.qml Kirigami-free.
    //
    // ONE uniform spacing (spacingFactor × dotSize) sits between every adjacent element —
    // dot-to-dot AND capsule-to-dot are the same gap (the GNOME look). The active element is
    // simply wider in place; its neighbours are pushed out by the Row, never covered.
    //
    // NATURAL vs EFFECTIVE size: naturalDotSize is the upper bound (the config/themed request); the
    // rendered `dotSize` SHRINKS below it to fit a crowded panel on EITHER axis — the major line length
    // OR the cross thickness (scale-to-fit, robustness.md) — floored at minDotSize so the dots stay
    // legible. naturalDotSize (NOT the effective size) drives the Layout
    // hints below, so the panel allocation never feeds back into the hints — no binding loop. In the
    // common case (room available) the effective size == naturalDotSize, so the look is unchanged.
    // Everything downstream (pillSize, pillWidth, dotSpacing, each WorkspaceDot, the Grid spacing)
    // reads the effective `dotSize`, so the whole strip — dots AND pill — scales in lockstep, even
    // when the pill is sized independently of the dots (its thickness tracks the same shrink ratio).
    property int dotSizeRequest: Logic.DEFAULTS.dotSize  // px override from config; 0 = auto
    readonly property real naturalDotSize: dotSizeRequest > 0 ? dotSizeRequest : Kirigami.Units.iconSizes.small / 2
    // Active-pill thickness, sized INDEPENDENTLY of the dots. 0 = auto = match the dot size, so the
    // default (and any dot-size-only change) keeps the pill tracking the dots — the look is unchanged
    // unless the user explicitly sets a pill size. pillThicknessRatio is the natural pill thickness in
    // DOT units (1 when auto); it is the ONE quantity that carries the decoupling into the otherwise
    // unchanged fit/extent formulas below (pill length stays pillWidthFactor *thicknesses* long).
    property int pillSizeRequest: Logic.DEFAULTS.pillSize
    readonly property real naturalPillSize: pillSizeRequest > 0 ? pillSizeRequest : naturalDotSize
    readonly property real pillThicknessRatio: naturalPillSize / naturalDotSize
    // Smallest legible dot we will shrink to: half the default dot, clamped to <= natural so a tiny
    // configured dot never scales UP (keeps the room-available common case byte-for-byte identical).
    readonly property real minDotSize: Math.min(naturalDotSize, Kirigami.Units.iconSizes.small / 4)
    // The panel-allocated extent of each axis, read live from this Item's geometry. `vertical` swaps
    // which physical dimension is the major (line) axis and which is the cross axis; naming the swap
    // once keeps the two scale-to-fit reads below declarative and orientation-symmetric.
    readonly property real availableMajor: vertical ? height : width
    readonly property real availableCross: vertical ? width : height
    // Dot size that makes one full line exactly fill the panel-allocated MAJOR length (width when
    // horizontal, height when vertical): one capsule + the rest of that line's dots + uniform gaps.
    // The capsule's length in DOT units is pillThicknessRatio * pillWidthFactor (pill length =
    // pillSize * pillWidthFactor, and pillSize = dot * ratio) — the only change vs M6, and it reduces
    // to pillWidthFactor when the pill tracks the dots (ratio == 1).
    // Pure math (logic.js); +Infinity before layout / with no line, so it does not bind there.
    readonly property real majorFitDotSize: Logic.fitDotSize(availableMajor, perLine, pillThicknessRatio * pillWidthFactor, spacingFactor)
    // Dot size that makes the stacked lines exactly fill the panel-allocated CROSS thickness (height
    // when horizontal, width when vertical). Only the line holding the pill is max(dot, pill) thick;
    // every other line is one dot thick — so the cross "pill factor" is max(1, pillThicknessRatio)
    // (1 when the pill is no thicker than a dot, recovering the M6 inverse of naturalCrossThickness).
    // +Infinity on a single thick panel (room to spare) or before layout, so it does not bind in the
    // common case; it only bites for a multi-row grid (or a thick pill) on a thin panel.
    readonly property real crossFitDotSize: Logic.fitDotSize(availableCross, lineCount, Math.max(1, pillThicknessRatio), spacingFactor)
    // A dot must fit BOTH axes, so the binding constraint is the smaller fit (the unconstrained axis
    // returns +Infinity, so min keeps the other). This generalises the M6 major-axis fit to the
    // multi-row + thin-panel case without ever overflowing the panel thickness (robustness.md).
    readonly property real fitDotSize: Math.min(majorFitDotSize, crossFitDotSize)
    // EFFECTIVE (rendered) dot size: shrink-to-fit, capped at natural, floored at minDotSize. Common
    // case (room available on both axes): fitDotSize >= naturalDotSize, so this == naturalDotSize exactly.
    readonly property real dotSize: Math.max(minDotSize, Math.min(naturalDotSize, fitDotSize))
    property real inactiveOpacity: Logic.DEFAULTS.inactiveOpacity
    property real hoverOpacity: Logic.DEFAULTS.hoverOpacity        // inactive-dot hover brighten target
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor  // active capsule length, as a multiple of the PILL thickness
    // EFFECTIVE pill thickness: scales in lockstep with the dot (same shrink ratio), so the configured
    // dot:pill proportion is preserved under scale-to-fit. == dotSize when the pill tracks the dots.
    readonly property real pillSize: dotSize * pillThicknessRatio
    readonly property real pillWidth: pillSize * pillWidthFactor   // active capsule LENGTH (major axis)
    property real spacingFactor: Logic.DEFAULTS.spacingFactor      // uniform gap as a multiple of a dot (GNOME-tight)
    readonly property real dotSpacing: dotSize * spacingFactor

    // Colour + animation config, passed straight through to each dot (the indicator draws nothing
    // itself). Defaults are the theme colours / auto duration so a standalone dot is unchanged.
    property bool followThemeColors: Logic.DEFAULTS.followThemeColors
    property color activeColor: Kirigami.Theme.highlightColor
    property color inactiveColor: Kirigami.Theme.textColor
    property int animationDuration: Logic.DEFAULTS.animationDuration   // ms; 0 = follow the theme (longDuration)

    // Axis-neutral size primitives the orientation-aware sizing binds to — all NATURAL/floor-based
    // (never the effective dotSize), so the Layout hints they feed do not depend on the panel
    // allocation and there is no binding loop (see the Layout block below). naturalStripLength is the
    // content extent along the MAJOR (line) axis at the natural dot size — the longest a line can be:
    // one capsule + the rest of that line's dots + uniform gaps (perLine dots, since full lines are the
    // widest). A FORMULA, not the live positioner length, so the panel cell never jitters during a
    // morph or while activeIndex is transiently -1 (a switch conserves total length). floorStripLength
    // is the same line at minDotSize — the major-axis MINIMUM, so the panel may compress the strip into
    // the scale-to-fit path but no further than still-legible dots. naturalCrossThickness is the
    // perpendicular extent at the natural dot size: lineCount lines of one dot each + the gaps between
    // them (one dot when single-line). floorCrossThickness is that same stack at minDotSize — the
    // cross-axis MINIMUM, so a thin panel may compress the thickness into the cross scale-to-fit path
    // (a multi-row grid on a thin panel) but no further than still-legible dots, exactly mirroring
    // floorStripLength on the major axis. All reduce to the M3 single-line formula when desktopRows == 1.
    // The capsule's length is naturalPillSize * pillWidthFactor (the pill thickness, sized
    // independently of the dot, times its aspect ratio); == naturalDotSize * pillWidthFactor when the
    // pill tracks the dots. The floor uses the pill thickness at the dot floor (minDotSize * ratio).
    readonly property real naturalStripLength: Logic.lineExtent(perLine, naturalDotSize, naturalDotSize * spacingFactor, naturalPillSize * pillWidthFactor)
    readonly property real floorStripLength: Logic.lineExtent(perLine, minDotSize, minDotSize * spacingFactor, minDotSize * pillThicknessRatio * pillWidthFactor)
    // The pill-bearing line is as thick as the thicker of dot/pill: pass activeExtent == max(dot, pill)
    // (== the dot size, the all-dots degenerate case, when the pill is no thicker than a dot).
    readonly property real naturalCrossThickness: Logic.lineExtent(lineCount, naturalDotSize, naturalDotSize * spacingFactor, Math.max(naturalDotSize, naturalPillSize))
    readonly property real floorCrossThickness: Logic.lineExtent(lineCount, minDotSize, minDotSize * spacingFactor, minDotSize * Math.max(1, pillThicknessRatio))

    // Raised when a dot is clicked or the strip is scrolled; main.qml turns the UUID into
    // a KWin switch.
    signal switchRequested(string uuid)

    // Translate a wheel event into a desktop switch. Thin wrapper: the branching (notch
    // accumulation, clamp/wrap, the -1 ignore states) is in logic.js and unit-tested.
    function handleWheel(angleDeltaY: real) {
        if (!indicator.enableScroll)
            return;
        const acc = Logic.accumulateWheel(indicator.wheelAccumulator, angleDeltaY, indicator.wheelNotchDelta);
        indicator.wheelAccumulator = acc.remainder;
        if (acc.steps === 0)
            return;   // sub-notch motion accumulated; nothing to do yet
        // Default: wheel up (+angleDelta) → previous desktop; wheel down (−) → next, so negate to
        // map. With invertScroll on, keep the sign so up → next / down → previous.
        const dir = indicator.invertScroll ? acc.steps : -acc.steps;
        const next = Logic.stepIndex(indicator.activeIndex, indicator.desktopIds.length, dir, indicator.scrollWrap);
        if (next < 0 || next === indicator.activeIndex)
            return;   // empty/unknown source, or a clamped no-op at an end
        const uuid = indicator.desktopIds[next];
        if (!uuid)
            return;   // transient empty id (robustness.md: guard before use)
        indicator.switchRequested(uuid);
    }

    // Advertise size so the panel allocates space. On the MAJOR (line) axis, preferred == maximum ==
    // naturalStripLength (one line at the natural dot size) so the applet never grows past its natural
    // length, while the MINIMUM drops to floorStripLength so the panel CAN compress us — when it does,
    // the dots scale down to fill the allocation exactly (majorFitDotSize above) instead of overflowing
    // onto the neighbours (robustness.md). The CROSS axis carries the lineCount lines (preferred ==
    // naturalCrossThickness) with its maximum reset to -1 (Qt maps that to the unconstrained
    // Number.POSITIVE_INFINITY default), so the panel can stretch it to the panel thickness with the
    // centred grid in the middle; its MINIMUM likewise drops to floorCrossThickness so a thin panel can
    // compress the thickness and the dots shrink to fit it too (cross scale-to-fit — a multi-row grid on
    // a thin panel no longer exceeds the thickness, crossFitDotSize above). A panel honours these Layout
    // hints, not implicitWidth alone — without them the inline full-representation gets a default square
    // cell and the dots overflow onto the neighbours. All hints are NATURAL/floor-based (never the
    // effective dotSize), so the allocation never feeds back into them — no binding loop. Which axis is
    // the major one swaps with `vertical`: a horizontal panel pins width (M3 behaviour when
    // single-line); a vertical panel pins height.
    implicitWidth: vertical ? naturalCrossThickness : naturalStripLength
    implicitHeight: vertical ? naturalStripLength : naturalCrossThickness
    Layout.minimumWidth: vertical ? floorCrossThickness : floorStripLength
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: vertical ? -1 : naturalStripLength
    Layout.minimumHeight: vertical ? floorStripLength : floorCrossThickness
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: vertical ? naturalStripLength : -1

    // Gate the morph so the FIRST valid placement is instant (the active element is already a
    // capsule on frame 0 — no grow-in from a dot on shell reload) while later switches animate.
    // Qt.callLater defers enabling until after the first valid placement, which also holds when
    // VirtualDesktopInfo populates (or currentDesktop resolves) a frame after this completes.
    property bool animate: false
    onActiveIndexChanged: {
        if (activeIndex >= 0 && !animate) {
            Qt.callLater(() => indicator.animate = true);
        }
    }
    Component.onCompleted: {
        indicator.updateCurrentDesktop();   // resolve the per-screen current before the latch check
        if (activeIndex >= 0) {
            animate = true;
        }
    }

    // Scroll-to-switch over the whole strip. This MouseArea sits BEHIND the dots (declared
    // first), accepts no buttons and does not enable hover, so clicks, right-clicks and hover
    // all pass through to the dots / the applet untouched. A dot has no onWheel, so a wheel
    // event over it propagates down to this handler; a wheel over a gap lands here directly.
    // (Verified against the KWin keyboard-layout switcher's onWheel pattern and headless
    // mouseWheel tests.)
    MouseArea {
        id: wheelArea
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => indicator.handleWheel(wheel.angleDelta.y)
    }

    // Two nested positioners mirror KWin's desktop grid: the OUTER stacks the lines along the cross
    // axis (the KWin rows), the INNER lays each line's dots along the major axis. Each inner line is
    // exactly the single-line reflow strip (tight dots + in-place pill), so a multi-row grid is just
    // `lineCount` of those stacked — every row keeps the current look, no column-alignment math.
    // Grid (a plain positioner, no Layout solver — qml-performance.md) does both: only the line
    // dimension is fixed to 1, the other is -1 (auto) so it tracks the live child count and never
    // warns ("more items than rows×columns") during an add/remove. The 1/-1 pair flips with
    // `vertical`: horizontal → lines stacked in a column, dots in rows; vertical → the transpose,
    // so the longer (per-line) extent always runs along the panel's long axis.
    Grid {
        id: strip
        anchors.centerIn: parent
        spacing: indicator.dotSpacing
        rows: indicator.vertical ? 1 : -1
        columns: indicator.vertical ? -1 : 1

        Repeater {
            // `lines` is [] while the source is transiently null/empty (add/remove or shell
            // reload), so the outer Repeater is empty and nothing below sees a missing source.
            model: indicator.lines

            delegate: Grid {
                id: lineStrip

                required property var modelData    // this line's UUIDs (a row-major chunk)
                required property int index        // line index (KWin row)

                spacing: indicator.dotSpacing
                rows: indicator.vertical ? -1 : 1
                columns: indicator.vertical ? 1 : -1
                // Centre every element on the CROSS axis. The line is as thick as its tallest element
                // (the capsule when pillSize > dotSize), so without this the positioner top/left-aligns
                // the smaller inactive dots against the taller pill. The MAJOR-axis alignment is the
                // default (a no-op: one item per row/column along that axis). Flips with `vertical`:
                // a horizontal line centres vertically, a vertical one horizontally.
                verticalItemAlignment: indicator.vertical ? Grid.AlignTop : Grid.AlignVCenter
                horizontalItemAlignment: indicator.vertical ? Grid.AlignHCenter : Grid.AlignLeft

                Repeater {
                    model: lineStrip.modelData

                    delegate: WorkspaceDot {
                        id: workspaceDot

                        required property string modelData
                        required property int index

                        // Position in the flat desktopIds/desktopNames: earlier lines are full at
                        // perLine, so global = line * perLine + position-within-line.
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

                        // Feed each dot its tooltip name + window-list subText (|| "" guards the
                        // transient state where names/tooltips lag ids during an add/remove —
                        // robustness.md) and the showTooltips flag.
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
