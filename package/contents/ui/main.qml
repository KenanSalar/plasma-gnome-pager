/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The applet root and the only file that touches the Plasma session: it reads the settings and the
 * desktops, sends the KWin writes, and owns the context menu. Everything below it gets plain values,
 * which is why this file is tested only in a real shell.
 */
pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.plasmoid

import org.kde.plasma.core as PlasmaCore
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kcmutils as KCM

import "logic.mjs" as Logic

PlasmoidItem {
    id: root

    Plasmoid.icon: "virtual-desktops"   // metadata.json's Icon
    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // A planar or floating applet lays out like a horizontal panel.
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // A key can read back undefined for a frame, which a bool would turn into false.
    readonly property bool enableScroll: Plasmoid.configuration.enableScroll ?? Logic.DEFAULTS.enableScroll
    readonly property bool scrollWrap: Plasmoid.configuration.scrollWrap ?? Logic.DEFAULTS.scrollWrap
    readonly property bool invertScroll: Plasmoid.configuration.invertScroll ?? Logic.DEFAULTS.invertScroll
    readonly property int pillClickAction: Plasmoid.configuration.pillClickAction ?? Logic.DEFAULTS.pillClickAction
    readonly property bool pillClickAnywhere: Plasmoid.configuration.pillClickAnywhere ?? Logic.DEFAULTS.pillClickAnywhere
    readonly property bool showTooltips: Plasmoid.configuration.showTooltips ?? Logic.DEFAULTS.showTooltips
    readonly property bool showWindowList: Plasmoid.configuration.showWindowList ?? Logic.DEFAULTS.showWindowList
    readonly property bool enableAddRemove: Plasmoid.configuration.enableAddRemove ?? Logic.DEFAULTS.enableAddRemove
    readonly property bool enableRename: Plasmoid.configuration.enableRename ?? Logic.DEFAULTS.enableRename
    readonly property bool dynamicWorkspaces: Plasmoid.configuration.dynamicWorkspaces ?? Logic.DEFAULTS.dynamicWorkspaces
    readonly property string dynamicNamePrefix: Plasmoid.configuration.dynamicNamePrefix ?? Logic.DEFAULTS.dynamicNamePrefix

    // Dynamic workspaces would undo a manual add or remove at once.
    readonly property bool canAddRemove: enableAddRemove && !dynamicWorkspaces

    readonly property int animationDuration: Plasmoid.configuration.animationDuration ?? Logic.DEFAULTS.animationDuration
    readonly property int dotStyle: Plasmoid.configuration.dotStyle ?? Logic.DEFAULTS.dotStyle
    readonly property bool singleLine: Plasmoid.configuration.singleLine ?? Logic.DEFAULTS.singleLine
    readonly property bool matchDesktopGrid: Plasmoid.configuration.matchDesktopGrid ?? Logic.DEFAULTS.matchDesktopGrid
    readonly property int dotSize: Plasmoid.configuration.dotSize ?? Logic.DEFAULTS.dotSize
    readonly property int pillSize: Plasmoid.configuration.pillSize ?? Logic.DEFAULTS.pillSize
    readonly property real spacingFactor: Plasmoid.configuration.spacingFactor ?? Logic.DEFAULTS.spacingFactor
    readonly property real pillWidthFactor: Plasmoid.configuration.pillWidthFactor ?? Logic.DEFAULTS.pillWidthFactor
    readonly property real inactiveOpacity: Plasmoid.configuration.inactiveOpacity ?? Logic.DEFAULTS.inactiveOpacity
    readonly property real hoverOpacity: Plasmoid.configuration.hoverOpacity ?? Logic.DEFAULTS.hoverOpacity
    readonly property bool showHoverBackground: Plasmoid.configuration.showHoverBackground ?? Logic.DEFAULTS.showHoverBackground
    readonly property real hoverBackgroundOpacity: Plasmoid.configuration.hoverBackgroundOpacity ?? Logic.DEFAULTS.hoverBackgroundOpacity
    readonly property real hoverLengthFactor: Plasmoid.configuration.hoverLengthFactor ?? Logic.DEFAULTS.hoverLengthFactor
    readonly property real hoverThicknessFactor: Plasmoid.configuration.hoverThicknessFactor ?? Logic.DEFAULTS.hoverThicknessFactor
    readonly property bool showOccupancy: Plasmoid.configuration.showOccupancy ?? Logic.DEFAULTS.showOccupancy
    readonly property real occupiedOpacity: Plasmoid.configuration.occupiedOpacity ?? Logic.DEFAULTS.occupiedOpacity
    readonly property int occupancyStyle: Plasmoid.configuration.occupancyStyle ?? Logic.DEFAULTS.occupancyStyle
    readonly property bool followThemeColors: Plasmoid.configuration.followThemeColors ?? Logic.DEFAULTS.followThemeColors
    readonly property color activeColor: Plasmoid.configuration.activeColor ?? Logic.DEFAULTS.activeColor
    readonly property color inactiveColor: Plasmoid.configuration.inactiveColor ?? Logic.DEFAULTS.inactiveColor
    readonly property color occupiedColor: Plasmoid.configuration.occupiedColor ?? Logic.DEFAULTS.occupiedColor
    readonly property color hoverBackgroundColor: Plasmoid.configuration.hoverBackgroundColor ?? Logic.DEFAULTS.hoverBackgroundColor

    // Without a fullRepresentation Plasma builds no representation at all, so the strip is that one,
    // forced inline.
    preferredRepresentation: fullRepresentation
    fullRepresentation: WorkspaceIndicator {
        vertical: root.isVertical
        virtualDesktopInfo: vdi
        enableScroll: root.enableScroll
        scrollWrap: root.scrollWrap
        invertScroll: root.invertScroll
        showTooltips: root.showTooltips
        desktopTooltips: root.desktopTooltips

        dotStyle: root.dotStyle
        singleLine: root.singleLine
        matchDesktopGrid: root.matchDesktopGrid
        dotSizeRequest: root.dotSize
        pillSizeRequest: root.pillSize
        spacingFactor: root.spacingFactor
        pillWidthFactor: root.pillWidthFactor
        inactiveOpacity: root.inactiveOpacity
        hoverOpacity: root.hoverOpacity
        showHoverBackground: root.showHoverBackground
        hoverBackgroundOpacity: root.hoverBackgroundOpacity
        hoverLengthFactor: root.hoverLengthFactor
        hoverThicknessFactor: root.hoverThicknessFactor
        hoverBackgroundColor: root.hoverBackgroundColor
        pillClickAnywhere: Logic.pillClickAnywhereActive(root.pillClickAnywhere, root.pillClickAction)
        showOccupancy: root.showOccupancy
        desktopOccupancy: root.screenOccupancy
        occupiedOpacity: root.occupiedOpacity
        occupancyStyle: root.occupancyStyle
        followThemeColors: root.followThemeColors
        activeColor: root.activeColor
        inactiveColor: root.inactiveColor
        occupiedColor: root.occupiedColor
        animationDuration: root.animationDuration

        onSwitchRequested: uuid => root.switchTo(uuid)
        onActiveClicked: root.dispatch(Logic.pillClickSpec(root.pillClickAction))
    }

    TaskManager.VirtualDesktopInfo {
        id: vdi
    }

    // The loader also runs for occupancy alone, which mustn't bring back a window list that's off.
    readonly property var desktopTooltips: (root.showTooltips && root.showWindowList && tooltipLoader.item)
        ? (tooltipLoader.item as WindowAggregator).desktopTooltips : []

    readonly property var desktopOccupancy: tooltipLoader.item ? (tooltipLoader.item as WindowAggregator).desktopOccupancy : []
    readonly property var screenOccupancy: tooltipLoader.item ? (tooltipLoader.item as WindowAggregator).screenOccupancy : []

    // Screen.* holds only on the placed item; the zero rect before then counts windows on every screen.
    readonly property rect screenRect: root.fullRepresentationItem
        ? (root.fullRepresentationItem as WorkspaceIndicator).screenRect : Qt.rect(0, 0, 0, 0)

    Loader {
        id: tooltipLoader
        active: (root.showTooltips && root.showWindowList) || root.dynamicWorkspaces || root.showOccupancy
        sourceComponent: aggregatorComponent
    }
    Component {
        id: aggregatorComponent
        WindowAggregator {
            virtualDesktopInfo: vdi
            screenRect: root.screenRect
            windowListActive: root.showTooltips && root.showWindowList
            occupancyActive: root.showOccupancy
            dynamicActive: root.dynamicWorkspaces
        }
    }

    // A null spec is a guard that tripped, and sends nothing.
    function dispatch(spec) {
        if (!spec) {
            return;
        }
        // The new state arrives through vdi; the reply is read only so a rejected call reaches the journal.
        const reply = DBus.SessionBus.asyncCall({
            "service": spec.service,
            "path": spec.path,
            "iface": spec.iface,
            "member": spec.member,
            "arguments": spec.args.map(a => root.toDBusArg(a))
        });
        if (reply) {
            reply.finished.connect(() => {
                if (reply.isError) {
                    console.warn("plasma-gnome-pager: DBus call failed:", spec.member, "-", reply.error.name, reply.error.message);
                }
            });
        }
    }

    // The variant wraps the plain value: KWin silently rejects a variant around a DBus.string.
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
            console.warn("plasma-gnome-pager: toDBusArg got unknown DBus type letter", a.t);
            return a.v;
        }
    }

    function switchTo(uuid) {
        root.dispatch(Logic.switchSpec(uuid));
    }

    function addDesktop() {
        root.dispatch(Logic.addSpec(vdi.numberOfDesktops ?? 0, i18n("New Desktop")));
    }

    function removeDesktop(uuid) {
        root.dispatch(Logic.removeSpec(uuid, vdi.numberOfDesktops));
    }

    function removeLastDesktop() {
        root.removeDesktop(Logic.lastDesktopId(vdi.desktopIds));
    }

    DynamicWorkspacesController {
        id: dynamicController

        dynamicEnabled: root.dynamicWorkspaces
        namePrefix: root.dynamicNamePrefix
        defaultPrefix: i18nc("@info default base name for auto-created virtual desktops", "Desktop")
        virtualDesktopInfo: vdi
        desktopOccupancy: root.desktopOccupancy

        onDispatchRequested: spec => root.dispatch(spec)
        onSyncConfigRequested: (nextEnabled, nextPrefix) => {
            // Writing only a changed value keeps the write from echoing back through onChanged.
            if (Plasmoid.configuration.dynamicWorkspaces !== nextEnabled)
                Plasmoid.configuration.dynamicWorkspaces = nextEnabled;
            if (Plasmoid.configuration.dynamicNamePrefix !== nextPrefix)
                Plasmoid.configuration.dynamicNamePrefix = nextPrefix;
        }
    }

    function renameDesktop(uuid, name) {
        root.dispatch(Logic.renameSpec(uuid, name));
    }

    function openRenameDialog(uuid) {
        if (!uuid) {
            return;
        }
        const ids = vdi.desktopIds ?? [];
        const names = vdi.desktopNames ?? [];
        renameDialog.openFor(uuid, names[ids.indexOf(uuid)] ?? "");
    }

    // A window to open rather than a write to make, so it has no spec in logic.mjs.
    function openVirtualDesktopsKcm() {
        KCM.KCMLauncher.openSystemSettings(Qt.platform.pluginName.includes("wayland")
            ? "kcm_kwin_virtualdesktops"
            : "kcm_kwin_virtualdesktops_x11");
    }

    // Plasma adds "Configure Workspaces…" for this widget's own settings; the last entry here opens the system's.
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
        },
        PlasmaCore.Action {
            text: i18n("Configure Virtual Desktops…")
            icon.name: "preferences-desktop-virtual"   // the Virtual Desktops page's own icon
            priority: Plasmoid.LowPriorityAction
            onTriggered: root.openVirtualDesktopsKcm()
        }
    ]

    RenameDialog {
        id: renameDialog
        visualParent: root.fullRepresentationItem
        location: Plasmoid.location
        onAccepted: (uuid, name) => root.renameDesktop(uuid, name)
    }
}
