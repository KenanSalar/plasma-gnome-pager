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
    // Integers/bools compare exactly; the real-valued sliders use a tolerance because a value
    // dragged back onto the default (SnapAlways lands it on the step grid) can differ from the
    // schema default by a float ULP and would otherwise read "modified". Colours are QColor-backed
    // value types: strict !== compares wrapper identity, not the colour value (equal colours still
    // read "different"), so use Qt.colorEqual (Qt docs).
    readonly property bool isModified: cfg_dotSize !== cfg_dotSizeDefault
        || Math.abs(cfg_spacingFactor - cfg_spacingFactorDefault) > 1e-9
        || Math.abs(cfg_pillWidthFactor - cfg_pillWidthFactorDefault) > 1e-9
        || Math.abs(cfg_inactiveOpacity - cfg_inactiveOpacityDefault) > 1e-9
        || Math.abs(cfg_hoverOpacity - cfg_hoverOpacityDefault) > 1e-9
        || cfg_followThemeColors !== cfg_followThemeColorsDefault
        || !Qt.colorEqual(cfg_activeColor, cfg_activeColorDefault)
        || !Qt.colorEqual(cfg_inactiveColor, cfg_inactiveColorDefault)

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
        ConfigSlider {
            id: dotSize
            label: i18n("Dot size:")
            from: 0
            to: 64
            stepSize: 1
            snapMode: QQC2.Slider.SnapAlways   // whole-pixel steps
            // 0 = auto: the widget falls back to the HiDPI-aware themed size.
            valueText: dotSize.value === 0 ? i18n("Default") : i18np("%1 px", "%1 px", Math.round(dotSize.value))
            widestText: i18np("%1 px", "%1 px", Math.round(dotSize.to))   // widest numeric read-out (tracks `to`)
            widestTextAlt: i18n("Default")            // 0 shows "Default"; reserve for whichever wins
        }

        ConfigSlider {
            id: spacingFactor
            label: i18n("Spacing:")
            from: 0.0
            to: 2.0
            stepSize: 0.1
            snapMode: QQC2.Slider.SnapAlways   // keep stored value on the displayed 0.1 grid
            valueText: i18n("%1× dot", spacingFactor.value.toFixed(1))
            widestText: i18n("%1× dot", spacingFactor.to.toFixed(1))   // widest read-out (tracks `to`)
        }

        ConfigSlider {
            id: pillWidthFactor
            label: i18n("Pill length:")
            from: 1.0
            to: 6.0
            stepSize: 0.1
            snapMode: QQC2.Slider.SnapAlways   // keep stored value on the displayed 0.1 grid
            valueText: i18n("%1× dot", pillWidthFactor.value.toFixed(1))
            widestText: i18n("%1× dot", pillWidthFactor.to.toFixed(1))   // widest read-out (tracks `to`)
        }

        ConfigSlider {
            id: inactiveOpacity
            label: i18n("Inactive opacity:")
            from: 0.0
            to: 1.0
            stepSize: 0.05
            snapMode: QQC2.Slider.SnapAlways   // keep stored value on the displayed 5% grid
            valueText: Math.round(inactiveOpacity.value * 100) + "%"
            widestText: Math.round(inactiveOpacity.to * 100) + "%"   // widest read-out (tracks `to`)
        }

        ConfigSlider {
            id: hoverOpacity
            label: i18n("Hover opacity:")
            from: 0.0
            to: 1.0
            stepSize: 0.05
            snapMode: QQC2.Slider.SnapAlways   // keep stored value on the displayed 5% grid
            valueText: Math.round(hoverOpacity.value * 100) + "%"
            widestText: Math.round(hoverOpacity.to * 100) + "%"   // widest read-out (tracks `to`)
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
