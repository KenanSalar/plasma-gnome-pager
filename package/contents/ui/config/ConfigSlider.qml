/*
 * Plasma Gnome Pager — ConfigSlider.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A FormLayout row of a Slider + a right-hand value read-out. A call site supplies one `format`
 * closure (value → display string); this component uses it for BOTH the live read-out and the
 * reserved label width, so the format is declared once instead of being repeated across a
 * value/widest pair that must be kept in sync by hand.
 *
 * The read-out's width is RESERVED for the widest string it can show, otherwise the label's
 * implicit width changes with the value and reflows the RowLayout, making the slider
 * track/handle/ticks appear to jump while you drag. The widest is `format` applied to the slider's
 * extremes (`from`/`to`): the formatters used here are monotonic in string width with value
 * magnitude, and the sentinel sliders put their special text at `from` (0 → "Default"), so
 * reserving over {from, to} bounds every value in between.
 *
 * `snapMode` defaults to SnapAlways (every metric here wants clean increments); override via the
 * alias if a continuous slider is ever needed. Config-page only (lazy-loaded with the settings
 * dialog), so the Layouts/TextMetrics use never touches the always-on widget. Two-way bound via the
 * parent page's `property alias cfg_<key>: <id>.value`.
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

    Kirigami.FormData.label: root.label

    QQC2.Slider {
        id: slider
        Layout.fillWidth: true
        snapMode: QQC2.Slider.SnapAlways   // clean increments even when dragged (override via alias)
    }

    QQC2.Label {
        id: valueLabel
        text: root.format(slider.value)
        horizontalAlignment: Text.AlignRight
        // Reserve the widest the read-out can get (+ a buffer) so the cell never resizes mid-drag.
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
