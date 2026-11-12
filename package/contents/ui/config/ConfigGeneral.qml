/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Behavior settings page.
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
    property alias cfg_pillClickAnywhere: pillClickAnywhere.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_showWindowList: showWindowList.checked
    property alias cfg_enableAddRemove: enableAddRemove.checked
    property alias cfg_enableRename: enableRename.checked
    property alias cfg_dynamicWorkspaces: dynamicWorkspaces.checked
    property alias cfg_dynamicNamePrefix: dynamicNamePrefix.text
    property alias cfg_animationDuration: animationDuration.value

    // The dialog sets these from main.xml.
    property bool cfg_enableScrollDefault
    property bool cfg_scrollWrapDefault
    property bool cfg_invertScrollDefault
    property int cfg_pillClickActionDefault
    property bool cfg_pillClickAnywhereDefault
    property bool cfg_showTooltipsDefault
    property bool cfg_showWindowListDefault
    property bool cfg_enableAddRemoveDefault
    property bool cfg_enableRenameDefault
    property bool cfg_dynamicWorkspacesDefault
    property string cfg_dynamicNamePrefixDefault
    property int cfg_animationDurationDefault

    configKeys: [
        { n: "enableScroll", t: "bool" },
        { n: "scrollWrap", t: "bool" },
        { n: "invertScroll", t: "bool" },
        { n: "pillClickAction", t: "int" },
        { n: "pillClickAnywhere", t: "bool" },
        { n: "showTooltips", t: "bool" },
        { n: "showWindowList", t: "bool" },
        { n: "enableAddRemove", t: "bool" },
        { n: "enableRename", t: "bool" },
        { n: "dynamicWorkspaces", t: "bool" },
        { n: "dynamicNamePrefix", t: "string" },
        { n: "animationDuration", t: "int" }
    ]

    Kirigami.FormLayout {
        ConfigSection {
            title: i18n("Mouse")
        }
        QQC2.CheckBox {
            id: enableScroll
            text: i18n("Scroll over the pager to switch desktops")
        }
        QQC2.CheckBox {
            id: scrollWrap
            text: i18n("Wrap around at the first and last desktop")
            enabled: enableScroll.checked
        }
        QQC2.CheckBox {
            id: invertScroll
            text: i18n("Invert the scroll direction")
            enabled: enableScroll.checked
        }
        QQC2.ComboBox {
            id: pillClickAction
            Kirigami.FormData.label: i18n("Click current desktop:")
            // The index is the stored value, in Logic.PILL_CLICK_ACTION's order.
            model: [i18n("Nothing"), i18n("Show Desktop"), i18n("Overview"), i18n("Grid")]
            Layout.preferredWidth: root.fieldWidth
        }
        ConfigHint {
            text: i18n("Action when clicking the highlighted current desktop. Clicking any other desktop switches to it.")
        }
        QQC2.CheckBox {
            id: pillClickAnywhere
            text: i18n("Trigger it from anywhere on the widget")
            enabled: pillClickAction.currentIndex !== 0   // Nothing
        }
        ConfigHint {
            text: i18n("Click the space around the dots, not just the highlighted desktop.")
        }

        ConfigSection {
            title: i18n("Tooltips")
        }
        QQC2.CheckBox {
            id: showTooltips
            text: i18n("Show the desktop name on hover")
        }
        QQC2.CheckBox {
            id: showWindowList
            text: i18n("List the open windows in the tooltip")
            enabled: showTooltips.checked
        }

        ConfigSection {
            // One heading for the two that exclude each other: side by side, the greyed Add/Remove reads
            // as deliberate.
            title: i18n("Desktop management")
        }
        QQC2.CheckBox {
            id: enableAddRemove
            text: i18n("Add and remove desktops from the right-click menu")
            enabled: !dynamicWorkspaces.checked
        }
        QQC2.CheckBox {
            id: enableRename
            text: i18n("Rename the current desktop from the right-click menu")
        }
        QQC2.CheckBox {
            id: dynamicWorkspaces
            text: i18n("Automatically add and remove desktops (GNOME-style)")
        }
        ConfigHint {
            text: i18n("While on, desktops are managed automatically — the menu Add/Remove options are disabled.")
            visible: dynamicWorkspaces.checked
        }
        QQC2.TextField {
            id: dynamicNamePrefix
            Kirigami.FormData.label: i18n("New desktop name:")
            enabled: dynamicWorkspaces.checked
            placeholderText: i18nc("@info default base name for auto-created virtual desktops", "Desktop")
            Layout.preferredWidth: root.fieldWidth
        }

        ConfigSection {
            title: i18n("Animation")
        }
        ConfigSlider {
            id: animationDuration
            label: i18n("Animation duration:")
            from: 0
            to: 2000
            stepSize: 25
            format: v => v === 0 ? i18n("Default") : i18np("%1 ms", "%1 ms", Math.round(v))
        }
    }
}
