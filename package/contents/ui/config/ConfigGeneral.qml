/*
 * Plasma Gnome Pager — ConfigGeneral.qml (Behavior settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Behavior page, built on ConfigPageBase. Each `cfg_<key>` alias MUST match a main.xml entry exactly
 * (the dialog wires load/save); `cfg_<key>Default` is injected from the schema.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ConfigPageBase {
    id: root

    property alias cfg_enableScroll: enableScroll.checked
    property alias cfg_scrollWrap: scrollWrap.checked
    property alias cfg_invertScroll: invertScroll.checked
    property alias cfg_pillClickAction: pillClickAction.currentIndex
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_showWindowList: showWindowList.checked
    property alias cfg_enableAddRemove: enableAddRemove.checked
    property alias cfg_enableRename: enableRename.checked
    property alias cfg_dynamicWorkspaces: dynamicWorkspaces.checked
    property alias cfg_dynamicNamePrefix: dynamicNamePrefix.text
    property alias cfg_animationDuration: animationDuration.value

    // Injected by the config dialog from the main.xml defaults; read by the Defaults handler below.
    property bool cfg_enableScrollDefault
    property bool cfg_scrollWrapDefault
    property bool cfg_invertScrollDefault
    property int cfg_pillClickActionDefault
    property bool cfg_showTooltipsDefault
    property bool cfg_showWindowListDefault
    property bool cfg_enableAddRemoveDefault
    property bool cfg_enableRenameDefault
    property bool cfg_dynamicWorkspacesDefault
    property string cfg_dynamicNamePrefixDefault
    property int cfg_animationDurationDefault

    // This page's keys + compare kind; ConfigPageBase binds isModified AND the Defaults reset off it.
    configKeys: [
        { n: "enableScroll", t: "bool" },
        { n: "scrollWrap", t: "bool" },
        { n: "invertScroll", t: "bool" },
        { n: "pillClickAction", t: "int" },
        { n: "showTooltips", t: "bool" },
        { n: "showWindowList", t: "bool" },
        { n: "enableAddRemove", t: "bool" },
        { n: "enableRename", t: "bool" },
        { n: "dynamicWorkspaces", t: "bool" },
        { n: "dynamicNamePrefix", t: "string" },
        { n: "animationDuration", t: "int" }
    ]

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enableScroll
            Kirigami.FormData.label: i18n("Mouse:")
            text: i18n("Scroll over the pager to switch desktops")
        }
        QQC2.CheckBox {
            id: scrollWrap
            text: i18n("Wrap around at the first and last desktop")
            enabled: enableScroll.checked   // wrap only matters when scrolling is on
        }
        QQC2.CheckBox {
            id: invertScroll
            text: i18n("Invert the scroll direction")
            enabled: enableScroll.checked   // inversion only matters when scrolling is on
        }
        QQC2.ComboBox {
            id: pillClickAction
            Kirigami.FormData.label: i18n("Click current desktop:")
            // Order MUST match Logic.PILL_CLICK_ACTION / main.xml pillClickAction (currentIndex is stored as the index).
            model: [i18n("Nothing"), i18n("Show Desktop"), i18n("Overview"), i18n("Grid")]
            Layout.preferredWidth: root.fieldWidth   // match the other field widths (ConfigPageBase.fieldWidth)
        }
        QQC2.Label {
            // Clarify the action only fires on the highlighted (current) desktop; other dots just switch.
            text: i18n("Action when clicking the highlighted current desktop. Clicking any other desktop switches to it.")
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.fillWidth: true
            Layout.preferredWidth: root.fieldWidth   // wrap within the field column
        }
        QQC2.CheckBox {
            id: showTooltips
            Kirigami.FormData.label: i18n("Tooltips:")
            text: i18n("Show the desktop name on hover")
        }
        QQC2.CheckBox {
            id: showWindowList
            text: i18n("List the open windows in the tooltip")
            enabled: showTooltips.checked   // the window list only shows when tooltips are on
        }
        QQC2.CheckBox {
            id: enableAddRemove
            Kirigami.FormData.label: i18n("Menu:")
            text: i18n("Add and remove desktops from the right-click menu")
            // Greyed while dynamic workspaces is on (mutually exclusive); value preserved, returns when off.
            enabled: !dynamicWorkspaces.checked
        }
        QQC2.CheckBox {
            id: enableRename
            text: i18n("Rename the current desktop from the right-click menu")
        }
        QQC2.CheckBox {
            id: dynamicWorkspaces
            Kirigami.FormData.label: i18n("Dynamic desktops:")
            text: i18n("Automatically add and remove desktops (GNOME-style)")
        }
        QQC2.Label {
            // Hint explaining the exclusivity above, so a new user sees why Add/Remove greys out.
            text: i18n("While on, desktops are managed automatically — the menu Add/Remove options are disabled.")
            visible: dynamicWorkspaces.checked
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            Layout.fillWidth: true
            Layout.preferredWidth: root.fieldWidth   // wrap within the field column
        }
        QQC2.TextField {
            id: dynamicNamePrefix
            Kirigami.FormData.label: i18n("New desktop name:")
            // Base name for auto-created desktops (number appended); empty → the placeholder default.
            enabled: dynamicWorkspaces.checked
            placeholderText: i18nc("@info default base name for auto-created virtual desktops", "Desktop")
            Layout.preferredWidth: root.fieldWidth   // match the slider track width (ConfigPageBase.fieldWidth)
        }

        ConfigSlider {
            id: animationDuration
            label: i18n("Animation duration:")
            from: 0
            to: 2000
            stepSize: 25   // clean 25 ms increments (SnapAlways is the ConfigSlider default)
            // 0 = follow the theme's default (and the global "reduce animations" setting).
            format: v => v === 0 ? i18n("Default") : i18np("%1 ms", "%1 ms", Math.round(v))
        }
    }
}
