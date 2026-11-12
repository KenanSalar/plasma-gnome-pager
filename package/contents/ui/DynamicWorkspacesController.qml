/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * GNOME-style dynamic workspaces: keeps one empty desktop at the end, one KWin write at a time. The
 * desktops are shared by every panel, so coordinator.mjs lets one instance write and keeps the setting
 * the same everywhere. The writes and the config go out as signals for main.qml to carry out.
 */
pragma ComponentBehavior: Bound

import QtQuick

import "logic.mjs" as Logic
import "coordinator.mjs" as Coordinator

Item {
    id: controller

    property bool dynamicEnabled: false
    property string namePrefix: ""              // "" uses defaultPrefix
    property string defaultPrefix: "Desktop"    // translated by main.qml, which has i18n
    property var virtualDesktopInfo: null
    property var desktopOccupancy: []           // every screen and activity, index-aligned with desktopIds

    signal dispatchRequested(var spec)
    signal syncConfigRequested(bool nextEnabled, string nextPrefix)

    property bool dynBusy: false
    property int dynToken: 0                    // 0 until join()
    // Only for a write that never lands; desktopIdsChanged normally clears the lock.
    readonly property int busyFallbackMs: 750

    Timer {
        id: dynBusyTimer
        interval: controller.busyFallbackMs
        onTriggered: controller.dynBusy = false
    }

    // The first instance seeds the global setting from its own config; the rest adopt it.
    Component.onCompleted: {
        controller.dynToken = Coordinator.join((en, pf) => controller.syncConfigRequested(en, pf));
        if (Coordinator.haveGlobal())
            controller.syncConfigRequested(Coordinator.globalEnabled(), Coordinator.globalPrefix());
        else
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }
    Component.onDestruction: Coordinator.leave(controller.dynToken)

    // A value that differs from the global came from this panel's settings; an equal one is the sync's
    // echo. Config onChanged runs before Component.onCompleted, and a publish with token 0 would register
    // a phantom instance that wins the election.
    function publishDynamicConfig() {
        if (controller.dynToken === 0)
            return;
        if (!Coordinator.haveGlobal()
                || controller.dynamicEnabled !== Coordinator.globalEnabled()
                || controller.namePrefix !== Coordinator.globalPrefix())
            Coordinator.publish(controller.dynamicEnabled, controller.namePrefix);
        controller.scheduleDynamic();
    }

    // One evaluation for a burst of changes.
    function scheduleDynamic() {
        if (!controller.dynamicEnabled)
            return;
        Qt.callLater(controller.evaluateDynamic);
    }

    function evaluateDynamic() {
        if (!controller.dynamicEnabled || controller.dynBusy)
            return;
        if (!Coordinator.isWriter(controller.dynToken))
            return;
        const ids = controller.virtualDesktopInfo?.desktopIds ?? [];
        const plan = Logic.dynamicWorkspacePlan(controller.desktopOccupancy, ids);
        if (!plan)
            return;
        let spec = null;
        if (plan.kind === "add") {
            // Appended at the end, so the new desktop's number is its position plus one.
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

    onDesktopOccupancyChanged: controller.scheduleDynamic()
    onDynamicEnabledChanged: controller.publishDynamicConfig()
    onNamePrefixChanged: controller.publishDynamicConfig()

    // The set changing is how a write of ours shows it landed; removing several surplus desktops takes
    // one round each.
    Connections {
        target: controller.virtualDesktopInfo
        function onDesktopIdsChanged() {
            controller.dynBusy = false;
            controller.scheduleDynamic();
        }
    }
}
