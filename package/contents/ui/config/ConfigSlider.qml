/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A slider row with its value read out on the right. format gives both the read-out and the width kept
 * for it, the wider of the two ends, so the row doesn't reflow while dragging. The track has a fixed
 * length, so sliders match across pages whose label columns differ.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../logic.mjs" as Logic

RowLayout {
    id: root

    property alias value: slider.value
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias snapMode: slider.snapMode
    property string label: ""
    property var format: (v) => String(v)

    readonly property int trackWidth: Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS

    Kirigami.FormData.label: root.label

    QQC2.Slider {
        id: slider
        Layout.preferredWidth: root.trackWidth
        Layout.minimumWidth: root.trackWidth
        snapMode: QQC2.Slider.SnapAlways
    }

    QQC2.Label {
        id: valueLabel
        text: root.format(slider.value)
        horizontalAlignment: Text.AlignRight
        // Takes the column's slack, so the track keeps its length.
        Layout.fillWidth: true
        Layout.minimumWidth: Math.max(valueMetricsFrom.advanceWidth, valueMetricsTo.advanceWidth) + Kirigami.Units.smallSpacing
        Layout.preferredWidth: Layout.minimumWidth

        TextMetrics {
            id: valueMetricsFrom
            font: valueLabel.font
            text: root.format(slider.from)
        }
        TextMetrics {
            id: valueMetricsTo
            font: valueLabel.font
            text: root.format(slider.to)
        }
    }
}
