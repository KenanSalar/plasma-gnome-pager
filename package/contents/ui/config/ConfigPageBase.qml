/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The base of both settings pages: a ScrollablePage for the dialog's title header and scrolling, plus
 * the Defaults action the dialog's footer lacks. A page lists its keys in configKeys, and both the
 * modified check and the reset run off that list.
 */
import QtQuick
import org.kde.kirigami as Kirigami

import "../logic.mjs" as Logic

Kirigami.ScrollablePage {
    id: root

    // { n, t }: the key, and bool, int, real, string or color for how it compares.
    property var configKeys: []

    readonly property bool isModified: configKeys.some(k => root.fieldChanged(k.n, k.t))

    // For combos and text fields, so they line up with the slider tracks.
    readonly property int fieldWidth: Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS

    // SnapAlways can land a real a rounding error away from its default.
    readonly property real epsilon: 1e-9

    function fieldChanged(name, kind) {
        var value = root["cfg_" + name];
        var defaultValue = root["cfg_" + name + "Default"];
        if (kind === "real")
            return Math.abs(value - defaultValue) > root.epsilon;
        if (kind === "color")
            return !Qt.colorEqual(value, defaultValue);
        return value !== defaultValue;
    }

    function resetField(name) {
        root["cfg_" + name] = root["cfg_" + name + "Default"];
    }

    function resetToDefaults() {
        root.configKeys.forEach(k => root.resetField(k.n));
    }

    actions: [
        Kirigami.Action {
            text: i18n("Defaults")
            icon.name: "edit-undo-symbolic"
            enabled: root.isModified
            onTriggered: root.resetToDefaults()
        }
    ]
}
