/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip — the signature GNOME look via a REFLOW model: a Grid of WorkspaceDot
 * elements (a single row on a horizontal panel, a single column on a vertical one) with a
 * SINGLE UNIFORM spacing between every pair. Each element renders as a dim dot when inactive
 * and morphs into a longer highlighted "capsule" (the pill) along the major axis when active —
 * there is no separate overlay. Switching morphs two elements (old capsule → dot, new dot →
 * capsule) and the strip reflows between them. Because the active element is a real, uniformly-
 * spaced strip child, the capsule can NEVER overlap or clip a neighbour — so no overhang /
 * clearance math, and the pill-to-dot gap equals the dot-to-dot gap (what an overlay pill
 * could not achieve). No clip / layer is needed (see qml-performance.md).
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
 * indicator PINS its content length along the major axis (Layout.minimum/preferred/maximum) and
 * leaves the cross axis FREE to fill the panel thickness (not implicitWidth alone — a panel
 * otherwise gives the inline full-representation a default square cell and the dots overflow onto
 * the neighbours). The pinned length is a FORMULA (one capsule + the rest dots) so the panel cell
 * stays put during the morph and when no element is active (a single switch conserves total length:
 * the shrinking and growing elements cancel). `vertical` (from Plasmoid.formFactor, via main.qml)
 * decides which axis is pinned — width for a horizontal panel, height for a vertical one.
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

    // Number of desktops (drives the stable implicitWidth formula below).
    readonly property int desktopCount: desktopIds.length

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
    // content extent along the MAJOR (strip) axis — one capsule + the rest dots + uniform gaps —
    // as a FORMULA (not the live positioner length) so the panel cell never jitters during a morph
    // or while activeIndex is transiently -1 (a switch conserves total length: the shrinking and
    // growing elements cancel). crossThickness is the perpendicular extent — always one dot.
    readonly property real stripLength: desktopCount > 0 ? pillWidth + (desktopCount - 1) * (dotSize + dotSpacing) : dotSize
    readonly property real crossThickness: dotSize

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

    // Advertise size so the panel allocates space. The MAJOR (strip) axis is PINNED to stripLength
    // (min == preferred == max) so the panel gives the applet exactly its content length; the CROSS
    // (thickness) axis is left FREE (preferred == crossThickness, maximum reset to -1, which Qt maps
    // to the unconstrained Number.POSITIVE_INFINITY default) so the panel stretches it to the panel
    // thickness and the centred Grid sits in the middle. A panel honours these Layout hints, not
    // implicitWidth alone — without them the inline full-representation gets a default square cell and
    // the dots overflow onto the neighbours. Swapping which axis is pinned is the whole of M4's sizing:
    // horizontal pins width (the M3 behaviour, unchanged); vertical pins height.
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

    // One positioner for both orientations: a single row when horizontal, a single column when
    // vertical. Grid is a plain positioner (like Row/Column — no Layout solver), so it honours
    // qml-performance.md, and in the 1-row case it positions identically to the old Row (uniform
    // spacing, cross-axis-aligned children). Only the single-line dimension is constrained to 1;
    // the other is left -1 (auto) so Grid derives it from the live child count — NOT from
    // desktopCount, which would warn ("more items than rows×columns") for the frame where the
    // Repeater and a count binding update out of step during an add/remove.
    Grid {
        id: strip
        anchors.centerIn: parent
        spacing: indicator.dotSpacing
        rows: indicator.vertical ? -1 : 1
        columns: indicator.vertical ? 1 : -1

        Repeater {
            // desktopIds is [] while the source is transiently null/empty (add/remove
            // or shell reload), so the Repeater is empty and the delegate bindings below
            // never see a missing source (robustness.md).
            model: indicator.desktopIds

            delegate: WorkspaceDot {
                id: workspaceDot

                required property string modelData
                required property int index

                vertical: indicator.vertical
                dotSize: indicator.dotSize
                pillWidthFactor: indicator.pillWidthFactor
                inactiveOpacity: indicator.inactiveOpacity
                hoverOpacity: indicator.hoverOpacity
                active: indicator.currentDesktop === workspaceDot.modelData
                animate: indicator.animate

                // Feed each dot its tooltip name (|| "" guards the transient state where
                // names lag ids during an add/remove — robustness.md) and the showTooltips flag.
                desktopName: indicator.desktopNames[workspaceDot.index] || ""
                showTooltips: indicator.showTooltips

                onActivated: indicator.switchRequested(workspaceDot.modelData)
            }
        }
    }
}
