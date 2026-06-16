/*
 * GNOME Workspace Switcher — WorkspaceDot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * SCAFFOLD ONLY. A single GNOME-style workspace dot (inactive look).
 *
 * TODO(impl):
 *   property string desktopId
 *   property bool   active
 *   property int    desktopIndex
 *   signal activated()
 *   - MouseArea for click (-> activated()) and hover brighten.
 *   - color/opacity bindings: active uses Kirigami.Theme.highlightColor,
 *     inactive uses theme text color at configuration.inactiveOpacity.
 *   - Honour plasmoid.configuration.followThemeColors / activeColor / inactiveColor.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: dot

    implicitWidth: Kirigami.Units.iconSizes.small / 2
    implicitHeight: implicitWidth
    radius: height / 2

    color: Kirigami.Theme.textColor
    opacity: 0.45
}
