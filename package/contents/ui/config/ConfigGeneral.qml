/*
 * GNOME Workspace Switcher — ConfigGeneral.qml (Behavior settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Behavior page of the settings dialog. Each `cfg_<key>` alias name MUST match a
 * contents/config/main.xml entry exactly; the dialog then wires load/save/defaults (and a
 * cfg_<key>Default alias) automatically. Public Kirigami.FormLayout + QtQuick.Controls only
 * (not PlasmaComponents) — see plasmoid.md / kirigami.md.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    property alias cfg_enableScroll: enableScroll.checked
    property alias cfg_scrollWrap: scrollWrap.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_enableAddRemove: enableAddRemove.checked
    property alias cfg_animationDuration: animationDuration.value

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
        id: enableAddRemove
        Kirigami.FormData.label: i18n("Menu:")
        text: i18n("Add and remove desktops from the right-click menu")
    }

    QQC2.SpinBox {
        id: animationDuration
        Kirigami.FormData.label: i18n("Animation duration:")
        from: 0
        to: 2000
        stepSize: 50
        // 0 = follow the theme's default (and the global "reduce animations" setting).
        textFromValue: (value) => value === 0 ? i18n("Default") : i18np("%1 ms", "%1 ms", value)
        valueFromText: (text) => text === i18n("Default") ? 0 : parseInt(text)
    }
}
