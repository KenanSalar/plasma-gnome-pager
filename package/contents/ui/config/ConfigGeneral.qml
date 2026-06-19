/*
 * Plasma Gnome Pager — ConfigGeneral.qml (Behavior settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Behavior page of the settings dialog. Built on ConfigPageBase (a Kirigami.ScrollablePage that
 * supplies the KDE title header + the shared "Defaults" header action); this page just declares its
 * keys and its content.
 *
 * Each `cfg_<key>` alias name MUST match a contents/config/main.xml entry exactly; the dialog then
 * wires load/save automatically. `cfg_<key>Default` is injected by the dialog from the schema default
 * (declared below, no initializer, so main.xml stays the single source of truth). This page fulfils
 * ConfigPageBase's contract: it binds `isModified` and handles `onDefaultsRequested`. Public Kirigami
 * + QtQuick.Controls only (not PlasmaComponents) — see plasmoid.md / kirigami.md.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

ConfigPageBase {
    id: root

    property alias cfg_enableScroll: enableScroll.checked
    property alias cfg_scrollWrap: scrollWrap.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_showWindowList: showWindowList.checked
    property alias cfg_enableAddRemove: enableAddRemove.checked
    property alias cfg_enableRename: enableRename.checked
    property alias cfg_animationDuration: animationDuration.value

    // Injected by the config dialog from the main.xml defaults; read by the Defaults handler below.
    property bool cfg_enableScrollDefault
    property bool cfg_scrollWrapDefault
    property bool cfg_showTooltipsDefault
    property bool cfg_showWindowListDefault
    property bool cfg_enableAddRemoveDefault
    property bool cfg_enableRenameDefault
    property int cfg_animationDurationDefault

    // True when any key on this page differs from its default (gates the base's Defaults action).
    isModified: cfg_enableScroll !== cfg_enableScrollDefault
        || cfg_scrollWrap !== cfg_scrollWrapDefault
        || cfg_showTooltips !== cfg_showTooltipsDefault
        || cfg_showWindowList !== cfg_showWindowListDefault
        || cfg_enableAddRemove !== cfg_enableAddRemoveDefault
        || cfg_enableRename !== cfg_enableRenameDefault
        || cfg_animationDuration !== cfg_animationDurationDefault

    onDefaultsRequested: {
        cfg_enableScroll = cfg_enableScrollDefault;
        cfg_scrollWrap = cfg_scrollWrapDefault;
        cfg_showTooltips = cfg_showTooltipsDefault;
        cfg_showWindowList = cfg_showWindowListDefault;
        cfg_enableAddRemove = cfg_enableAddRemoveDefault;
        cfg_enableRename = cfg_enableRenameDefault;
        cfg_animationDuration = cfg_animationDurationDefault;
    }

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
        }
        QQC2.CheckBox {
            id: enableRename
            text: i18n("Rename the current desktop from the right-click menu")
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
