/*
 * GNOME Workspace Switcher — WorkspaceIndicator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
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
 * binds live to VirtualDesktopInfo (read state) and reports clicks up to main.qml
 * (which owns the KWin DBus write).
 *
 * TODO(M3):  MouseArea { onWheel: ... } scroll-to-switch (gated by config).
 * TODO(M4):  Row (horizontal) vs Column (vertical) on Plasmoid.formFactor; slide the
 *            pill along the correct axis (Behavior on y) and animate its size.
 * TODO(M5):  metrics (dotSize/dotSpacing/pillWidthFactor/inactiveOpacity) + colours
 *            from plasmoid.configuration.* instead of the Kirigami defaults below.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

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

    // Raised when a dot is clicked; main.qml turns the UUID into a KWin switch.
    signal switchRequested(string uuid)

    // Advertise size so the panel allocates space. The pill overhangs the end dots by
    // pillOverhang on each side, so reserve that extra width beyond the Row's footprint.
    implicitWidth: row.implicitWidth + 2 * pillOverhang
    implicitHeight: row.implicitHeight

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

                dotSize: indicator.dotSize
                slotWidth: indicator.dotSize
                inactiveOpacity: indicator.inactiveOpacity
                active: indicator.currentDesktop === workspaceDot.modelData

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
