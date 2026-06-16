/*
 * GNOME Workspace Switcher — ConfigGeneral.qml (Behavior page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * SCAFFOLD ONLY. The config system two-way-binds controls via property aliases
 * named cfg_<key> matching the entries in contents/config/main.xml.
 *
 * TODO(impl): add controls + aliases, e.g.
 *   property alias cfg_enableScroll: enableScrollCheck.checked
 *   QQC2.CheckBox { id: enableScrollCheck; text: i18n("Scroll to switch desktops") }
 *   ...and the same for scrollWrap, enableAddRemove, showTooltips, animationDuration.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    QQC2.Label {
        Kirigami.FormData.label: i18n("Behavior")
        text: i18n("Not implemented yet (scaffold).")
        opacity: 0.6
    }
}
