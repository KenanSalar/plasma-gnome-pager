/*
 * Plasma Gnome Pager — DynamicWorkspacesController.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * GNOME-style dynamic-workspaces controller — a non-visual Item (QtQuick + pure .js only, headless-tested).
 * When enabled, keep one empty trailing desktop via ONE KWin add/remove per cycle. The desktop SET is
 * global, so coordinator.js does setting SYNC + single-WRITER election (else panels double-add → a flash).
 */
pragma ComponentBehavior: Bound

import QtQuick

import "logic.js" as Logic
import "coordinator.js" as Coordinator         // single-writer election + prefix sync across instances

Item {
    id: controller

    // Inputs (injected by main.qml). dynamicEnabled (not `enabled` — QQuickItem already defines that).
    property bool dynamicEnabled: false
    property string namePrefix: ""              // base name for auto-created desktops ("" = defaultPrefix)
    property string defaultPrefix: "Desktop"    // i18n default, passed IN so this stays i18n-free; never empty (KWin drops empty-name createDesktop)
    property var virtualDesktopInfo: null        // the read source (null-safe throughout — transiently absent)
    // Per-desktop occupancy bool[], index-aligned with desktopIds. The length guard in dynamicWorkspacePlan
    // makes a transient frame (occupancy still lagging a just-changed desktop set) a no-op until it catches up.
    property var desktopOccupancy: []

    // Outputs (the two things only main.qml's e2e boundary can do).
    signal dispatchRequested(var spec)          // a built KWin add/remove spec → root.dispatch(spec)
    signal syncConfigRequested(bool nextEnabled, string nextPrefix)  // mirror the global setting into persisted config

    // Internal state.
    property bool dynBusy: false
    property int dynToken: 0
    // Liveness fallback only — the real lock-clear is vdi.desktopIdsChanged below.
    readonly property int busyFallbackMs: 750

    Timer {
        id: dynBusyTimer
        interval: controller.busyFallbackMs
        onTriggered: controller.dynBusy = false
    }

    // Join the coordinator (syncConfigRequested is the push channel). Adopt the global if a sibling seeded
    // it, else seed it from our value, then evaluate once. Leave on teardown (stop counting in the election).
    Component.onCompleted: {
        controller.dynToken = Coordinator.join((en, pf) => controller.syncConfigRequested(en, pf));
        if (Coordinator.haveGlobal())
            controller.syncConfigRequested(Coordinator.globalEnabled(), Coordinator.globalPrefix());
        else
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }
    Component.onDestruction: Coordinator.leave(controller.dynToken)

    // Our setting changed: if it differs from the global WE changed it → publish to every panel; else it's
    // a sync echo → just re-evaluate. Guard the pre-join window (dynToken 0): config onChanged fires before
    // Component.onCompleted, and publishing then registers a phantom value that stalls the real writer.
    function publishDynamicConfig() {
        if (controller.dynToken === 0)
            return;
        if (!Coordinator.haveGlobal()
                || controller.dynamicEnabled !== Coordinator.globalEnabled()
                || controller.namePrefix !== Coordinator.globalPrefix())
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }

    // Coalesce a burst of occupancy / desktop-set changes into ONE evaluation next tick.
    function scheduleDynamic() {
        if (!controller.dynamicEnabled)
            return;
        Qt.callLater(controller.evaluateDynamic);
    }

    // Compute and dispatch the single action for the freshest state, or nothing. Only the elected writer acts (panels never double-add).
    function evaluateDynamic() {
        if (!controller.dynamicEnabled || controller.dynBusy)
            return;
        if (!Coordinator.isWriter(controller.dynToken))
            return;                              // another instance is the single global writer
        const ids = controller.virtualDesktopInfo?.desktopIds ?? [];
        const plan = Logic.dynamicWorkspacePlan(controller.desktopOccupancy, ids);
        if (!plan)
            return;
        let spec = null;
        if (plan.kind === "add") {
            // Name "<prefix> N" (prefix synced across panels); position == current count (append), so the number is pos + 1.
            const pos = controller.virtualDesktopInfo?.numberOfDesktops ?? ids.length;
            spec = Logic.addSpec(pos, Logic.formatDynamicDesktopName(controller.namePrefix, pos + 1, controller.defaultPrefix));
        } else if (plan.kind === "remove") {
            const count = controller.virtualDesktopInfo?.numberOfDesktops ?? ids.length;
            spec = Logic.removeSpec(plan.uuid, count);
        }
        if (!spec)
            return;
        controller.dynBusy = true;
        controller.dispatchRequested(spec);
        dynBusyTimer.restart();
    }

    // Triggers: occupancy flips, and our own setting changing (routed through publishDynamicConfig so the global syncs before we act).
    onDesktopOccupancyChanged: controller.scheduleDynamic()
    onDynamicEnabledChanged: controller.publishDynamicConfig()
    onNamePrefixChanged: controller.publishDynamicConfig()

    // The desktop SET changing is also the signal that OUR add/remove landed → clear the lock and re-evaluate (multi-step trim converges over cycles).
    Connections {
        target: controller.virtualDesktopInfo
        function onDesktopIdsChanged() {
            controller.dynBusy = false;
            controller.scheduleDynamic();
        }
    }
}
