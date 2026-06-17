/*
 * GNOME Workspace Switcher — main.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Root PlasmoidItem: owns the virtual-desktop data source (read) and the KWin
 * DBus helpers (write), and renders the dot strip inline in the panel.
 */
pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.plasmoid

// Public, stable imports only (intentionally no org.kde.plasma.private.*):
import org.kde.plasma.core as PlasmaCore         // PlasmaCore.Action (contextual menu)
import org.kde.taskmanager as TaskManager        // VirtualDesktopInfo (read state)
import org.kde.plasma.workspace.dbus as DBus     // KWin DBus (switch/add/remove)

import "logic.js" as Logic

PlasmoidItem {
    id: root

    Plasmoid.icon: "user-desktop"

    // A pager never demands attention — mark it Passive so the panel/system-tray treats it as a
    // quiet always-on widget (and a panel may auto-hide over it). The dots float directly on the
    // panel, so the applet draws no background of its own (the GNOME look).
    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Panel orientation, read here (the one place that touches Plasmoid) and passed DOWN as a plain
    // bool so the indicator/dot stay free of Plasmoid/PlasmaCore and remain headless-testable.
    // Planar (desktop) and Floating both report non-Vertical, so they fall through to the horizontal
    // row — the sensible default off-panel.
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Behaviour settings, read live from the config schema (contents/config/main.xml).
    // Defaults there apply even before the settings UI exists (M5 owns the dialog), so the
    // widget is config-driven now. These flow down to the indicator/tooltip/actions as
    // plain booleans, keeping those sub-components free of plasmoid.configuration (and so
    // headless-testable).
    //
    // The `?? <default>` mirrors each schema default: a freshly-added schema can read back
    // `undefined` for a frame (or until the widget is re-added) and a bare bool would then
    // collapse to false, silently disabling every interaction. The guard keeps the intended
    // defaults regardless, while still honouring a real saved value (false ?? true === false).
    readonly property bool enableScroll: Plasmoid.configuration.enableScroll ?? true
    readonly property bool scrollWrap: Plasmoid.configuration.scrollWrap ?? false
    readonly property bool showTooltips: Plasmoid.configuration.showTooltips ?? true
    readonly property bool enableAddRemove: Plasmoid.configuration.enableAddRemove ?? true

    // Appearance + animation settings, read the same way and passed down to the indicator as plain
    // values (it forwards them per-dot). dotSize/animationDuration use a `0 = auto` sentinel: the
    // indicator/dot turn 0 into the HiDPI/themed default (so main.qml stays free of Kirigami and
    // these stay headless-testable — see WorkspaceIndicator/WorkspaceDot). Each `?? <default>`
    // mirrors the schema default for the transient-undefined frame, exactly like the booleans above.
    readonly property int animationDuration: Plasmoid.configuration.animationDuration ?? 0
    readonly property int dotSize: Plasmoid.configuration.dotSize ?? 0
    readonly property real spacingFactor: Plasmoid.configuration.spacingFactor ?? 0.5
    readonly property real pillWidthFactor: Plasmoid.configuration.pillWidthFactor ?? 2.5
    readonly property real inactiveOpacity: Plasmoid.configuration.inactiveOpacity ?? 0.45
    readonly property real hoverOpacity: Plasmoid.configuration.hoverOpacity ?? 0.8
    readonly property bool followThemeColors: Plasmoid.configuration.followThemeColors ?? true
    readonly property color activeColor: Plasmoid.configuration.activeColor ?? "#3daee9"
    readonly property color inactiveColor: Plasmoid.configuration.inactiveColor ?? "#eff0f1"

    // A pager renders inline in the panel. Plasma will not instantiate ANY
    // representation unless a fullRepresentation is defined (a compact-only applet
    // renders nothing at all), so the dot strip IS the full representation and we
    // force it to always show inline — never a popup or the default compact icon —
    // via preferredRepresentation. (verified against develop.kde.org/docs/plasma/widget)
    //
    // The indicator is the representation directly; it advertises its size via Layout.*
    // hints so the panel allocates the right width (tooltips live per-dot inside it).
    preferredRepresentation: fullRepresentation
    fullRepresentation: WorkspaceIndicator {
        vertical: root.isVertical
        virtualDesktopInfo: vdi
        enableScroll: root.enableScroll
        scrollWrap: root.scrollWrap
        showTooltips: root.showTooltips

        // Appearance/animation config (dotSize passed as the raw 0=auto request; resolved here).
        dotSizeRequest: root.dotSize
        spacingFactor: root.spacingFactor
        pillWidthFactor: root.pillWidthFactor
        inactiveOpacity: root.inactiveOpacity
        hoverOpacity: root.hoverOpacity
        followThemeColors: root.followThemeColors
        activeColor: root.activeColor
        inactiveColor: root.inactiveColor
        animationDuration: root.animationDuration

        onSwitchRequested: uuid => root.switchTo(uuid)
    }

    // Reactive, read-only desktop state. Bind to it; never cache — it updates when
    // desktops change by ANY means (keyboard, another pager, settings). Writing
    // (switch/add/remove) goes through KWin DBus below. (see virtual-desktops.md)
    TaskManager.VirtualDesktopInfo {
        id: vdi
    }

    // Every virtual-desktop write goes through KWin's VirtualDesktopManager (service + path are
    // the invariant; only iface/member/arguments vary). Async fire-and-forget: issue the call and
    // let `vdi` report the resulting state. The typed-arg `arguments` arrays stay at each call site
    // — they hold the order-sensitive DBus.* constructors (see CLAUDE.md DBus gotcha).
    function kwinCall(iface, member, args) {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/VirtualDesktopManager",
            "iface": iface,
            "member": member,
            "arguments": args
        });
    }

    // Switch to a desktop by UUID via the VirtualDesktopManager "current" property.
    function switchTo(uuid) {
        if (!uuid) {
            return; // robustness: desktopIds/currentDesktop can be transiently empty
        }
        root.kwinCall("org.freedesktop.DBus.Properties", "Set", [new DBus.string("org.kde.KWin.VirtualDesktopManager"), new DBus.string("current"), new DBus.variant(uuid)]);
    }

    // Append a new desktop at the end. `vdi` reports the new count.
    function addDesktop() {
        root.kwinCall("org.kde.KWin.VirtualDesktopManager", "createDesktop", [new DBus.uint32(vdi.numberOfDesktops),   // position = append at end
            new DBus.string(i18n("New Desktop"))]);
    }

    // Remove a desktop by UUID. Never remove the last one (there must always be ≥1).
    function removeDesktop(uuid) {
        if (!uuid || !Logic.canRemoveDesktop(vdi.numberOfDesktops)) {
            return;
        }
        root.kwinCall("org.kde.KWin.VirtualDesktopManager", "removeDesktop", [new DBus.string(uuid)]);
    }

    // "Remove" targets the last desktop (the one addDesktop appended).
    function removeLastDesktop() {
        root.removeDesktop(Logic.lastDesktopId(vdi.desktopIds));
    }

    // Right-click menu. Gated by enableAddRemove; Remove also disables at the last desktop.
    // (The "Configure…" entry is added automatically by Plasma once a config schema exists.)
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Add Desktop")
            icon.name: "list-add"
            priority: Plasmoid.LowPriorityAction
            visible: root.enableAddRemove
            enabled: root.enableAddRemove
            onTriggered: root.addDesktop()
        },
        PlasmaCore.Action {
            text: i18n("Remove Last Desktop")
            icon.name: "list-remove"
            priority: Plasmoid.LowPriorityAction
            visible: root.enableAddRemove
            enabled: root.enableAddRemove && Logic.canRemoveDesktop(vdi.numberOfDesktops)
            onTriggered: root.removeLastDesktop()
        }
    ]
}
