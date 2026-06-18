/*
 * GNOME Workspace Switcher — ConfigSlider.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A FormLayout row of a Slider + a right-hand value read-out. The read-out's width is RESERVED for
 * the widest string it can show (`widestText`) plus a small buffer: without that, the label's
 * implicit width changes with the value, which reflows the RowLayout and makes the slider
 * track/handle/ticks appear to jump while you drag. Pass `widestText` = the longest label the
 * slider can ever display (e.g. "100%", "2.0× dot", "Default") so the row width stays constant.
 *
 * Config-page only (lazy-loaded with the settings dialog), so the Layouts/TextMetrics use never
 * touches the always-on widget. Two-way bound via the parent page's
 * `property alias cfg_<key>: <id>.value`.
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
    property string label: ""        // the row's Kirigami.FormData label
    property string valueText: ""    // formatted read-out for the current value
    property string widestText: ""   // longest text valueText can be (reserves a stable width)
    property string widestTextAlt: "" // a second widest candidate (e.g. a "Default" sentinel the
                                       // read-out can also show); the reservation takes the wider
                                       // of the two so the row never reflows whichever string wins

    Kirigami.FormData.label: root.label

    QQC2.Slider {
        id: slider
        Layout.fillWidth: true
    }

    QQC2.Label {
        id: valueLabel
        text: root.valueText
        horizontalAlignment: Text.AlignRight
        // Pin to the widest text (+ a buffer) so the cell never resizes as the value changes.
        // widestTextAlt is "" unless set, so its metric is 0 and Math.max is a no-op by default.
        Layout.minimumWidth: Math.max(valueMetrics.advanceWidth, valueMetricsAlt.advanceWidth) + Kirigami.Units.smallSpacing
        Layout.preferredWidth: Layout.minimumWidth

        TextMetrics {
            id: valueMetrics
            font: valueLabel.font
            text: root.widestText
        }
        TextMetrics {
            id: valueMetricsAlt
            font: valueLabel.font
            text: root.widestTextAlt
        }
    }
}
