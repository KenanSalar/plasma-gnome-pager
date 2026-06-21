/*
 * Plasma Gnome Pager — main.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Root PlasmoidItem: owns the virtual-desktop data source (read) and the KWin
 * DBus helpers (write), and renders the dot strip inline in the panel.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts                            // Column/RowLayout (rename dialog content)

import org.kde.plasma.plasmoid

// Public, stable imports only (intentionally no org.kde.plasma.private.*):
import org.kde.plasma.core as PlasmaCore         // PlasmaCore.Action (menu) + PlasmaCore.Dialog (rename)
import org.kde.plasma.components as PlasmaComponents3  // TextField/Button/Label (rename dialog)
import org.kde.kirigami as Kirigami              // Units (rename dialog spacing)
import org.kde.taskmanager as TaskManager        // VirtualDesktopInfo + TasksModel/ActivityInfo (read)
import org.kde.plasma.workspace.dbus as DBus     // KWin DBus (switch/add/remove/rename)

import "logic.js" as Logic
import "coordinator.js" as Coordinator         // single-writer election + prefix sync across panel instances

PlasmoidItem {
    id: root

    Plasmoid.icon: "user-desktop"

    // A pager never demands attention — mark it Passive so the panel/system-tray treats it as a
    // quiet always-on widget (and a panel may auto-hide over it). The dots float directly on the
    // panel, so the applet draws no background of its own (the GNOME look).
    Plasmoid.status: PlasmaCore.Types.PassiveStatus
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Panel orientation, read here (the one place that touches Plasmoid) and passed DOWN as a plain
    // bool so the indicator/dot stay free of Plasmoid/PlasmaCore and remain headless-testable.
    // Planar (desktop) and Floating both report non-Vertical, so they fall through to the horizontal
    // row — the sensible default off-panel.
    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // Behaviour settings, read live from the config schema (contents/config/main.xml).
    // Defaults there apply even before the settings UI exists (M5 owns the dialog), so the
    // widget is config-driven now. These flow down to the indicator/tooltip/actions as
    // plain booleans, keeping those sub-components free of plasmoid.configuration (and so
    // headless-testable).
    //
    // The `?? <default>` mirrors each schema default: a freshly-added schema can read back
    // `undefined` for a frame (or until the widget is re-added) and a bare bool would then
    // collapse to false, silently disabling every interaction. The guard keeps the intended
    // defaults regardless, while still honouring a real saved value (false ?? true === false).
    readonly property bool enableScroll: Plasmoid.configuration.enableScroll ?? Logic.DEFAULTS.enableScroll
    readonly property bool scrollWrap: Plasmoid.configuration.scrollWrap ?? Logic.DEFAULTS.scrollWrap
    readonly property bool invertScroll: Plasmoid.configuration.invertScroll ?? Logic.DEFAULTS.invertScroll
    readonly property bool showTooltips: Plasmoid.configuration.showTooltips ?? Logic.DEFAULTS.showTooltips
    readonly property bool showWindowList: Plasmoid.configuration.showWindowList ?? Logic.DEFAULTS.showWindowList
    readonly property bool enableAddRemove: Plasmoid.configuration.enableAddRemove ?? Logic.DEFAULTS.enableAddRemove
    readonly property bool enableRename: Plasmoid.configuration.enableRename ?? Logic.DEFAULTS.enableRename
    // Dynamic workspaces (GNOME-style, default OFF): auto-keep exactly one empty trailing desktop. Drives
    // the controller below. dynamicNamePrefix is the base name for the desktops it creates ("" = the i18n
    // default "Desktop"); the controller appends the new desktop's number ("<prefix> N").
    readonly property bool dynamicWorkspaces: Plasmoid.configuration.dynamicWorkspaces ?? Logic.DEFAULTS.dynamicWorkspaces
    readonly property string dynamicNamePrefix: Plasmoid.configuration.dynamicNamePrefix ?? Logic.DEFAULTS.dynamicNamePrefix

    // Manual Add/Remove is available only when enabled AND dynamic workspaces is off — the two
    // conflict (the controller would instantly trim a manually-added empty / re-add a removed
    // trailing one). Derived once here and reused by the contextualActions' visible:/enabled: below.
    readonly property bool canAddRemove: enableAddRemove && !dynamicWorkspaces

    // Appearance + animation settings, read the same way and passed down to the indicator as plain
    // values (it forwards them per-dot). dotSize/animationDuration use a `0 = auto` sentinel: the
    // indicator/dot turn 0 into the HiDPI/themed default — resolved there because the components are
    // the headless-tested rendering layer (main.qml imports Kirigami only for the rename dialog's
    // spacing, not for these; see WorkspaceIndicator/WorkspaceDot). Each `?? <default>`
    // mirrors the schema default for the transient-undefined frame, exactly like the booleans above.
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

    // A pager renders inline in the panel. Plasma will not instantiate ANY
    // representation unless a fullRepresentation is defined (a compact-only applet
    // renders nothing at all), so the dot strip IS the full representation and we
    // force it to always show inline — never a popup or the default compact icon —
    // via preferredRepresentation. (verified against develop.kde.org/docs/plasma/widget)
    //
    // The indicator is the representation directly; it advertises its size via Layout.*
    // hints so the panel allocates the right width (tooltips live per-dot inside it).
    preferredRepresentation: fullRepresentation
    fullRepresentation: WorkspaceIndicator {
        vertical: root.isVertical
        virtualDesktopInfo: vdi
        enableScroll: root.enableScroll
        scrollWrap: root.scrollWrap
        invertScroll: root.invertScroll
        showTooltips: root.showTooltips
        desktopTooltips: root.desktopTooltips

        // Appearance/animation config (dotSize/pillSize passed as the raw 0=auto requests; resolved
        // in the indicator — pillSize 0 there means "match the dot size").
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

    // Reactive, read-only desktop state. Bind to it; never cache — it updates when
    // desktops change by ANY means (keyboard, another pager, settings). Writing
    // (switch/add/remove) goes through KWin DBus below. (see virtual-desktops.md)
    TaskManager.VirtualDesktopInfo {
        id: vdi
    }

    // Per-desktop tooltip subText (a rich-text <ul> of the windows open on each desktop), index-aligned
    // with vdi.desktopIds and passed DOWN to the indicator/dots as plain strings (so those sub-components
    // stay free of Plasma data types and headless-testable). Built here — the e2e boundary that may touch
    // live Plasma models + i18n. Explicitly gated by showTooltips && showWindowList: the aggregator Loader
    // can now also be active purely for dynamic workspaces (occupancy below), so the Loader being live no
    // longer implies the user wants the window list — without this gate, turning on dynamic workspaces would
    // resurface the window list the user disabled. Empty [] → each dot falls back to a name-only tooltip.
    // Mirrors the stock KDE pager's tooltip text, but sourced from the PUBLIC TaskManager.TasksModel instead
    // of the private PagerModel (robustness.md). The `as` cast gives qmllint a typed read of Loader.item.
    readonly property var desktopTooltips: (root.showTooltips && root.showWindowList && tooltipLoader.item)
        ? (tooltipLoader.item as WindowAggregator).desktopTooltips : []

    // Per-desktop occupancy boolean[] (does each desktop hold a window?), index-aligned with vdi.desktopIds.
    // Produced from the SAME window snapshot as desktopTooltips (one shared TasksModel) and consumed by the
    // dynamic-workspaces controller below. Empty [] when the aggregator Loader is inactive (feature + window
    // list both off) — the controller then no-ops via the length guard in Logic.dynamicWorkspacePlan.
    readonly property var desktopOccupancy: tooltipLoader.item ? (tooltipLoader.item as WindowAggregator).desktopOccupancy : []

    // The whole window-list machinery (a TasksModel + ActivityInfo + the row Instantiator) lives behind a
    // Loader, so when nothing needs it the always-on model cost simply does not exist (qml-performance.md:
    // this widget is always on screen). It's needed for the tooltip window list (showTooltips && showWindowList)
    // AND for dynamic workspaces (which reads per-desktop occupancy) — so the gate is the OR of the two.
    Loader {
        id: tooltipLoader
        active: (root.showTooltips && root.showWindowList) || root.dynamicWorkspaces
        sourceComponent: aggregatorComponent
    }
    Component {
        id: aggregatorComponent
        WindowAggregator {
            virtualDesktopInfo: vdi   // inject the read source (the aggregator is otherwise data-source-agnostic)
        }
    }

    // Every virtual-desktop write goes through KWin's VirtualDesktopManager. The CALL SHAPES
    // (service/path/iface/member + per-arg DBus types) live in pure logic.js as *Spec builders, so
    // the exact strings/types — the parts that fail SILENTLY on a Plasma upgrade (CLAUDE.md DBus
    // gotcha) — are unit-tested by tst_logic.qml. Here we only DISPATCH a built spec: async
    // fire-and-forget (issue the call, let `vdi` report the resulting state). A null spec (a guard
    // tripped in logic.js: transient-empty uuid, never-remove-last, blank rename) is a no-op.
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

    // Map ONE spec arg { t, v } to the order-sensitive DBus.* constructor it describes (t mirrors a
    // DBus signature letter: "s" string, "u" uint32, "i" int32, "v" variant). This is the only seam
    // tests can't reach (it needs the real DBus plugin); it stays a trivial 1:1 switch. The "v" case
    // wraps a PLAIN value — never a wrapped DBus.string, which KWin silently rejects (CLAUDE.md).
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
        }
        return a.v;
    }

    // Switch to a desktop by UUID via the VirtualDesktopManager "current" property.
    function switchTo(uuid) {
        root.dispatch(Logic.switchSpec(uuid));
    }

    // Append a new desktop at the end. `?? 0` keeps a transient-undefined count (shell reload / widget
    // re-add) out of the uint32 position; when the menu action actually fires the widget is live, so it
    // is a real append. The i18n label stays here (logic.js is i18n-free). `vdi` reports the new count.
    function addDesktop() {
        root.dispatch(Logic.addSpec(vdi.numberOfDesktops ?? 0, i18n("New Desktop")));
    }

    // Remove a desktop by UUID. logic.js's removeSpec enforces never-remove-last (returns null).
    function removeDesktop(uuid) {
        root.dispatch(Logic.removeSpec(uuid, vdi.numberOfDesktops));
    }

    // "Remove" targets the last desktop (the one addDesktop appended).
    function removeLastDesktop() {
        root.removeDesktop(Logic.lastDesktopId(vdi.desktopIds));
    }

    // ── Dynamic workspaces (GNOME-style) ──────────────────────────────────────────────────────────
    // When enabled, keep exactly one empty trailing desktop by issuing ONE KWin add/remove per cycle and
    // letting `vdi` report the result (the read/write split). The decision is the pure
    // Logic.dynamicWorkspacePlan; here we debounce, re-check the freshest state, and hold a short
    // busy-lock against THIS instance re-firing before its own change reflects.
    //
    // The desktop SET is global, so this is a single GLOBAL behaviour. The shared coordinator
    // (coordinator.js) gives two things across all panel/monitor instances:
    //   1. Setting SYNC — the enabled flag and name prefix are ONE global value: toggling on any panel
    //      mirrors into every other panel's own config (so all checkboxes agree and persist), removing
    //      the per-panel confusion. applyDynamicSync writes our config; publishDynamicConfig broadcasts ours.
    //   2. Single-WRITER election — only the lowest-token instance issues the KWin add/remove, so two
    //      panels never double-add then trim (the multi-monitor "flash"). dynToken is our handle.
    property bool dynBusy: false
    property int dynToken: 0
    Timer {
        id: dynBusyTimer
        interval: 750
        onTriggered: root.dynBusy = false
    }

    // Join the coordinator (registering applyDynamicSync as how it pushes the global value to us). If a
    // sibling already established the global, adopt it; otherwise we are first and seed it from our stored
    // config. Then evaluate once (the last desktop may already be occupied at startup). Leave on teardown
    // so a removed panel stops counting in the election.
    Component.onCompleted: {
        root.dynToken = Coordinator.join(root.applyDynamicSync);
        if (Coordinator.haveGlobal())
            root.applyDynamicSync(Coordinator.globalEnabled(), Coordinator.globalPrefix());
        else
            Coordinator.publish(root.dynamicWorkspaces, root.dynamicNamePrefix);
        root.scheduleDynamic();
    }
    Component.onDestruction: Coordinator.leave(root.dynToken)

    // Mirror the one global setting into THIS instance's persisted config (so the checkbox/prefix field
    // agree across panels and survive a reload). Value-guarded, so it never loops: after this our values
    // equal the global, and publishDynamicConfig below only republishes a genuine local change.
    function applyDynamicSync(enabled, prefix) {
        if (Plasmoid.configuration.dynamicWorkspaces !== enabled)
            Plasmoid.configuration.dynamicWorkspaces = enabled;
        if (Plasmoid.configuration.dynamicNamePrefix !== prefix)
            Plasmoid.configuration.dynamicNamePrefix = prefix;
    }

    // Our config changed. If it differs from the established global, WE changed it (the user toggled this
    // panel) → publish to every panel. If it already matches the global, this was an applyDynamicSync echo
    // → just re-evaluate. Guarded against the pre-join window (config bindings fire before onCompleted).
    function publishDynamicConfig() {
        if (root.dynToken === 0)
            return;
        if (!Coordinator.haveGlobal()
                || root.dynamicWorkspaces !== Coordinator.globalEnabled()
                || root.dynamicNamePrefix !== Coordinator.globalPrefix())
            Coordinator.publish(root.dynamicWorkspaces, root.dynamicNamePrefix);
        root.scheduleDynamic();
    }

    // Coalesce a burst of occupancy / desktop-set changes into ONE evaluation next tick (the aggregator's
    // scheduleRebuild idiom). A cheap no-op when the feature is off.
    function scheduleDynamic() {
        if (!root.dynamicWorkspaces)
            return;
        Qt.callLater(root.evaluateDynamic);
    }

    // Compute and dispatch the single dynamic-workspace action for the FRESHEST state, or do nothing. Only
    // the elected writer acts (Coordinator.isWriter) — so multiple panels never double-add. The length
    // guard inside dynamicWorkspacePlan makes a transient frame — where desktopOccupancy still lags a
    // just-changed desktop set — a no-op until occupancy catches up.
    function evaluateDynamic() {
        if (!root.dynamicWorkspaces || root.dynBusy)
            return;
        if (!Coordinator.isWriter(root.dynToken))
            return;                              // another panel instance is the single global writer
        const ids = vdi.desktopIds ?? [];
        const plan = Logic.dynamicWorkspacePlan(root.desktopOccupancy, ids);
        if (!plan)
            return;
        let spec = null;
        if (plan.kind === "add") {
            // Name auto-created desktops "<prefix> N" (prefix synced across panels, default the i18n
            // "Desktop"). position == current count (append at end), so the new desktop's number is pos + 1.
            // formatDynamicDesktopName guarantees a non-empty name: KWin silently drops createDesktop with an
            // empty name. The i18n default base is passed IN (logic.js stays i18n-free).
            const pos = vdi.numberOfDesktops ?? ids.length;
            spec = Logic.addSpec(pos, Logic.formatDynamicDesktopName(root.dynamicNamePrefix, pos + 1,
                i18nc("@info default base name for auto-created virtual desktops", "Desktop")));
        } else if (plan.kind === "remove") {
            spec = Logic.removeSpec(plan.uuid, vdi.numberOfDesktops ?? ids.length);
        }
        if (!spec)
            return;
        root.dynBusy = true;
        root.dispatch(spec);
        dynBusyTimer.restart();
    }

    // Triggers: occupancy flips (a window opened/closed/moved) and the desktop SET changing (also the
    // signal that OUR own add/remove landed → clear the busy-lock and re-evaluate). Config changes go
    // through publishDynamicConfig so the global stays in sync before we act.
    onDesktopOccupancyChanged: root.scheduleDynamic()
    onDynamicWorkspacesChanged: root.publishDynamicConfig()
    onDynamicNamePrefixChanged: root.publishDynamicConfig()
    Connections {
        target: vdi
        function onDesktopIdsChanged() {
            root.dynBusy = false;
            root.scheduleDynamic();
        }
    }

    // Rename a desktop by UUID via KWin's setDesktopName(id, name). renameSpec trims/sanitizes and
    // rejects an empty/whitespace-only name (returns null → no-op); `vdi` reports the new name back
    // via the desktopNames binding — no cache (the read/write split).
    function renameDesktop(uuid, name) {
        root.dispatch(Logic.renameSpec(uuid, name));
    }

    // Open the rename prompt for a desktop, prefilled with its current name. Resolves the name from the
    // live vdi arrays (index-aligned; guarded for the transient-empty frame).
    function openRenameDialog(uuid) {
        if (!uuid) {
            return;
        }
        const ids = vdi.desktopIds ?? [];
        const names = vdi.desktopNames ?? [];
        renameDialog.openFor(uuid, names[ids.indexOf(uuid)] ?? "");
    }

    // Right-click menu. Add/Remove are gated by enableAddRemove AND hidden while dynamicWorkspaces is on
    // (the two conflict: the controller would immediately trim a manually-added empty / re-add a removed
    // trailing empty — so manual editing must yield to the auto-manager). dynamicWorkspaces is globally
    // synced, so this hides the entries on every panel; enableAddRemove's own value is left untouched and
    // returns when dynamic is turned off. Remove also disables at the last desktop. Rename never conflicts.
    // (The "Configure…" entry is added automatically by Plasma once a config schema exists.)
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

    // Rename prompt — a panel-native PlasmaCore.Dialog (a top-level Window), declared directly (not in a
    // Loader: a Loader is for Items, and there is no precedent for loading a Window through one; visible:
    // false keeps it cheap — no native surface until first shown, and its content is just a field + two
    // buttons). Chosen over Kirigami.PromptDialog, whose base parents to applicationWindow().overlay —
    // undefined in a plasmoid, so it would be clipped to the thin panel (robustness.md). It pops next to
    // the widget via visualParent + location (the AppletAlternatives idiom) and lives here in main.qml
    // (the e2e boundary) so the headless-tested sub-components never touch a dialog or Plasma window type.
    PlasmaCore.Dialog {
        id: renameDialog

        property string targetUuid: ""

        visible: false
        visualParent: root.fullRepresentationItem
        location: Plasmoid.location
        hideOnWindowDeactivate: true            // click-away cancels

        // Show prefilled with the desktop's current name, text selected and focused for immediate typing.
        function openFor(uuid, currentName) {
            renameDialog.targetUuid = uuid;
            renameField.text = currentName;
            renameDialog.visible = true;
            renameField.selectAll();
            renameField.forceActiveFocus();
        }

        // Commit the rename, then close. An empty/whitespace name (sanitize → "") keeps the prompt open
        // rather than silently doing nothing; renameDesktop re-sanitizes, so the write stays guarded.
        function commit() {
            const clean = Logic.sanitizeDesktopName(renameField.text);
            if (clean === "") {
                return;
            }
            root.renameDesktop(renameDialog.targetUuid, clean);
            renameDialog.visible = false;
        }

        mainItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: i18n("Rename desktop:")
            }
            PlasmaComponents3.TextField {
                id: renameField
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 12
                onAccepted: renameDialog.commit()                  // Enter commits
                Keys.onEscapePressed: renameDialog.visible = false // Esc cancels
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Button {
                    text: i18n("Cancel")
                    icon.name: "dialog-cancel"
                    onClicked: renameDialog.visible = false
                }
                PlasmaComponents3.Button {
                    text: i18n("Rename")
                    icon.name: "edit-rename"
                    enabled: renameField.text.trim().length > 0
                    onClicked: renameDialog.commit()
                }
            }
        }
    }
}
