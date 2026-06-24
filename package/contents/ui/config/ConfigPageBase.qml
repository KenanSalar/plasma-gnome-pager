/*
 * Plasma Gnome Pager — ConfigPageBase.qml (shared settings-page base)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Shared skeleton for every settings page: a Kirigami.ScrollablePage for the KDE header + scrolling, plus
 * the "Defaults" button the Plasma footer lacks (defined ONCE here). A derived page only declares its
 * `configKeys` { n, t } list; the modified-check and the Defaults reset are bound off it here, once.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: root

    // The derived page's keys + compare kind ({ n, t }); drives both isModified and the Defaults reset.
    property var configKeys: []

    // True when any key differs from its default (gates the Defaults action). Bound off configKeys here
    // so a derived page need only declare the list; empty configKeys ⇒ false (unmodified).
    property bool isModified: configKeys.some(k => root.fieldChanged(root, k.n, k.t))

    // Field-column width for non-slider fields; kept equal to ConfigSlider.trackWidth so every row lines up.
    readonly property int fieldWidth: Kirigami.Units.gridUnit * 18

    // Tolerance for real-valued "differs from default": SnapAlways can land a value a ULP off the default.
    readonly property real epsilon: 1e-9

    // Does cfg_<name> differ from cfg_<name>Default? Type-aware: reals within epsilon, colours via Qt.colorEqual, else exact.
    function fieldChanged(page, name, kind) {
        var a = page["cfg_" + name];
        var b = page["cfg_" + name + "Default"];
        if (kind === "real")
            return Math.abs(a - b) > root.epsilon;
        if (kind === "color")
            return !Qt.colorEqual(a, b);
        return a !== b;
    }

    // Reset cfg_<name> to its injected schema default.
    function resetField(page, name) {
        page["cfg_" + name] = page["cfg_" + name + "Default"];
    }

    // Raised by the Defaults action; resets every configKeys entry to its injected schema default.
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
