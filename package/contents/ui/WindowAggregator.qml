/*
 * Plasma Gnome Pager — WindowAggregator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The window aggregator — a non-visual zero-size Item (Loader.item must be a QQuickItem, not a bare
 * QtObject). ONE unfiltered public TasksModel feeds BOTH features from a single snapshot via pure JS
 * (Logic.groupWindowsByDesktop for the tooltip window list, Logic.computeDesktopOccupancy for dynamic
 * workspaces), not N filtered models, so the grouping stays headless-unit-tested. GroupDisabled →
 * one row per window (an accurate per-desktop count); filterByActivity keeps other activities'
 * windows out of the lists (so occupancy is current-activity — see CLAUDE.md / the plan's trade-off).
 *
 * Lives in its own file (loaded behind a Loader in main.qml) rather than inline so main.qml stays
 * lean and this data-source+i18n unit is isolated. The reactive desktop set is INJECTED as the
 * `virtualDesktopInfo` property (not closure-captured), exactly like the indicator reads it; the
 * i18n + HTML formatting stays here because logic.js is i18n-free (it returns raw window data and the
 * presentation happens at this e2e boundary). This file is not headless-testable (it needs live
 * Plasma models); the grouping/truncation it calls IS unit-tested in logic.js.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQml                                      // Instantiator (materialise TasksModel rows)
import org.kde.taskmanager as TaskManager        // TasksModel/ActivityInfo (read)

import "logic.js" as Logic

Item {
    id: aggregator

    // The reactive read-only desktop state (a VirtualDesktopInfo), injected by main.qml. Null-safe
    // throughout: it can be transiently absent during a desktop add/remove or shell reload.
    property var virtualDesktopInfo: null

    property var desktopTooltips: []
    property var desktopOccupancy: []

    // One materialised TasksModel row, as a NAMED inline component so objectAt(i) can be `as`-cast to it
    // for typed (lint-clean) role access — the stock pager's `itemAt(i) as WindowDelegate` idiom. The
    // capitalised TasksModel roles aren't valid lowercase identifiers, so they can't be required
    // properties; read them off the var `model` (only the lowercase `display` role is a required property).
    component WindowRow: QtObject {
        required property var model
        required property string display                  // window title (Qt::DisplayRole)
        readonly property var windowDesktops: model.VirtualDesktops
        readonly property bool onAllDesktops: model.IsOnAllVirtualDesktops
        readonly property bool minimized: model.IsMinimized
        readonly property bool isWindow: model.IsWindow   // false for launchers / startup tasks
        readonly property bool skipPager: model.SkipPager // hidden from pagers — never counts as occupying a desktop
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

    // The exact role ints rebuild() reads — title + the four taskmanager roles below — built from
    // the PUBLIC org.kde.taskmanager enum (already imported; robustness.md). dataChanged for any
    // OTHER role leaves desktopTooltips byte-identical, so we skip the rebuild — most importantly
    // IsActive, which KWin emits on EVERY window-focus change (the losing AND gaining window), plus
    // StackingOrder/Geometry/IsDemandingAttention/icon. Qt::DisplayRole (== 0) is the window title.
    readonly property var relevantRoles: [
        Qt.DisplayRole,
        TaskManager.AbstractTasksModel.VirtualDesktops,
        TaskManager.AbstractTasksModel.IsOnAllVirtualDesktops,
        TaskManager.AbstractTasksModel.IsMinimized,
        TaskManager.AbstractTasksModel.IsWindow,
        TaskManager.AbstractTasksModel.SkipPager     // occupancy ignores pager-hidden windows
    ]

    // Materialise the rows so objectAt(i) can read role values by name (a C++ QAbstractItemModel has
    // no model.get(i)). Row add/remove triggers a rebuild here; role-value changes (title rename,
    // minimise, desktop move) arrive via the model's dataChanged below.
    Instantiator {
        id: winInstantiator
        model: tasksModel
        delegate: WindowRow {}
        onObjectAdded: aggregator.scheduleRebuild()
        onObjectRemoved: aggregator.scheduleRebuild()
    }

    // Rebuild when a role rebuild() actually reads changes (title/desktop/minimise — Logic filters
    // out the IsActive focus churn etc. against relevantRoles; an empty roles list is Qt's "all
    // changed" and rebuilds), or on a full reset, or when the desktop SET changes (the index
    // alignment shifts). All funnel through the debounced scheduleRebuild so a burst collapses to
    // one rebuild per frame.
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

    // Coalesce a burst of change signals into ONE rebuild per frame — never per signal. No binding
    // loop: the rows read the model, rebuild() writes desktopTooltips, and the dots only read it.
    function scheduleRebuild() {
        Qt.callLater(aggregator.rebuild);
    }

    // Snapshot the materialised rows into a plain JS array, group per desktop (pure logic.js), then
    // format each summary into the tooltip subText. The `as WindowRow` cast gives typed role access;
    // normalise VirtualDesktops to plain strings so the UUID compare against desktopIds can't silently
    // miss (variant wrappers).
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
        // Two pure reductions of the SAME snapshot: the tooltip window list (includes on-all windows,
        // the stock-pager look) and dynamic-workspace occupancy (excludes on-all/skipPager). Set both
        // so the feature works even when the window-list tooltip is off (the Loader gate is the OR).
        aggregator.desktopTooltips = Logic.groupWindowsByDesktop(windows, ids).map(aggregator.formatSubText);
        aggregator.desktopOccupancy = Logic.computeDesktopOccupancy(windows, ids);
    }

    // One window title as escaped rich text, falling back to a localized "Untitled Window" for a
    // titleless window. Shared by formatList and formatSubText so the fallback is written once.
    function titleHtml(title) {
        return Logic.sanitizeHtml(title.length ? title : i18nc("@item:intext window with no title", "Untitled Window"));
    }

    // Build one desktop's window list as a rich-text <ul> capped at Logic.windowListMaximum, with an
    // "…and N other windows" overflow line — the stock pager's generateWindowList.
    function formatList(titles) {
        const total = titles.length;
        const max = Logic.windowListMaximum(total);
        let t = "<ul><li>" + titles.slice(0, max).map(x => aggregator.titleHtml(x)).join("</li><li>") + "</li></ul>";
        if (total > max)
            t += i18ncp("@info:tooltip overflow label", "…and %1 other window", "…and %1 other windows", total - max);
        return t;
    }

    // Assemble one desktop's tooltip subText from its { visible, minimized } summary — the stock
    // pager's updateSubTextIfNeeded: a single visible window shows just its title; >1 shows a
    // "%1 Windows:" header + the list; minimised windows get their own header + list; a <br>
    // separates the two sections. The leading <style> kills the <ul>'s default margin.
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

    Component.onCompleted: aggregator.rebuild()
}
