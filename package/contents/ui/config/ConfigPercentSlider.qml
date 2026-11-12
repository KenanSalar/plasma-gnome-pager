/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A ConfigSlider for the 0..1 opacity keys, read out as a percentage, so the opacity rows can't drift apart.
 */
import QtQuick

ConfigSlider {
    from: 0.0
    to: 1.0
    stepSize: 0.01
    format: v => Math.round(v * 100) + "%"
}
