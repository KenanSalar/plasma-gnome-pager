/*
 * GNOME Workspace Switcher — ConfigGeneral.qml (Behavior settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Behavior page of the settings dialog. Root is a Kirigami.ScrollablePage (on robustness.md's
 * allowlist; the stock KCM.SimpleKCM is just a thin subclass of it) so the page gets the standard
 * KDE title header ("Behavior") + top spacing + scrolling, matching the other Plasma widgets.
 *
 * Each `cfg_<key>` alias name MUST match a contents/config/main.xml entry exactly; the dialog then
 * wires load/save automatically. The dialog has NO "Defaults" button of its own (its footer is only
 * Apply/Discard/Cancel — verified in AppletConfiguration.qml), so we add one as a header action that
 * resets each key to `cfg_<key>Default` — a property the dialog injects with the schema default
 * (declared below, no initializer, so main.xml stays the single source of truth). Public
 * Kirigami + QtQuick.Controls only (not PlasmaComponents) — see plasmoid.md / kirigami.md.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.ScrollablePage {
    id: root

    property alias cfg_enableScroll: enableScroll.checked
    property alias cfg_scrollWrap: scrollWrap.checked
    property alias cfg_showTooltips: showTooltips.checked
    property alias cfg_enableAddRemove: enableAddRemove.checked
    property alias cfg_animationDuration: animationDuration.value

    // Injected by the config dialog from the main.xml defaults; read by the Defaults action below.
    // Declared (no initializer) so QML can reference them and the dialog has somewhere to write.
    property bool cfg_enableScrollDefault
    property bool cfg_scrollWrapDefault
    property bool cfg_showTooltipsDefault
    property bool cfg_enableAddRemoveDefault
    property int cfg_animationDurationDefault

    // True when any key on this page differs from its default (gates the Defaults action).
    readonly property bool isModified: cfg_enableScroll !== cfg_enableScrollDefault
        || cfg_scrollWrap !== cfg_scrollWrapDefault
        || cfg_showTooltips !== cfg_showTooltipsDefault
        || cfg_enableAddRemove !== cfg_enableAddRemoveDefault
        || cfg_animationDuration !== cfg_animationDurationDefault

    function resetDefaults() {
        cfg_enableScroll = cfg_enableScrollDefault;
        cfg_scrollWrap = cfg_scrollWrapDefault;
        cfg_showTooltips = cfg_showTooltipsDefault;
        cfg_enableAddRemove = cfg_enableAddRemoveDefault;
        cfg_animationDuration = cfg_animationDurationDefault;
    }

    actions: [
        Kirigami.Action {
            text: i18n("Defaults")
            icon.name: "edit-undo-symbolic"
            enabled: root.isModified
            onTriggered: root.resetDefaults()
        }
    ]

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enableScroll
            Kirigami.FormData.label: i18n("Mouse:")
            text: i18n("Scroll over the pager to switch desktops")
        }
        QQC2.CheckBox {
            id: scrollWrap
            text: i18n("Wrap around at the first and last desktop")
            enabled: enableScroll.checked   // wrap only matters when scrolling is on
        }
        QQC2.CheckBox {
            id: showTooltips
            Kirigami.FormData.label: i18n("Tooltips:")
            text: i18n("Show the desktop name on hover")
        }
        QQC2.CheckBox {
            id: enableAddRemove
            Kirigami.FormData.label: i18n("Menu:")
            text: i18n("Add and remove desktops from the right-click menu")
        }

        ConfigSlider {
            id: animationDuration
            label: i18n("Animation duration:")
            from: 0
            to: 2000
            stepSize: 50
            snapMode: QQC2.Slider.SnapAlways   // clean 50 ms increments even when dragged
            // 0 = follow the theme's default (and the global "reduce animations" setting).
            valueText: animationDuration.value === 0 ? i18n("Default") : i18np("%1 ms", "%1 ms", Math.round(animationDuration.value))
            widestText: i18np("%1 ms", "%1 ms", Math.round(animationDuration.to))   // widest numeric read-out (tracks `to`)
            widestTextAlt: i18n("Default")   // the read-out also shows "Default" at 0; reserve for both
        }
    }
}
