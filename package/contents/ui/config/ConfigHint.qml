/*
 * Plasma Gnome Pager — ConfigHint.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dimmed explanatory line under a form row ("why this setting exists / what it interacts with").
 * A FormLayout row of its own with no label, so it sits in the field column under the control it explains.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../logic.js" as Logic

QQC2.Label {
    wrapMode: Text.WordWrap
    opacity: 0.7
    font: Kirigami.Theme.smallFont

    Layout.fillWidth: true
    // Pin the wrap width to the shared field column — with fillWidth alone the long text widens the
    // column and drags every other row's field with it.
    Layout.preferredWidth: Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS
}
