/*
 * Plasma Gnome Pager — ConfigPercentSlider.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A ConfigSlider preset for the 0..1 opacity keys, read out as a percentage. One home for the range,
 * the step and the format, so the four opacity rows can't drift apart. Callers set only label/enabled.
 */
import QtQuick

ConfigSlider {
    from: 0.0
    to: 1.0
    stepSize: 0.01   // 1% increments for fine control (drag or arrow keys)
    format: v => Math.round(v * 100) + "%"
}
