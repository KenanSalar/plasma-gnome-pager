/*
 * Plasma Gnome Pager — WindowAggregator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The window aggregator — a non-visual Item. ONE unfiltered public TasksModel feeds BOTH the tooltip
 * window list and dynamic-workspace occupancy from a single snapshot via pure JS. The desktop set is
 * INJECTED as `virtualDesktopInfo`; i18n + HTML formatting stays here (logic.js is i18n-free), so e2e-only.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQml                                      // Instantiator (materialise TasksModel rows)
import org.kde.taskmanager as TaskManager        // TasksModel/ActivityInfo (read)

import "logic.js" as Logic

Item {
    id: aggregator

    // The read source (a VirtualDesktopInfo), injected by main.qml. Null-safe throughout (transiently absent).
    property var virtualDesktopInfo: null

    // The per-dot window-list tooltip wanted? Injected as (showTooltips && showWindowList). When false the
    // aggregator is live only for occupancy, skipping tooltip work (drops title/minimise roles; empty tooltips).
    property bool windowListActive: true

    property var desktopTooltips: []
    property var desktopOccupancy: []

    // One materialised TasksModel row, a NAMED inline component so objectAt(i) can be `as`-cast for typed role access (capitalised roles read off `model`).
    component WindowRow: QtObject {
        required property var model
        required property string display                  // window title (Qt::DisplayRole)
        readonly property var windowDesktops: model.VirtualDesktops
        readonly property bool onAllDesktops: model.IsOnAllVirtualDesktops
        readonly property bool minimized: model.IsMinimized
        readonly property bool isWindow: model.IsWindow   // false for launchers / startup tasks
        readonly property bool skipPager: model.SkipPager // hidden from pagers — never occupies a desktop
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }
    TaskManager.TasksModel {
        id: tasksModel
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: true
        activity: activityInfo.currentActivity
    }

    // The role ints rebuild() reads (PUBLIC enum); other roles are skipped (notably the IsActive focus churn).
    // CONDITIONAL on windowListActive: occupancy needs only the four desktop/window roles (off → drop title + IsMinimized).
    readonly property var relevantRoles: aggregator.windowListActive ? [
        Qt.DisplayRole,
        TaskManager.AbstractTasksModel.VirtualDesktops,
        TaskManager.AbstractTasksModel.IsOnAllVirtualDesktops,
        TaskManager.AbstractTasksModel.IsMinimized,
        TaskManager.AbstractTasksModel.IsWindow,
        TaskManager.AbstractTasksModel.SkipPager
    ] : [
        TaskManager.AbstractTasksModel.VirtualDesktops,
        TaskManager.AbstractTasksModel.IsOnAllVirtualDesktops,
        TaskManager.AbstractTasksModel.IsWindow,
        TaskManager.AbstractTasksModel.SkipPager     // occupancy-only: ignores title/minimised
    ]

    // Materialise the rows so objectAt(i) can read role values by name (a C++ model has no model.get(i)).
    // Row add/remove triggers a rebuild; role-value changes arrive via the model's dataChanged below.
    Instantiator {
        id: winInstantiator
        model: tasksModel
        delegate: WindowRow {}
        onObjectAdded: aggregator.scheduleRebuild()
        onObjectRemoved: aggregator.scheduleRebuild()
    }

    // Rebuild on a relevant role change, a full reset, or a desktop-SET change. All funnel through the debounced scheduleRebuild.
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

    // Coalesce a burst of change signals into ONE rebuild per frame. No loop: rows read the model, rebuild() writes, the dots only read.
    function scheduleRebuild() {
        Qt.callLater(aggregator.rebuild);
    }

    // Snapshot the materialised rows into a plain JS array, group per desktop (pure logic.js), then format each
    // summary. `as WindowRow` gives typed access; normalise VirtualDesktops to plain strings (variant wrappers).
    function rebuild() {
        let windows = [];
        for (let i = 0; i < winInstantiator.count; ++i) {
            const o = winInstantiator.objectAt(i) as WindowRow;
            if (!o)
                continue;
            windows.push({
                title: o.display || "",
                minimized: o.minimized,
                onAll: o.onAllDesktops,
                isWindow: o.isWindow,
                skipPager: o.skipPager,
                desktops: (o.windowDesktops || []).map(x => String(x))
            });
        }
        const ids = aggregator.virtualDesktopInfo?.desktopIds ?? [];
        // Two reductions of the SAME snapshot. Compare-before-assign on BOTH (arraysShallowEqual) avoids waking downstream on an unchanged array.
        const tooltips = aggregator.windowListActive
            ? Logic.groupWindowsByDesktop(windows, ids).map(aggregator.formatSubText)
            : [];
        if (!Logic.arraysShallowEqual(tooltips, aggregator.desktopTooltips))
            aggregator.desktopTooltips = tooltips;

        const occupancy = Logic.computeDesktopOccupancy(windows, ids);
        if (!Logic.arraysShallowEqual(occupancy, aggregator.desktopOccupancy))
            aggregator.desktopOccupancy = occupancy;
    }

    // One window title as escaped rich text, falling back to a localized "Untitled Window" (shared fallback).
    function titleHtml(title) {
        return Logic.sanitizeHtml(title.length ? title : i18nc("@item:intext window with no title", "Untitled Window"));
    }

    // One desktop's window list as a rich-text <ul> capped at Logic.windowListMaximum + an "…and N other windows" overflow (stock pager's generateWindowList).
    function formatList(titles) {
        const total = titles.length;
        const max = Logic.windowListMaximum(total);
        let t = "<ul><li>" + titles.slice(0, max).map(x => aggregator.titleHtml(x)).join("</li><li>") + "</li></ul>";
        if (total > max)
            t += i18ncp("@info:tooltip overflow label", "…and %1 other window", "…and %1 other windows", total - max);
        return t;
    }

    // Assemble one desktop's subText from its { visible, minimized } summary (the stock pager's
    // updateSubTextIfNeeded). The leading <style> kills the <ul>'s default margin.
    function formatSubText(s) {
        let t = "";
        if (s.visible.length === 1)
            t += aggregator.titleHtml(s.visible[0]);
        else if (s.visible.length > 1)
            t += i18ncp("@info:tooltip start of list", "%1 Window:", "%1 Windows:", s.visible.length) + aggregator.formatList(s.visible);
        if (s.visible.length && s.minimized.length)
            t += s.visible.length === 1 ? "<br><br>" : "<br>";
        if (s.minimized.length > 0)
            t += i18ncp("@info:tooltip", "%1 Minimized Window:", "%1 Minimized Windows:", s.minimized.length) + aggregator.formatList(s.minimized);
        return t.length ? "<style>ul { margin: 0; }</style>" + t : "";
    }

    // Toggling the list at runtime changes both rebuild()'s output and its triggers, so force one rebuild on the flip (ON repopulates, OFF clears).
    onWindowListActiveChanged: aggregator.scheduleRebuild()

    Component.onCompleted: aggregator.rebuild()
}
