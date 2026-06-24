/*
 * Plasma Gnome Pager — ConfigSlider.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A FormLayout row of a Slider + a right-hand value read-out. One `format` closure (value → string) drives
 * BOTH the read-out AND its reserved width (widest of from/to) so the label can't reflow mid-drag. The
 * track is a FIXED width (NOT fillWidth) so sliders match across both pages; the value label absorbs slack.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property alias value: slider.value
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias snapMode: slider.snapMode
    property string label: ""              // the row's Kirigami.FormData label
    property var format: (v) => String(v)  // value → read-out string (drives text AND reserved width)

    // Fixed track length, matched to ConfigPageBase.fieldWidth so every row's field column lines up.
    readonly property int trackWidth: Kirigami.Units.gridUnit * 18

    Kirigami.FormData.label: root.label

    QQC2.Slider {
        id: slider
        // Fixed track length (NOT fillWidth): a fillWidth track would stretch wider on the Behavior page's long labels. min == preferred so it can't shrink.
        Layout.preferredWidth: root.trackWidth
        Layout.minimumWidth: root.trackWidth
        snapMode: QQC2.Slider.SnapAlways   // clean increments even when dragged (override via alias)
    }

    QQC2.Label {
        id: valueLabel
        text: root.format(slider.value)
        horizontalAlignment: Text.AlignRight
        // fillWidth so extra column width is absorbed here — the right-aligned read-out pins to the column edge and the slider keeps its length.
        Layout.fillWidth: true
        // Reserve the widest the read-out can get (+ buffer) so the cell never resizes mid-drag.
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
