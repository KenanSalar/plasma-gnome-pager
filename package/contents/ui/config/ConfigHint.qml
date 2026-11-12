/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dimmed line explaining the form row above it: a row of its own with no label, so it sits in the
 * field column under that control.
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
    // On fillWidth alone, a long hint would widen the field column and every row with it.
    Layout.preferredWidth: Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS
}
