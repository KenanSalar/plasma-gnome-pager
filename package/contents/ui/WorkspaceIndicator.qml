/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
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
 * Sizing: a panel allocates an applet's space from the representation's Layout.* hints, so the
 * indicator PINS one line's length along the major axis (Layout.minimum/preferred/maximum) and
 * carries the lines on the cross axis with its maximum left FREE to fill the panel thickness (not
 * implicitWidth alone — a panel otherwise gives the inline full-representation a default square cell
 * and the dots overflow onto the neighbours). The pinned length is a FORMULA (one capsule + the rest
 * of a full line's dots) so the panel cell stays put during a morph and when no element is active
 * (a switch conserves total length: the shrinking and growing elements cancel). Which axis is the
 * major one swaps with `vertical` — width for a horizontal panel, height for a vertical one.
 *
 * TODO(M5):  metrics (dotSize/spacingFactor/pillWidthFactor/inactiveOpacity) + colours
 *            from plasmoid.configuration.* instead of the Kirigami defaults below.
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
    readonly property var desktopIds: virtualDesktopInfo && virtualDesktopInfo.desktopIds ? virtualDesktopInfo.desktopIds : []
    readonly property string currentDesktop: virtualDesktopInfo ? virtualDesktopInfo.currentDesktop : ""
    // Display names, index-aligned with desktopIds. Null-safe like the views above
    // (VirtualDesktopInfo, or its desktopNames, can be transiently absent).
    readonly property var desktopNames: virtualDesktopInfo && virtualDesktopInfo.desktopNames ? virtualDesktopInfo.desktopNames : []

    // Behaviour flags, supplied by main.qml from plasmoid.configuration. Defaults match the
    // schema so the indicator behaves sensibly standalone (and under qmltestrunner).
    property bool enableScroll: true
    property bool scrollWrap: false
    property bool showTooltips: true   // passed down to each dot's tooltip

    // Panel orientation, supplied by main.qml from Plasmoid.formFactor. false = horizontal row
    // (also the Planar/desktop/floating default); true = vertical column. Default false keeps the
    // standalone/headless behaviour — and every existing horizontal test — unchanged.
    property bool vertical: false

    // Running total of hi-res/touchpad wheel deltas; whole notches become steps (the remainder
    // carries so sub-notch touchpad motion is not lost). See Logic.accumulateWheel.
    property real wheelAccumulator: 0

    // Standard Qt angleDelta units per wheel notch (QWheelEvent reports ±120 for one mouse
    // notch; touchpads send fractions of this that accumulate). Passed to Logic.accumulateWheel.
    readonly property int wheelNotchDelta: 120

    // Number of desktops (drives the stable size formula below).
    readonly property int desktopCount: desktopIds.length

    // KWin's desktop-grid row count (System Settings → Virtual Desktops → "Rows"), read live
    // from VirtualDesktopInfo — null-guarded, and clamped to ≥1 so a transient 0/undefined reads
    // as a single line. We MIRROR KWin's grid rather than add our own setting: change "Rows" there
    // and the strip re-lays out reactively. The default (1) is a single line — today's behaviour.
    readonly property int desktopRows: virtualDesktopInfo && virtualDesktopInfo.desktopLayoutRows > 0 ? virtualDesktopInfo.desktopLayoutRows : 1

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

    // Visual metrics. Named to forward-match the M5 ConfigAppearance keys; M5 swaps these
    // defaults for `plasmoid.configuration.*` reads. Sizes go through Kirigami.Units (HiDPI);
    // pillWidthFactor / inactiveOpacity / hoverOpacity / spacingFactor are dimensionless ratios.
    //
    // ONE uniform spacing (spacingFactor × dotSize) sits between every adjacent element —
    // dot-to-dot AND capsule-to-dot are the same gap (the GNOME look). The active element is
    // simply wider in place; its neighbours are pushed out by the Row, never covered.
    readonly property real dotSize: Kirigami.Units.iconSizes.small / 2
    readonly property real inactiveOpacity: 0.45
    readonly property real hoverOpacity: 0.8              // inactive-dot hover brighten target
    readonly property real pillWidthFactor: 2.5          // active capsule length, as a multiple of a dot
    readonly property real pillWidth: dotSize * pillWidthFactor
    readonly property real spacingFactor: 0.5            // uniform gap as a multiple of a dot (GNOME-tight)
    readonly property real dotSpacing: dotSize * spacingFactor

    // Axis-neutral size primitives the orientation-aware sizing binds to. stripLength is the
    // content extent along the MAJOR (line) axis — the longest a line can be: one capsule + the
    // rest of that line's dots + uniform gaps (perLine dots, since full lines are the widest). A
    // FORMULA, not the live positioner length, so the panel cell never jitters during a morph or
    // while activeIndex is transiently -1 (a switch conserves total length). crossThickness is the
    // perpendicular extent: lineCount lines of one dot each + the gaps between them (one dot when
    // single-line — today's value). Both reduce to the M3 single-line formula when desktopRows == 1.
    readonly property real stripLength: perLine > 0 ? pillWidth + (perLine - 1) * (dotSize + dotSpacing) : dotSize
    readonly property real crossThickness: lineCount > 0 ? lineCount * dotSize + (lineCount - 1) * dotSpacing : dotSize

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
        // Wheel up (+angleDelta) → previous desktop; wheel down (−) → next. Negate to map.
        const next = Logic.stepIndex(indicator.activeIndex, indicator.desktopIds.length, -acc.steps, indicator.scrollWrap);
        if (next < 0 || next === indicator.activeIndex)
            return;   // empty/unknown source, or a clamped no-op at an end
        const uuid = indicator.desktopIds[next];
        if (!uuid)
            return;   // transient empty id (robustness.md: guard before use)
        indicator.switchRequested(uuid);
    }

    // Advertise size so the panel allocates space. The MAJOR (line) axis is PINNED to stripLength
    // (min == preferred == max) so the panel gives the applet exactly one line's content length; the
    // CROSS axis carries the lineCount lines (preferred == crossThickness) but its maximum is reset to
    // -1 (Qt maps that to the unconstrained Number.POSITIVE_INFINITY default), so the panel can still
    // stretch it to the panel thickness with the centred grid in the middle, while min keeps room for
    // every line. A panel honours these Layout hints, not implicitWidth alone — without them the inline
    // full-representation gets a default square cell and the dots overflow onto the neighbours. Which
    // axis is the major one swaps with `vertical`: a horizontal panel pins width (M3 behaviour when
    // single-line); a vertical panel pins height.
    implicitWidth: vertical ? crossThickness : stripLength
    implicitHeight: vertical ? stripLength : crossThickness
    Layout.minimumWidth: vertical ? crossThickness : stripLength
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: vertical ? -1 : stripLength
    Layout.minimumHeight: vertical ? stripLength : crossThickness
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: vertical ? stripLength : -1

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
                        pillWidthFactor: indicator.pillWidthFactor
                        inactiveOpacity: indicator.inactiveOpacity
                        hoverOpacity: indicator.hoverOpacity
                        active: indicator.currentDesktop === workspaceDot.modelData
                        animate: indicator.animate

                        // Feed each dot its tooltip name (|| "" guards the transient state where
                        // names lag ids during an add/remove — robustness.md) and the showTooltips flag.
                        desktopName: indicator.desktopNames[workspaceDot.globalIndex] || ""
                        showTooltips: indicator.showTooltips

                        onActivated: indicator.switchRequested(workspaceDot.modelData)
                    }
                }
            }
        }
    }
}
