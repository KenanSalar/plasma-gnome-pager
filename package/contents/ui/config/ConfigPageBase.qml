/*
 * Plasma Gnome Pager — ConfigPageBase.qml (shared settings-page base)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The shared skeleton for every settings page: a Kirigami.ScrollablePage (on robustness.md's
 * allowlist; the stock KCM.SimpleKCM is just a thin subclass) so each page gets the standard KDE
 * title header + top spacing + scrolling. The Plasma applet config dialog footer is only
 * Apply/Discard/Cancel — it has NO "Defaults" button of its own — so this base adds one as a
 * header action, defined ONCE here instead of copy-pasted onto each page.
 *
 * Contract for a derived page (see ConfigGeneral/ConfigAppearance): declare one `configKeys`
 * list of { n: <key>, t: "bool"|"int"|"real"|"string"|"color" }, then
 *   - isModified: configKeys.some(k => root.fieldChanged(root, k.n, k.t))   // gates the action
 *   - onDefaultsRequested: configKeys.forEach(k => root.resetField(root, k.n))
 * so the compare/reset logic isn't hand-written per key. The page's own content (a
 * Kirigami.FormLayout) is its default child — ScrollablePage places it inside its built-in
 * ScrollView automatically.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: root

    // Derived page binds this to its per-key "differs from default" check.
    property bool isModified: false

    // The settings forms' field-column width: a derived page pins its non-slider fields (e.g. a
    // TextField) to this so they line up with the sliders. Kept equal to ConfigSlider.trackWidth
    // (the same Kirigami.Units.gridUnit * 18) so every row's field column is the same width.
    readonly property int fieldWidth: Kirigami.Units.gridUnit * 18

    // Tolerance for real-valued "differs from default" checks: SnapAlways can land a value a float
    // ULP off the schema default, which would otherwise read "modified". Shared so no page redefines it.
    readonly property real epsilon: 1e-9

    // Does cfg_<name> differ from cfg_<name>Default? Type-aware: reals compare within epsilon, colours
    // via Qt.colorEqual (QColor wrappers compare by identity under !==, not value), everything else
    // exact. Lets a page generate isModified from its configKeys list. `page` is the derived page.
    function fieldChanged(page, name, kind) {
        var a = page["cfg_" + name];
        var b = page["cfg_" + name + "Default"];
        if (kind === "real")
            return Math.abs(a - b) > root.epsilon;
        if (kind === "color")
            return !Qt.colorEqual(a, b);
        return a !== b;
    }

    // Reset cfg_<name> to its injected schema default — the Defaults handler is one forEach over the
    // same configKeys list.
    function resetField(page, name) {
        page["cfg_" + name] = page["cfg_" + name + "Default"];
    }

    // Raised by the Defaults action; the derived page resets its cfg_<key> values in the handler.
    signal defaultsRequested()

    actions: [
        Kirigami.Action {
            text: i18n("Defaults")
            icon.name: "edit-undo-symbolic"
            enabled: root.isModified
            onTriggered: root.defaultsRequested()
        }
    ]
}
