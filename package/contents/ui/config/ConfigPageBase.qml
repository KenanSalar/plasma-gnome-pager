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

import "../logic.js" as Logic

Kirigami.ScrollablePage {
    id: root

    // { n, t }: the key, and bool, int, real, string or color for how it compares.
    property var configKeys: []

    property bool isModified: configKeys.some(k => root.fieldChanged(root, k.n, k.t))

    // For combos and text fields, so they line up with the slider tracks.
    readonly property int fieldWidth: Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS

    // SnapAlways can land a real a rounding error away from its default.
    readonly property real epsilon: 1e-9

    function fieldChanged(page, name, kind) {
        var a = page["cfg_" + name];
        var b = page["cfg_" + name + "Default"];
        if (kind === "real")
            return Math.abs(a - b) > root.epsilon;
        if (kind === "color")
            return !Qt.colorEqual(a, b);
        return a !== b;
    }

    function resetField(page, name) {
        page["cfg_" + name] = page["cfg_" + name + "Default"];
    }

    signal defaultsRequested()
    onDefaultsRequested: configKeys.forEach(k => root.resetField(root, k.n))

    actions: [
        Kirigami.Action {
            text: i18n("Defaults")
            icon.name: "edit-undo-symbolic"
            enabled: root.isModified
            onTriggered: root.defaultsRequested()
        }
    ]
}
