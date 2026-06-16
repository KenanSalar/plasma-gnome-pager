/*
 * GNOME Workspace Switcher — ConfigAppearance.qml (Appearance page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * SCAFFOLD ONLY. The config system two-way-binds controls via property aliases
 * named cfg_<key> matching the entries in contents/config/main.xml.
 *
 * TODO(impl): add controls + aliases, e.g.
 *   property alias cfg_dotSize: dotSizeSpin.value
 *   QQC2.SpinBox { id: dotSizeSpin; from: 2; to: 64 }
 *   ...and the same for dotSpacing, pillWidthFactor, inactiveOpacity,
 *   followThemeColors, activeColor, inactiveColor.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    QQC2.Label {
        Kirigami.FormData.label: i18n("Appearance")
        text: i18n("Not implemented yet (scaffold).")
        opacity: 0.6
    }
}
