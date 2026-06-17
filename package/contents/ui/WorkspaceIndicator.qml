/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip — the signature GNOME look via a REFLOW model: a Row of WorkspaceDot
 * elements with a SINGLE UNIFORM spacing between every pair. Each element renders as a dim
 * dot when inactive and morphs into a wider highlighted "capsule" (the pill) when active —
 * there is no separate overlay. Switching morphs two elements (old capsule → dot, new dot →
 * capsule) and the Row reflows between them. Because the active element is a real, uniformly-
 * spaced Row child, the capsule can NEVER overlap or clip a neighbour — so no overhang /
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
 * Sizing: a panel allocates an applet's space from the representation's Layout.* hints, so
 * the indicator advertises its content width via Layout.minimum/preferred/maximumWidth (not
 * implicitWidth alone — a panel otherwise gives the inline full-representation a default
 * square cell and the dots overflow onto the neighbours). The advertised width is a FORMULA
 * (one capsule + the rest dots) so the panel cell stays put during the morph and when no
 * element is active (a single switch conserves total width: the shrinking and growing
 * elements cancel).
 *
 * TODO(M4):  Row (horizontal) vs Column (vertical) on Plasmoid.formFactor; morph along the
 *            correct axis; swap the width Layout hints for height hints when vertical.
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

    // Advertise size so the panel allocates space, from a FORMULA (not the live Row width):
    // exactly one element is the capsule at steady state, so width = one pillWidth + the rest
    // dots + the uniform gaps. This stays constant during a morph (a single switch conserves
    // total width) and when activeIndex is transiently -1 (no capsule), so the panel cell
    // never jitters. A horizontal panel sizes the applet from these Layout hints (implicitWidth
    // alone is not honoured for the inline full-representation — the panel would give it a
    // default square cell and the content would overflow onto the neighbours). Height is left
    // to the panel thickness; the Row is centred within it. (M4: swap to height hints when vertical.)
    implicitWidth: desktopCount > 0 ? pillWidth + (desktopCount - 1) * (dotSize + dotSpacing) : dotSize
    implicitHeight: dotSize
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

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

    Row {
        id: row
        anchors.centerIn: parent
        spacing: indicator.dotSpacing

        Repeater {
            // desktopIds is [] while the source is transiently null/empty (add/remove
            // or shell reload), so the Repeater is empty and the delegate bindings below
            // never see a missing source (robustness.md).
            model: indicator.desktopIds

            delegate: WorkspaceDot {
                id: workspaceDot

                required property string modelData
                required property int index

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
