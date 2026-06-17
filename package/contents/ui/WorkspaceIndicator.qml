/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip. Milestone 2: the signature GNOME look — a Row of dim WorkspaceDot
 * circles plus a single "pill" overlay (Kirigami.Theme.highlightColor) that sits over
 * the current desktop's dot and SLIDES between positions on switch.
 *
 * Pill length and dot spacing are DECOUPLED: the pill is wider than a dot, and the
 * inter-dot spacing is derived so the pill always keeps a small clearance to its
 * neighbours (never covering them) while the dots themselves stay tight. The indicator
 * reserves a half-pill "overhang" at each end so the pill never clips. No reflow on
 * switch; no clip / layer is needed (see qml-performance.md).
 *
 * Data + DBus live in main.qml (see CLAUDE.md architecture); this component only
 * lays out and forwards intent — it never caches or switches desktops itself. It
 * binds live to VirtualDesktopInfo (read state) and reports clicks/scroll up to main.qml
 * (which owns the KWin DBus write).
 *
 * Milestone 3 adds scroll-to-switch and tooltips. Scroll uses a bottom MouseArea (behind
 * the dots, acceptedButtons: NoButton, onWheel) — the canonical Plasma pattern: wheel
 * events over a dot propagate down to it (the dots have no onWheel), while clicks, hover
 * and right-clicks pass straight through to the dots / the applet. The index math
 * (clamp/wrap, hi-res wheel accumulation) lives in logic.js so it is unit-tested without a
 * Plasma session; this component stays a thin caller and keeps emitting switchRequested(uuid)
 * (main.qml owns the DBus write). Each dot carries its own tooltip (showing desktopName);
 * the indicator just feeds every dot its name + the showTooltips flag, so it stays free of
 * org.kde.plasma.* and remains headless-testable.
 *
 * Sizing: a panel allocates an applet's space from the representation's Layout.* hints, so
 * the indicator advertises its content width via Layout.minimum/preferred/maximumWidth (not
 * implicitWidth alone — a panel otherwise gives the inline full-representation a default
 * square cell and the dots overflow onto the neighbours).
 *
 * TODO(M4):  Row (horizontal) vs Column (vertical) on Plasmoid.formFactor; slide the
 *            pill along the correct axis (Behavior on y) and animate its size; swap the
 *            width Layout hints for height hints when vertical.
 * TODO(M5):  metrics (dotSize/dotSpacing/pillWidthFactor/inactiveOpacity) + colours
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
    readonly property var desktopIds: virtualDesktopInfo ? virtualDesktopInfo.desktopIds : []
    readonly property string currentDesktop: virtualDesktopInfo ? virtualDesktopInfo.currentDesktop : ""
    // Display names, index-aligned with desktopIds. Null-safe like the views above
    // (VirtualDesktopInfo, or its desktopNames, can be transiently absent).
    readonly property var desktopNames: virtualDesktopInfo && virtualDesktopInfo.desktopNames ? virtualDesktopInfo.desktopNames : []

    // Behaviour flags, supplied by main.qml from plasmoid.configuration. Defaults match the
    // schema so the indicator behaves sensibly standalone (and under qmltestrunner).
    property bool enableScroll: true
    property bool scrollWrap: false
    property bool showTooltips: true   // passed down to each dot's tooltip

    // Running total of hi-res/touchpad wheel deltas; whole 120-unit notches become steps
    // (the remainder carries so sub-notch touchpad motion is not lost). See Logic.accumulateWheel.
    property real wheelAccumulator: 0

    // Index of the active slot, or -1 when there is none to highlight. indexOf returns
    // -1 for every transient state — empty desktopIds, empty currentDesktop, or a
    // currentDesktop not yet present during an add/remove — which hides the pill
    // (robustness.md: guard/clamp the index before acting on it).
    readonly property int activeIndex: desktopIds.indexOf(currentDesktop)

    // Visual metrics. Named to forward-match the M5 ConfigAppearance keys; M5 swaps
    // these defaults for `plasmoid.configuration.*` reads. Sizes go through
    // Kirigami.Units (HiDPI); pillWidthFactor/inactiveOpacity are dimensionless ratios.
    //
    // Pill length and dot spacing are DECOUPLED: pillWidthFactor sets how long the pill
    // is relative to a dot, while dotSpacing is DERIVED from it so the (wider) pill keeps
    // a small constant clearance to its neighbours and never covers them — which lets the
    // dots sit tight even with a long pill (a single coupled factor could not do both).
    readonly property real dotSize: Kirigami.Units.iconSizes.small / 2
    readonly property real inactiveOpacity: 0.45
    readonly property real pillWidthFactor: 2.5            // pill length as a multiple of a dot
    readonly property real pillWidth: dotSize * pillWidthFactor
    // Half-pill that sticks out past the dot it covers, on each side.
    readonly property real pillOverhang: (pillWidth - dotSize) / 2
    // Clear space kept between the pill's end and the adjacent dot (tune for breathing room).
    readonly property real pillEndGap: dotSize / 4
    // Inter-dot gap: overhang (so the pill reaches but does not cover a neighbour) plus
    // the clearance. With slots == dotSize, this is exactly the circle-to-circle gap.
    readonly property real dotSpacing: pillOverhang + pillEndGap

    // X of the pill's left edge: step to the active dot's left edge (row.x accounts for the
    // centred Row when the panel grants extra width), then back off by the overhang so the
    // wider pill is centred on the dot. A -1 activeIndex parks it left of the strip, where
    // it is never seen because the pill is hidden whenever activeIndex < 0.
    readonly property real pillX: row.x + activeIndex * (dotSize + row.spacing) - pillOverhang

    // Typed handle so the headless tests can assert the pill's geometry/visibility/colour
    // without a fragile recursive tree walk (qml.md: expose internals via alias).
    readonly property alias pill: pill

    // Raised when a dot is clicked or the strip is scrolled; main.qml turns the UUID into
    // a KWin switch.
    signal switchRequested(string uuid)

    // Translate a wheel event into a desktop switch. Thin wrapper: the branching (notch
    // accumulation, clamp/wrap, the -1 ignore states) is in logic.js and unit-tested.
    function handleWheel(angleDeltaY: real) {
        if (!indicator.enableScroll)
            return;
        const acc = Logic.accumulateWheel(indicator.wheelAccumulator, angleDeltaY, 120);
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

    // Advertise size so the panel allocates space. The pill overhangs the end dots by
    // pillOverhang on each side, so reserve that extra width beyond the Row's footprint.
    // A horizontal panel sizes the applet from these Layout hints (implicitWidth alone is
    // not honoured for the inline full-representation — the panel would give it a default
    // square cell and the dots would overflow onto the neighbours). Height is left to the
    // panel thickness; the Row is centred within it. (M4: swap to height hints when vertical.)
    implicitWidth: row.implicitWidth + 2 * pillOverhang
    implicitHeight: row.implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    // Gate the slide animation so the FIRST valid placement is an instant jump (no
    // slide-in from x=0 on shell reload) while later switches animate. Qt.callLater
    // defers enabling until after the first valid x has been placed, which also holds
    // when VirtualDesktopInfo populates a frame after this component completes.
    property bool slideEnabled: false
    onActiveIndexChanged: {
        if (activeIndex >= 0 && !slideEnabled) {
            Qt.callLater(() => indicator.slideEnabled = true);
        }
    }
    Component.onCompleted: {
        if (activeIndex >= 0) {
            slideEnabled = true;
        }
    }

    // Scroll-to-switch over the whole strip. This MouseArea sits BEHIND the dots and the
    // pill (declared first), accepts no buttons and does not enable hover, so clicks,
    // right-clicks and hover all pass through to the dots / the applet untouched. A dot has
    // no onWheel, so a wheel event over it propagates down to this handler; a wheel over a
    // gap or the pill lands here directly. (Verified against the KWin keyboard-layout
    // switcher's onWheel pattern and headless mouseWheel tests.)
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
                slotWidth: indicator.dotSize
                inactiveOpacity: indicator.inactiveOpacity
                active: indicator.currentDesktop === workspaceDot.modelData

                // Feed each dot its tooltip name (|| "" guards the transient state where
                // names lag ids during an add/remove — robustness.md) and the showTooltips flag.
                desktopName: indicator.desktopNames[workspaceDot.index] || ""
                showTooltips: indicator.showTooltips

                onActivated: indicator.switchRequested(workspaceDot.modelData)
            }
        }
    }

    // The single sliding pill, drawn AFTER (on top of) the Row so it fully covers the
    // active slot's dim circle. It has no MouseArea, so clicks fall through to the dot
    // beneath (a bare Rectangle does not intercept pointer events in Qt Quick).
    Rectangle {
        id: pill

        visible: indicator.activeIndex >= 0
        width: indicator.pillWidth
        height: indicator.dotSize
        radius: height / 2
        color: Kirigami.Theme.highlightColor

        anchors.verticalCenter: row.verticalCenter
        // Centred over the active dot; see indicator.pillX for the geometry.
        x: indicator.pillX

        // Smooth GNOME-style slide. Disabled until the first placement (slideEnabled)
        // and when the user has turned animations off (longDuration === 0 → instant).
        Behavior on x {
            enabled: indicator.slideEnabled && Kirigami.Units.longDuration > 0
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
        }
    }
}
