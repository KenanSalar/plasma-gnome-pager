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
 * Contract for a derived page (see ConfigGeneral/ConfigAppearance):
 *   - bind `isModified` to "any cfg_<key> differs from its cfg_<key>Default" (gates the action), and
 *   - handle `onDefaultsRequested` by resetting each cfg_<key> to its cfg_<key>Default.
 * The page's own content (a Kirigami.FormLayout) is its default child — ScrollablePage places it
 * inside its built-in ScrollView automatically.
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
