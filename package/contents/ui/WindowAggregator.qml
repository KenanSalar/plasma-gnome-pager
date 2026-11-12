/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The widget's one TasksModel, filtered by neither desktop nor activity, reduced per desktop into the
 * tooltip text and two occupancy arrays. Each consumer switches its own reduction on. The tooltip text
 * is translated and marked up here, since logic.mjs has no i18n.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import org.kde.taskmanager as TaskManager

import "logic.mjs" as Logic

Item {
    id: aggregator

    property var virtualDesktopInfo: null

    // One switch per consumer: one that's off keeps its output at [] and its roles wake no rebuild.
    property bool windowListActive: true
    property bool occupancyActive: false
    property bool dynamicActive: false

    // A zero rect counts windows on every screen.
    property rect screenRect: Qt.rect(0, 0, 0, 0)

    property var desktopTooltips: []
    property var desktopOccupancy: []   // every screen and activity, for the dynamic controller
    property var screenOccupancy: []    // this screen in the current activity, for the markers

    // Named so objectAt(i) can be cast to it. A capitalised role isn't a valid property name, so those
    // are read off model.
    component WindowRow: QtObject {
        required property var model
        required property string display
        readonly property var windowDesktops: model.VirtualDesktops
        readonly property bool onAllDesktops: model.IsOnAllVirtualDesktops
        readonly property bool minimized: model.IsMinimized
        readonly property bool isWindow: model.IsWindow   // false for launchers and starting apps
        readonly property bool skipPager: model.SkipPager
        // var, not rect: a window without an output reads undefined, which a rect refuses with a warning
        // and answers by keeping the previous screen.
        readonly property var windowScreen: model.ScreenGeometry
        readonly property var windowActivities: model.Activities
    }

    // The tooltip and the markers show only the current activity.
    readonly property bool activityFiltered: aggregator.windowListActive || aggregator.occupancyActive

    TaskManager.ActivityInfo {
        id: activityInfo
    }
    // Unfiltered by activity: dynamic workspaces must count every activity's windows, or they remove a
    // desktop another activity still uses (#35).
    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
    }

    // The roles a rebuild reads for the consumers that are on. Window focus touches none of them, so its
    // constant churn never wakes a rebuild.
    readonly property var relevantRoles: {
        var roles = [
            TaskManager.AbstractTasksModel.VirtualDesktops,
            TaskManager.AbstractTasksModel.IsOnAllVirtualDesktops,
            TaskManager.AbstractTasksModel.IsWindow
        ];
        if (aggregator.windowListActive)
            roles.push(Qt.DisplayRole, TaskManager.AbstractTasksModel.IsMinimized);
        if (aggregator.occupancyActive || aggregator.dynamicActive)
            roles.push(TaskManager.AbstractTasksModel.SkipPager);
        if (aggregator.occupancyActive)
            roles.push(TaskManager.AbstractTasksModel.ScreenGeometry);
        if (aggregator.activityFiltered)
            roles.push(TaskManager.AbstractTasksModel.Activities);
        return roles;
    }

    // A C++ model has no get(i), so the rows are built to be read by role name.
    Instantiator {
        id: winInstantiator
        model: tasksModel
        delegate: WindowRow {}
        onObjectAdded: aggregator.scheduleRebuild()
        onObjectRemoved: aggregator.scheduleRebuild()
    }

    Connections {
        target: tasksModel
        function onDataChanged(topLeft, bottomRight, roles) {
            if (Logic.dataChangeAffectsRoles(roles, aggregator.relevantRoles))
                aggregator.scheduleRebuild();
        }
        function onModelReset() {
            aggregator.scheduleRebuild();
        }
    }
    Connections {
        target: aggregator.virtualDesktopInfo
        function onDesktopIdsChanged() {
            aggregator.scheduleRebuild();
        }
    }
    // A reorder emits only this (Plasma 6.5 and later). The indicator re-reads the order in the same
    // emission, so a deferred rebuild would leave a frame of occupancy on the wrong dots.
    Connections {
        target: aggregator.virtualDesktopInfo
        ignoreUnknownSignals: true
        function onDesktopPositionsChanged() {
            aggregator.rebuild();
        }
    }
    // An activity switch changes no rows of an unfiltered model.
    Connections {
        target: activityInfo
        function onCurrentActivityChanged() {
            if (aggregator.activityFiltered)
                aggregator.scheduleRebuild();
        }
    }

    // One rebuild for a burst of signals. Unloading clears this context before deleting the item: a
    // pending Qt.callLater still runs and can't call the item's functions, while this handler doesn't.
    Timer {
        id: rebuildTimer
        interval: 0
        onTriggered: aggregator.rebuild()
    }

    function scheduleRebuild() {
        rebuildTimer.start();
    }

    function rebuild() {
        const ids = aggregator.virtualDesktopInfo?.desktopIds ?? [];
        const reduced = Logic.reduceWindowSnapshot(aggregator.snapshotWindows(), ids, {
            windowList: aggregator.windowListActive,
            occupancy: aggregator.occupancyActive,
            dynamic: aggregator.dynamicActive,
            screenRect: aggregator.screenRect,
            activity: activityInfo.currentActivity
        });

        const tooltips = reduced.groups.map(aggregator.formatSubText);
        if (!Logic.arraysShallowEqual(tooltips, aggregator.desktopTooltips))
            aggregator.desktopTooltips = tooltips;
        if (!Logic.arraysShallowEqual(reduced.occupancy, aggregator.desktopOccupancy))
            aggregator.desktopOccupancy = reduced.occupancy;
        if (!Logic.arraysShallowEqual(reduced.screenOccupancy, aggregator.screenOccupancy))
            aggregator.screenOccupancy = reduced.screenOccupancy;
    }

    // The UUID lists arrive as variant wrappers, so they're stringified before logic.mjs compares them.
    function snapshotWindows() {
        const windows = [];
        for (let i = 0; i < winInstantiator.count; ++i) {
            const row = winInstantiator.objectAt(i) as WindowRow;
            if (!row)
                continue;
            windows.push({
                title: row.display || "",
                minimized: row.minimized,
                onAll: row.onAllDesktops,
                isWindow: row.isWindow,
                skipPager: row.skipPager,
                desktops: (row.windowDesktops || []).map(uuid => String(uuid)),
                activities: (row.windowActivities || []).map(uuid => String(uuid)),
                // A QRect isn't a plain JS value; null counts the window on every screen.
                screen: row.windowScreen ? { x: row.windowScreen.x, y: row.windowScreen.y, width: row.windowScreen.width, height: row.windowScreen.height } : null
            });
        }
        return windows;
    }

    function titleHtml(title) {
        return Logic.sanitizeHtml(title.length ? title : i18nc("@item:intext window with no title", "Untitled Window"));
    }

    // The stock pager's list: up to Logic.windowListMaximum titles, then "…and N other windows".
    function formatList(titles) {
        const total = titles.length;
        const max = Logic.windowListMaximum(total);
        let html = "<ul><li>" + titles.slice(0, max).map(title => aggregator.titleHtml(title)).join("</li><li>") + "</li></ul>";
        if (total > max)
            html += i18ncp("@info:tooltip overflow label", "…and %1 other window", "…and %1 other windows", total - max);
        return html;
    }

    // Laid out as the stock pager's tooltip is; the leading <style> drops the list's default margin.
    function formatSubText(group) {
        let html = "";
        if (group.visible.length === 1)
            html += aggregator.titleHtml(group.visible[0]);
        else if (group.visible.length > 1)
            html += i18ncp("@info:tooltip start of list", "%1 Window:", "%1 Windows:", group.visible.length) + aggregator.formatList(group.visible);
        if (group.visible.length && group.minimized.length)
            html += group.visible.length === 1 ? "<br><br>" : "<br>";
        if (group.minimized.length > 0)
            html += i18ncp("@info:tooltip", "%1 Minimized Window:", "%1 Minimized Windows:", group.minimized.length) + aggregator.formatList(group.minimized);
        return html.length ? "<style>ul { margin: 0; }</style>" + html : "";
    }

    // Switching a consumer on fills its output, switching it off empties it.
    onWindowListActiveChanged: aggregator.scheduleRebuild()
    onOccupancyActiveChanged: aggregator.scheduleRebuild()
    onDynamicActiveChanged: aggregator.scheduleRebuild()

    // The panel moved to another screen.
    onScreenRectChanged: if (aggregator.occupancyActive) aggregator.scheduleRebuild()

    Component.onCompleted: aggregator.rebuild()
}
