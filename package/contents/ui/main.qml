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
import QtQml                                      // Instantiator (materialise TasksModel rows)
import QtQuick.Layouts                            // Column/RowLayout (rename dialog content)

import org.kde.plasma.plasmoid

// Public, stable imports only (intentionally no org.kde.plasma.private.*):
import org.kde.plasma.core as PlasmaCore         // PlasmaCore.Action (menu) + PlasmaCore.Dialog (rename)
import org.kde.plasma.components as PlasmaComponents3  // TextField/Button/Label (rename dialog)
import org.kde.kirigami as Kirigami              // Units (rename dialog spacing)
import org.kde.taskmanager as TaskManager        // VirtualDesktopInfo + TasksModel/ActivityInfo (read)
import org.kde.plasma.workspace.dbus as DBus     // KWin DBus (switch/add/remove/rename)

import "logic.js" as Logic

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
    readonly property bool showTooltips: Plasmoid.configuration.showTooltips ?? Logic.DEFAULTS.showTooltips
    readonly property bool showWindowList: Plasmoid.configuration.showWindowList ?? Logic.DEFAULTS.showWindowList
    readonly property bool enableAddRemove: Plasmoid.configuration.enableAddRemove ?? Logic.DEFAULTS.enableAddRemove
    readonly property bool enableRename: Plasmoid.configuration.enableRename ?? Logic.DEFAULTS.enableRename

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
    // live Plasma models + i18n. Empty [] when the window list is off (the Loader is then inactive), so
    // each dot falls back to a name-only tooltip. Mirrors the stock KDE pager's tooltip text, but sourced
    // from the PUBLIC TaskManager.TasksModel instead of the private PagerModel (robustness.md). The `as`
    // cast gives qmllint a typed read of the loaded item's property (no missing-property on Loader.item).
    readonly property var desktopTooltips: tooltipLoader.item ? (tooltipLoader.item as TooltipAggregator).desktopTooltips : []

    // The whole window-list machinery (a TasksModel + ActivityInfo + the row Instantiator) lives behind a
    // Loader gated by showTooltips && showWindowList, so when the window list is off it — and its always-on
    // model cost — simply does not exist (qml-performance.md: this widget is always on screen).
    Loader {
        id: tooltipLoader
        active: root.showTooltips && root.showWindowList
        sourceComponent: aggregatorComponent
    }
    Component {
        id: aggregatorComponent
        TooltipAggregator {}
    }

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
    }

    // The window-list aggregator — a NAMED inline component (so tooltipLoader.item can be `as`-cast to it
    // above). Non-visual zero-size Item: Loader.item must be a QQuickItem, not a bare QtObject. ONE
    // unfiltered public TasksModel + grouping in pure JS (Logic.groupWindowsByDesktop), not N filtered
    // models, so the grouping/truncation stays headless-unit-tested. GroupDisabled → one row per window
    // (an accurate per-desktop count); filterByActivity keeps other activities' windows out of the lists.
    component TooltipAggregator: Item {
        id: aggregator

        property var desktopTooltips: []

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

        // Rebuild on any role-value change (dataChanged covers title/minimise/desktop) or a full reset,
        // and when the desktop SET changes (the index alignment shifts). All funnel through the debounced
        // scheduleRebuild so a burst collapses to one rebuild per frame.
        Connections {
            target: tasksModel
            function onDataChanged() {
                aggregator.scheduleRebuild();
            }
            function onModelReset() {
                aggregator.scheduleRebuild();
            }
        }
        Connections {
            target: vdi
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
                    desktops: (o.windowDesktops || []).map(x => String(x))
                });
            }
            aggregator.desktopTooltips = Logic.groupWindowsByDesktop(windows, vdi.desktopIds ?? []).map(aggregator.formatSubText);
        }

        // Build one desktop's window list as a rich-text <ul> capped at Logic.windowListMaximum, with an
        // "…and N other windows" overflow line — the stock pager's generateWindowList.
        function formatList(titles) {
            const total = titles.length;
            const max = Logic.windowListMaximum(total);
            let t = "<ul><li>" + titles.slice(0, max).map(x => Logic.sanitizeHtml(x.length ? x : i18nc("@item:intext window with no title", "Untitled Window"))).join("</li><li>") + "</li></ul>";
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
                t += Logic.sanitizeHtml(s.visible[0].length ? s.visible[0] : i18nc("@item:intext window with no title", "Untitled Window"));
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

    // Right-click menu. Gated by enableAddRemove; Remove also disables at the last desktop.
    // (The "Configure…" entry is added automatically by Plasma once a config schema exists.)
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Add Desktop")
            icon.name: "list-add"
            priority: Plasmoid.LowPriorityAction
            visible: root.enableAddRemove
            enabled: root.enableAddRemove
            onTriggered: root.addDesktop()
        },
        PlasmaCore.Action {
            text: i18n("Remove Last Desktop")
            icon.name: "list-remove"
            priority: Plasmoid.LowPriorityAction
            visible: root.enableAddRemove
            enabled: root.enableAddRemove && Logic.canRemoveDesktop(vdi.numberOfDesktops)
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
