/*
 * Plasma Gnome Pager — main.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Root PlasmoidItem: owns the virtual-desktop data source (read) and the KWin DBus helpers (write),
 * and renders the dot strip inline in the panel. This is the e2e boundary (not headless-testable).
 */
pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.plasmoid

// Public, stable imports only — never org.kde.plasma.private.* (robustness.md).
import org.kde.plasma.core as PlasmaCore         // PlasmaCore.Action + PlasmaCore.Types
import org.kde.taskmanager as TaskManager        // VirtualDesktopInfo + TasksModel/ActivityInfo (read)
import org.kde.plasma.workspace.dbus as DBus     // KWin DBus (switch/add/remove/rename)

import "logic.js" as Logic

PlasmoidItem {
    id: root

    Plasmoid.icon: "virtual-desktops"   // match metadata.json's Icon (theme-safe Breeze name)

    // Passive always-on widget, no background of its own (dots float on the panel — the GNOME look).
    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Panel orientation, passed DOWN as a plain bool so the sub-components stay Plasmoid-free. Planar/Floating → horizontal.
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Behaviour settings, read live from main.xml. Each `?? Logic.DEFAULTS` guards the transient-undefined frame (undefined → false).
    readonly property bool enableScroll: Plasmoid.configuration.enableScroll ?? Logic.DEFAULTS.enableScroll
    readonly property bool scrollWrap: Plasmoid.configuration.scrollWrap ?? Logic.DEFAULTS.scrollWrap
    readonly property bool invertScroll: Plasmoid.configuration.invertScroll ?? Logic.DEFAULTS.invertScroll
    readonly property bool showTooltips: Plasmoid.configuration.showTooltips ?? Logic.DEFAULTS.showTooltips
    readonly property bool showWindowList: Plasmoid.configuration.showWindowList ?? Logic.DEFAULTS.showWindowList
    readonly property bool enableAddRemove: Plasmoid.configuration.enableAddRemove ?? Logic.DEFAULTS.enableAddRemove
    readonly property bool enableRename: Plasmoid.configuration.enableRename ?? Logic.DEFAULTS.enableRename
    // Dynamic workspaces (default OFF): auto-keep one empty trailing desktop; dynamicNamePrefix is the created-desktop base name ("" = "Desktop").
    readonly property bool dynamicWorkspaces: Plasmoid.configuration.dynamicWorkspaces ?? Logic.DEFAULTS.dynamicWorkspaces
    readonly property string dynamicNamePrefix: Plasmoid.configuration.dynamicNamePrefix ?? Logic.DEFAULTS.dynamicNamePrefix

    // Manual Add/Remove only when enabled AND dynamic workspaces off — the two conflict. Reused by the contextualActions below.
    readonly property bool canAddRemove: enableAddRemove && !dynamicWorkspaces

    // Appearance/animation settings, read the same way. dotSize/pillSize/animationDuration use a 0 = auto sentinel resolved in the indicator/dot.
    readonly property int animationDuration: Plasmoid.configuration.animationDuration ?? Logic.DEFAULTS.animationDuration
    readonly property int dotSize: Plasmoid.configuration.dotSize ?? Logic.DEFAULTS.dotSize
    readonly property int pillSize: Plasmoid.configuration.pillSize ?? Logic.DEFAULTS.pillSize
    readonly property real spacingFactor: Plasmoid.configuration.spacingFactor ?? Logic.DEFAULTS.spacingFactor
    readonly property real pillWidthFactor: Plasmoid.configuration.pillWidthFactor ?? Logic.DEFAULTS.pillWidthFactor
    readonly property real inactiveOpacity: Plasmoid.configuration.inactiveOpacity ?? Logic.DEFAULTS.inactiveOpacity
    readonly property real hoverOpacity: Plasmoid.configuration.hoverOpacity ?? Logic.DEFAULTS.hoverOpacity
    readonly property bool followThemeColors: Plasmoid.configuration.followThemeColors ?? Logic.DEFAULTS.followThemeColors
    readonly property color activeColor: Plasmoid.configuration.activeColor ?? Logic.DEFAULTS.activeColor
    readonly property color inactiveColor: Plasmoid.configuration.inactiveColor ?? Logic.DEFAULTS.inactiveColor

    // A pager renders inline. Plasma instantiates NO representation unless a fullRepresentation exists, so
    // the dot strip IS the full representation, forced inline via preferredRepresentation.
    preferredRepresentation: fullRepresentation
    fullRepresentation: WorkspaceIndicator {
        vertical: root.isVertical
        virtualDesktopInfo: vdi
        enableScroll: root.enableScroll
        scrollWrap: root.scrollWrap
        invertScroll: root.invertScroll
        showTooltips: root.showTooltips
        desktopTooltips: root.desktopTooltips

        // dotSize/pillSize passed as raw 0=auto requests; resolved in the indicator (pillSize 0 = match dots).
        dotSizeRequest: root.dotSize
        pillSizeRequest: root.pillSize
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

    // Reactive read-only desktop state — bind, never cache; updates on ANY change. Writes go through KWin DBus below.
    TaskManager.VirtualDesktopInfo {
        id: vdi
    }

    // Per-desktop tooltip subText (rich-text window list), gated by showTooltips && showWindowList INDEPENDENTLY of the Loader.
    readonly property var desktopTooltips: (root.showTooltips && root.showWindowList && tooltipLoader.item)
        ? (tooltipLoader.item as WindowAggregator).desktopTooltips : []

    // Per-desktop occupancy boolean[] from the SAME snapshot, consumed by the dynamic-workspaces controller. Empty [] when the Loader is inactive.
    readonly property var desktopOccupancy: tooltipLoader.item ? (tooltipLoader.item as WindowAggregator).desktopOccupancy : []

    // The window-list machinery lives behind a Loader (zero cost when unused). Needed by the tooltip list OR dynamic workspaces — gate is the OR.
    Loader {
        id: tooltipLoader
        active: (root.showTooltips && root.showWindowList) || root.dynamicWorkspaces
        sourceComponent: aggregatorComponent
    }
    Component {
        id: aggregatorComponent
        WindowAggregator {
            virtualDesktopInfo: vdi   // inject the read source (the aggregator is data-source-agnostic)
            // windowListActive false → aggregator is live only for occupancy, skipping the discarded tooltip work.
            windowListActive: root.showTooltips && root.showWindowList
        }
    }

    // Every desktop write goes through KWin's VirtualDesktopManager. The CALL SHAPES live in logic.js's
    // *Spec builders; here we only DISPATCH a built spec (async fire-and-forget). A null spec is a no-op.
    function dispatch(spec) {
        if (!spec) {
            return;
        }
        DBus.SessionBus.asyncCall({
            "service": spec.service,
            "path": spec.path,
            "iface": spec.iface,
            "member": spec.member,
            "arguments": spec.args.map(a => root.toDBusArg(a))
        });
    }

    // Map ONE spec arg { t, v } to its DBus.* constructor. The "v" case wraps a PLAIN value — a wrapped DBus.string is silently rejected by KWin.
    function toDBusArg(a) {
        switch (a.t) {
        case "s":
            return new DBus.string(a.v);
        case "u":
            return new DBus.uint32(a.v);
        case "i":
            return new DBus.int32(a.v);
        case "v":
            return new DBus.variant(a.v);
        default:
            // Unknown type letter: warn LOUDLY rather than fail silently (the silent-DBus-drop class this widget avoids).
            console.warn("plasma-gnome-pager: toDBusArg got unknown DBus type letter", a.t);
            return a.v;
        }
    }

    function switchTo(uuid) {
        root.dispatch(Logic.switchSpec(uuid));
    }

    // Append a new desktop at the end. `?? 0` keeps a transient-undefined count out of the uint32 (i18n label stays here).
    function addDesktop() {
        root.dispatch(Logic.addSpec(vdi.numberOfDesktops ?? 0, i18n("New Desktop")));
    }

    // Remove a desktop by UUID. removeSpec enforces never-remove-last (returns null).
    function removeDesktop(uuid) {
        root.dispatch(Logic.removeSpec(uuid, vdi.numberOfDesktops));
    }

    // "Remove" targets the last desktop (the one addDesktop appended).
    function removeLastDesktop() {
        root.removeDesktop(Logic.lastDesktopId(vdi.desktopIds));
    }

    // Dynamic workspaces (GNOME-style): one GLOBAL behaviour keeping an empty trailing desktop. The non-visual controller emits the two signals below.
    DynamicWorkspacesController {
        id: dynamicController

        dynamicEnabled: root.dynamicWorkspaces
        namePrefix: root.dynamicNamePrefix
        // i18n default base name, passed IN so the controller stays i18n-free (never empty — KWin drops createDesktop on an empty name).
        defaultPrefix: i18nc("@info default base name for auto-created virtual desktops", "Desktop")
        virtualDesktopInfo: vdi
        desktopOccupancy: root.desktopOccupancy

        onDispatchRequested: spec => root.dispatch(spec)
        onSyncConfigRequested: (nextEnabled, nextPrefix) => {
            // Mirror the global setting into this instance's persisted config (value-guarded so sync→onChanged→publish can't loop).
            if (Plasmoid.configuration.dynamicWorkspaces !== nextEnabled)
                Plasmoid.configuration.dynamicWorkspaces = nextEnabled;
            if (Plasmoid.configuration.dynamicNamePrefix !== nextPrefix)
                Plasmoid.configuration.dynamicNamePrefix = nextPrefix;
        }
    }

    // Rename a desktop via KWin setDesktopName. renameSpec sanitizes and rejects empty (null → no-op); `vdi` reports the new name.
    function renameDesktop(uuid, name) {
        root.dispatch(Logic.renameSpec(uuid, name));
    }

    // Open the rename prompt prefilled with the desktop's current name (resolved from the live vdi arrays, guarded for the transient frame).
    function openRenameDialog(uuid) {
        if (!uuid) {
            return;
        }
        const ids = vdi.desktopIds ?? [];
        const names = vdi.desktopNames ?? [];
        renameDialog.openFor(uuid, names[ids.indexOf(uuid)] ?? "");
    }

    // Right-click menu. Add/Remove gated by canAddRemove (they conflict with dynamic workspaces); Remove
    // also disables at the last desktop. ("Configure…" is auto-added by Plasma.)
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Add Desktop")
            icon.name: "list-add"
            priority: Plasmoid.LowPriorityAction
            visible: root.canAddRemove
            enabled: root.canAddRemove
            onTriggered: root.addDesktop()
        },
        PlasmaCore.Action {
            text: i18n("Remove Last Desktop")
            icon.name: "list-remove"
            priority: Plasmoid.LowPriorityAction
            visible: root.canAddRemove
            enabled: root.canAddRemove && Logic.canRemoveDesktop(vdi.numberOfDesktops)
            onTriggered: root.removeLastDesktop()
        },
        PlasmaCore.Action {
            text: i18n("Rename Current Desktop…")
            icon.name: "edit-rename"
            priority: Plasmoid.LowPriorityAction
            visible: root.enableRename
            enabled: root.enableRename
            onTriggered: root.openRenameDialog(vdi.currentDesktop)
        }
    ]

    // Rename prompt — the view lives in RenameDialog.qml; here we only place it and turn accepted() into the KWin write.
    RenameDialog {
        id: renameDialog
        visualParent: root.fullRepresentationItem
        location: Plasmoid.location
        onAccepted: (uuid, name) => root.renameDesktop(uuid, name)
    }
}
