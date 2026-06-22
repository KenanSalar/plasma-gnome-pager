/*
 * Plasma Gnome Pager — DynamicWorkspacesController.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The GNOME-style dynamic-workspaces controller — a non-visual zero-size Item (it hosts a Timer +
 * Connections, which need a QQuickItem host). Extracted out of main.qml so the reactive state machine
 * is ONE single-responsibility unit AND headless-testable: it imports only QtQuick + the two pure .js
 * tiers (no Plasmoid/PlasmaCore/Kirigami/i18n), so tst_dynamicworkspacescontroller.qml drives it with a
 * VdiMock + injected occupancy and asserts the dispatched specs directly.
 *
 * When enabled, keep exactly one empty trailing desktop by issuing ONE KWin add/remove per cycle and
 * letting VirtualDesktopInfo report the result (the read/write split). The decision is the pure
 * Logic.dynamicWorkspacePlan; here we debounce, re-check the freshest state, and hold a short busy-lock
 * against THIS instance re-firing before its own change reflects.
 *
 * The desktop SET is global, so this is a single GLOBAL behaviour coordinated via coordinator.js (one
 * .pragma library per plasmashell engine): (1) setting SYNC — the enabled flag + name prefix are ONE
 * global value, mirrored into this instance's persisted config via syncConfigRequested (main.qml does
 * the Plasmoid.configuration write, so the controller stays Plasma-free); (2) single-WRITER election —
 * only the lowest-token instance issues the add/remove, so panels never double-add then trim (the
 * "flash"); dynToken is our handle. Inputs flow IN as plain values; side effects flow OUT as the two
 * signals (DIP).
 */
pragma ComponentBehavior: Bound

import QtQuick

import "logic.js" as Logic
import "coordinator.js" as Coordinator         // single-writer election + prefix sync across panel instances

Item {
    id: controller

    // ── Inputs (injected by main.qml; bound to its live config + the read source) ──────────────────
    // Whether dynamic workspaces is on. (Named dynamicEnabled, not `enabled`, because QQuickItem
    // already defines `enabled` — redeclaring it would clash.)
    property bool dynamicEnabled: false
    // Base name for auto-created desktops ("" = use defaultPrefix); the controller appends the number.
    property string namePrefix: ""
    // The i18n default base name ("Desktop"), passed IN so this file stays i18n-free (logic.js and the
    // controller are headless-tested where the i18n* globals don't exist). KWin silently drops
    // createDesktop with an empty name, so formatDynamicDesktopName guarantees a non-empty "<base> N".
    property string defaultPrefix: "Desktop"
    // The reactive read-only desktop state (a VirtualDesktopInfo), injected — null-safe throughout
    // (it can be transiently absent during a desktop add/remove or shell reload).
    property var virtualDesktopInfo: null
    // Per-desktop occupancy bool[], index-aligned with virtualDesktopInfo.desktopIds (from the shared
    // WindowAggregator). The length guard in Logic.dynamicWorkspacePlan makes a transient frame — where
    // this still lags a just-changed desktop set — a no-op until it catches up.
    property var desktopOccupancy: []

    // ── Outputs (the two things only the e2e boundary in main.qml can actually do) ──────────────────
    // A built KWin add/remove spec to issue (main.qml: root.dispatch(spec)).
    signal dispatchRequested(var spec)
    // Mirror the one global setting into this instance's persisted config (main.qml writes Plasmoid.configuration).
    signal syncConfigRequested(bool nextEnabled, string nextPrefix)

    // ── Internal state ─────────────────────────────────────────────────────────────────────────────
    property bool dynBusy: false
    property int dynToken: 0
    // Busy-lock fallback: how long to suppress re-firing after our own write before assuming the
    // desktopIdsChanged confirmation was lost. Comfortably longer than KWin's add/remove round-trip
    // (which normally clears the lock first, via the Connections below) but short enough that a missed
    // signal can't wedge the controller for a noticeable time.
    readonly property int busyFallbackMs: 750

    Timer {
        id: dynBusyTimer
        interval: controller.busyFallbackMs
        onTriggered: controller.dynBusy = false
    }

    // Join the coordinator (registering how it pushes the global value to us: as syncConfigRequested).
    // If a sibling already established the global, adopt it; otherwise we are first and seed it from our
    // own value. Then evaluate once (the last desktop may already be occupied at startup). Leave on
    // teardown so a removed panel stops counting in the election.
    Component.onCompleted: {
        controller.dynToken = Coordinator.join((en, pf) => controller.syncConfigRequested(en, pf));
        if (Coordinator.haveGlobal())
            controller.syncConfigRequested(Coordinator.globalEnabled(), Coordinator.globalPrefix());
        else
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }
    Component.onDestruction: Coordinator.leave(controller.dynToken)

    // Our setting changed. If it differs from the established global, WE changed it (the user toggled
    // this panel) → publish to every panel. If it already matches the global, this was a sync echo →
    // just re-evaluate. Guarded against the pre-join window: config bindings (and their onChanged) fire
    // before Component.onCompleted, so dynToken is still 0 (its "not joined yet" sentinel) — publishing
    // then would register a phantom value before join and stall the real writer (a previously-real bug).
    function publishDynamicConfig() {
        if (controller.dynToken === 0)
            return;
        if (!Coordinator.haveGlobal()
                || controller.dynamicEnabled !== Coordinator.globalEnabled()
                || controller.namePrefix !== Coordinator.globalPrefix())
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }

    // Coalesce a burst of occupancy / desktop-set changes into ONE evaluation next tick. A cheap no-op
    // when the feature is off.
    function scheduleDynamic() {
        if (!controller.dynamicEnabled)
            return;
        Qt.callLater(controller.evaluateDynamic);
    }

    // Compute and dispatch the single dynamic-workspace action for the FRESHEST state, or do nothing.
    // Only the elected writer acts (Coordinator.isWriter), so multiple panels never double-add. The
    // length guard inside dynamicWorkspacePlan makes a transient frame — where desktopOccupancy still
    // lags a just-changed desktop set — a no-op until occupancy catches up.
    function evaluateDynamic() {
        if (!controller.dynamicEnabled || controller.dynBusy)
            return;
        if (!Coordinator.isWriter(controller.dynToken))
            return;                              // another panel instance is the single global writer
        const ids = controller.virtualDesktopInfo?.desktopIds ?? [];
        const plan = Logic.dynamicWorkspacePlan(controller.desktopOccupancy, ids);
        if (!plan)
            return;
        let spec = null;
        if (plan.kind === "add") {
            // Name auto-created desktops "<prefix> N" (prefix synced across panels, default the i18n
            // "Desktop"). position == current count (append at end), so the new desktop's number is pos + 1.
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

    // Triggers: occupancy flips (a window opened/closed/moved), and our own setting changing (route
    // through publishDynamicConfig so the global stays in sync before we act).
    onDesktopOccupancyChanged: controller.scheduleDynamic()
    onDynamicEnabledChanged: controller.publishDynamicConfig()
    onNamePrefixChanged: controller.publishDynamicConfig()

    // The desktop SET changing is also the signal that OUR own add/remove landed → clear the busy-lock
    // and re-evaluate (so a multi-step trim of several trailing empties converges over a few cycles).
    Connections {
        target: controller.virtualDesktopInfo
        function onDesktopIdsChanged() {
            controller.dynBusy = false;
            controller.scheduleDynamic();
        }
    }
}
