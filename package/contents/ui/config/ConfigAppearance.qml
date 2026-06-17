/*
 * GNOME Workspace Switcher — ConfigAppearance.qml (Appearance settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Appearance page of the settings dialog. Root is a Kirigami.ScrollablePage (see ConfigGeneral
 * for the rationale) so it gets the standard KDE title header ("Appearance") + spacing + scrolling.
 *
 * Each `cfg_<key>` alias name MUST match a contents/config/main.xml entry exactly. A header "Defaults"
 * action resets each key to its dialog-injected `cfg_<key>Default` (the dialog footer has none of its
 * own). Controls: the dimensionless ratios use QQC2.Slider — its `value` is a real, unlike the
 * integer-only SpinBox — with a live read-out Label. dotSize is an integer SpinBox where 0 reads as
 * "Default" (the 0 = auto sentinel → HiDPI themed size in the widget). Colours use
 * org.kde.kquickcontrols.ColorButton (the canonical Plasma picker; this page is loaded lazily only
 * when the dialog opens, so the import never affects the always-on widget — robustness.md), disabled
 * while "Follow the color scheme" is on.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.ScrollablePage {
    id: root

    property alias cfg_dotSize: dotSize.value
    property alias cfg_spacingFactor: spacingFactor.value
    property alias cfg_pillWidthFactor: pillWidthFactor.value
    property alias cfg_inactiveOpacity: inactiveOpacity.value
    property alias cfg_hoverOpacity: hoverOpacity.value
    property alias cfg_followThemeColors: followThemeColors.checked
    property alias cfg_activeColor: activeColor.color
    property alias cfg_inactiveColor: inactiveColor.color

    // Injected by the config dialog from the main.xml defaults; read by the Defaults action below.
    property int cfg_dotSizeDefault
    property real cfg_spacingFactorDefault
    property real cfg_pillWidthFactorDefault
    property real cfg_inactiveOpacityDefault
    property real cfg_hoverOpacityDefault
    property bool cfg_followThemeColorsDefault
    property color cfg_activeColorDefault
    property color cfg_inactiveColorDefault

    // True when any key on this page differs from its default (gates the Defaults action).
    readonly property bool isModified: cfg_dotSize !== cfg_dotSizeDefault
        || cfg_spacingFactor !== cfg_spacingFactorDefault
        || cfg_pillWidthFactor !== cfg_pillWidthFactorDefault
        || cfg_inactiveOpacity !== cfg_inactiveOpacityDefault
        || cfg_hoverOpacity !== cfg_hoverOpacityDefault
        || cfg_followThemeColors !== cfg_followThemeColorsDefault
        || cfg_activeColor !== cfg_activeColorDefault
        || cfg_inactiveColor !== cfg_inactiveColorDefault

    function resetDefaults() {
        cfg_dotSize = cfg_dotSizeDefault;
        cfg_spacingFactor = cfg_spacingFactorDefault;
        cfg_pillWidthFactor = cfg_pillWidthFactorDefault;
        cfg_inactiveOpacity = cfg_inactiveOpacityDefault;
        cfg_hoverOpacity = cfg_hoverOpacityDefault;
        cfg_followThemeColors = cfg_followThemeColorsDefault;
        cfg_activeColor = cfg_activeColorDefault;
        cfg_inactiveColor = cfg_inactiveColorDefault;
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
        QQC2.SpinBox {
            id: dotSize
            Kirigami.FormData.label: i18n("Dot size:")
            from: 0
            to: 64
            stepSize: 1
            // 0 = auto: the widget falls back to the HiDPI-aware themed size.
            textFromValue: (value) => value === 0 ? i18n("Default") : i18np("%1 px", "%1 px", value)
            valueFromText: (text) => text === i18n("Default") ? 0 : parseInt(text)
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Spacing:")
            QQC2.Slider {
                id: spacingFactor
                Layout.fillWidth: true
                from: 0.0
                to: 2.0
                stepSize: 0.1
            }
            QQC2.Label {
                text: i18n("%1× dot", spacingFactor.value.toFixed(1))
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Pill length:")
            QQC2.Slider {
                id: pillWidthFactor
                Layout.fillWidth: true
                from: 1.0
                to: 4.0
                stepSize: 0.1
            }
            QQC2.Label {
                text: i18n("%1× dot", pillWidthFactor.value.toFixed(1))
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Inactive opacity:")
            QQC2.Slider {
                id: inactiveOpacity
                Layout.fillWidth: true
                from: 0.0
                to: 1.0
                stepSize: 0.05
            }
            QQC2.Label {
                text: Math.round(inactiveOpacity.value * 100) + "%"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Hover opacity:")
            QQC2.Slider {
                id: hoverOpacity
                Layout.fillWidth: true
                from: 0.0
                to: 1.0
                stepSize: 0.05
            }
            QQC2.Label {
                text: Math.round(hoverOpacity.value * 100) + "%"
            }
        }

        Item {
            Kirigami.FormData.isSection: true   // a little vertical breathing room before the colours
        }

        QQC2.CheckBox {
            id: followThemeColors
            Kirigami.FormData.label: i18n("Colors:")
            text: i18n("Follow the color scheme")
        }
        KQuickControls.ColorButton {
            id: activeColor
            Kirigami.FormData.label: i18n("Active desktop:")
            enabled: !followThemeColors.checked   // custom colours apply only when not following the theme
            showAlphaChannel: false
        }
        KQuickControls.ColorButton {
            id: inactiveColor
            Kirigami.FormData.label: i18n("Inactive desktop:")
            enabled: !followThemeColors.checked
            showAlphaChannel: false
        }
    }
}
