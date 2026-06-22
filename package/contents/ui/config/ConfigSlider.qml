/*
 * Plasma Gnome Pager — ConfigSlider.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A FormLayout row of a Slider + a right-hand value read-out. The call site supplies one `format` closure
 * (value → display string), used for BOTH the live read-out AND the reserved label width — the read-out's
 * width is RESERVED for the widest string (format applied to from/to) or the label reflows and the slider
 * appears to jump while dragging. The track is a FIXED width (NOT fillWidth) so every slider matches across
 * both config pages; the value label absorbs any extra column width. Config-page only (lazy-loaded), so the
 * Layouts/TextMetrics use never touches the always-on widget. See CLAUDE.md "ConfigSlider".
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
        // Fixed track length (NOT fillWidth): the Behavior page's long checkbox labels would stretch a
        // fillWidth track wider than the slider-only Appearance page. min == preferred so it can't shrink.
        Layout.preferredWidth: root.trackWidth
        Layout.minimumWidth: root.trackWidth
        snapMode: QQC2.Slider.SnapAlways   // clean increments even when dragged (override via alias)
    }

    QQC2.Label {
        id: valueLabel
        text: root.format(slider.value)
        horizontalAlignment: Text.AlignRight
        // fillWidth so extra column width (from a long checkbox on a sibling row) is absorbed here — the
        // right-aligned read-out pins to the column's right edge and the slider keeps its length.
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
