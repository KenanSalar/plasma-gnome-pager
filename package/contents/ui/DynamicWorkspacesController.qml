/*
 * Plasma Gnome Pager — DynamicWorkspacesController.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * GNOME-style dynamic-workspaces controller — a non-visual Item, extracted from main.qml as one
 * headless-testable unit (imports only QtQuick + the pure .js tiers). When enabled, keep one empty trailing
 * desktop by issuing ONE KWin add/remove per cycle (Logic.dynamicWorkspacePlan). The desktop SET is global,
 * so this is a single GLOBAL behaviour coordinated via coordinator.js: setting SYNC + single-WRITER election
 * (else panels double-add then trim = a flash). Inputs IN as plain values, effects OUT as signals. See CLAUDE.md.
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
    // Busy-lock fallback: suppress re-firing after our own write until desktopIdsChanged confirms it.
    // Longer than KWin's round-trip (which normally clears the lock first) but short enough not to wedge.
    readonly property int busyFallbackMs: 750

    Timer {
        id: dynBusyTimer
        interval: controller.busyFallbackMs
        onTriggered: controller.dynBusy = false
    }

    // Join the coordinator (registering syncConfigRequested as the push channel). Adopt the global if a
    // sibling seeded it, else seed it from our value. Then evaluate once (the last desktop may already be
    // occupied at startup). Leave on teardown so a removed panel stops counting in the election.
    Component.onCompleted: {
        controller.dynToken = Coordinator.join((en, pf) => controller.syncConfigRequested(en, pf));
        if (Coordinator.haveGlobal())
            controller.syncConfigRequested(Coordinator.globalEnabled(), Coordinator.globalPrefix());
        else
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }
    Component.onDestruction: Coordinator.leave(controller.dynToken)

    // Our setting changed: if it differs from the global WE changed it → publish to every panel; if it
    // matches, this was a sync echo → just re-evaluate. Guarded against the pre-join window — config
    // bindings (and onChanged) fire before Component.onCompleted, so dynToken is still 0; publishing then
    // registers a phantom value that stalls the real writer (a previously-real bug).
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

    // Compute and dispatch the single action for the freshest state, or nothing. Only the elected writer
    // acts (Coordinator.isWriter), so panels never double-add.
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
            // Name "<prefix> N" (prefix synced across panels). position == current count (append), so the
            // new desktop's number is pos + 1.
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

    // Triggers: occupancy flips (window opened/closed/moved), and our own setting changing (route through
    // publishDynamicConfig so the global stays in sync before we act).
    onDesktopOccupancyChanged: controller.scheduleDynamic()
    onDynamicEnabledChanged: controller.publishDynamicConfig()
    onNamePrefixChanged: controller.publishDynamicConfig()

    // The desktop SET changing is also the signal that OUR add/remove landed → clear the lock and
    // re-evaluate (so a multi-step trim converges over a few cycles).
    Connections {
        target: controller.virtualDesktopInfo
        function onDesktopIdsChanged() {
            controller.dynBusy = false;
            controller.scheduleDynamic();
        }
    }
}
