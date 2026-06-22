/*
 * Plasma Gnome Pager — WindowAggregator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The window aggregator — a non-visual zero-size Item (Loader.item must be a QQuickItem, not a bare
 * QtObject). ONE unfiltered public TasksModel feeds BOTH features from a single snapshot via pure JS
 * (Logic.groupWindowsByDesktop for the tooltip window list, Logic.computeDesktopOccupancy for dynamic
 * workspaces) rather than N filtered models, so the grouping stays headless-unit-tested. GroupDisabled
 * → one row per window; filterByActivity keeps other activities' windows out (occupancy is current-
 * activity). Loaded behind a Loader in main.qml so its cost is zero when neither feature needs it. The
 * desktop set is INJECTED as `virtualDesktopInfo`; i18n + HTML formatting stays here (logic.js is
 * i18n-free), so this file is not headless-testable, but the grouping/truncation it calls IS.
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

    // Does the user actually want the per-dot window-list tooltip? Injected by main.qml as
    // (showTooltips && showWindowList). The aggregator can be loaded purely for dynamic workspaces
    // (which needs only desktopOccupancy), so when this is false we skip ALL the tooltip work —
    // both the rebuild TRIGGERS (relevantRoles below drops the title/minimise roles occupancy never
    // reads) and the per-rebuild HTML formatting (rebuild() leaves desktopTooltips empty). main.qml
    // already discards the formatted strings in that case (its desktopTooltips binding is gated the
    // same way), so this only removes wasted work — never changes behaviour. Defaults true so the
    // aggregator is self-contained if a caller forgets to set it.
    property bool windowListActive: true

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

    // The role ints rebuild() reads, built from the PUBLIC org.kde.taskmanager enum (already
    // imported; robustness.md). dataChanged for any OTHER role leaves our output byte-identical, so
    // we skip the rebuild — most importantly IsActive, which KWin emits on EVERY window-focus change
    // (the losing AND gaining window), plus StackingOrder/Geometry/IsDemandingAttention/icon.
    //
    // The set is CONDITIONAL on windowListActive. Occupancy (computeDesktopOccupancy, the only output
    // when the window list is off) reads four roles — VirtualDesktops, IsOnAllVirtualDesktops,
    // IsWindow, SkipPager — and never the title or minimised state (a minimised window still occupies
    // its desktop, so windowOccupiesDesktop has no minimised check). The window LIST additionally
    // needs the title (Qt::DisplayRole == 0) and IsMinimized (the separate "minimised" tooltip
    // section). So when the list is off we drop those two, and the high-frequency title-rename /
    // minimise-toggle churn no longer wakes a (discarded) rebuild. relevantRoles re-evaluates when
    // windowListActive flips; onWindowListActiveChanged forces the one rebuild that flip needs.
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
        // Two pure reductions of the SAME snapshot. Occupancy (excludes on-all/skipPager) ALWAYS
        // feeds dynamic workspaces; the tooltip window list (includes on-all windows, the stock-pager
        // look) is built ONLY when the user wants it (windowListActive) — when the list is off main.qml
        // discards it, so building the N HTML <ul> strings would be pure waste on an always-on widget.
        // Compare-before-assign on BOTH: a `var`/object property notifies on every reassignment to a
        // fresh reference (which each freshly-built array is) — no contents compare — so re-assigning
        // an identical array would needlessly wake the dynamic controller (occupancy) or every dot's
        // tooltip binding (tooltips) on unrelated window churn. arraysShallowEqual keeps the old ref.
        const tooltips = aggregator.windowListActive
            ? Logic.groupWindowsByDesktop(windows, ids).map(aggregator.formatSubText)
            : [];
        if (!Logic.arraysShallowEqual(tooltips, aggregator.desktopTooltips))
            aggregator.desktopTooltips = tooltips;

        const occupancy = Logic.computeDesktopOccupancy(windows, ids);
        if (!Logic.arraysShallowEqual(occupancy, aggregator.desktopOccupancy))
            aggregator.desktopOccupancy = occupancy;
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

    // Toggling the window list at runtime changes BOTH what rebuild() produces (tooltips ⇄ []) and
    // which roles trigger it (relevantRoles), so force one rebuild on the flip: ON repopulates the
    // per-dot tooltips that were left empty, OFF clears them to []. Debounced like every other trigger.
    onWindowListActiveChanged: aggregator.scheduleRebuild()

    Component.onCompleted: aggregator.rebuild()
}
