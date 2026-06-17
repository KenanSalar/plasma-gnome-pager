/*
 * GNOME Workspace Switcher — ConfigAppearance.qml (Appearance settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Appearance page of the settings dialog. Each `cfg_<key>` alias name MUST match a
 * contents/config/main.xml entry exactly; the dialog wires load/save/defaults automatically.
 *
 * Controls: the dimensionless ratios (spacing/pill/opacities) use QQC2.Slider — its `value` is a
 * real, unlike the integer-only SpinBox — paired with a live read-out Label. dotSize is an integer
 * SpinBox where 0 reads as "Default" (the 0 = auto sentinel → HiDPI themed size in the widget).
 * Colours use org.kde.kquickcontrols.ColorButton (the canonical Plasma picker; this page is loaded
 * lazily only when the dialog opens, so it never affects the always-on running widget — robustness.md),
 * disabled while "Follow the color scheme" is on.
 */
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    property alias cfg_dotSize: dotSize.value
    property alias cfg_spacingFactor: spacingFactor.value
    property alias cfg_pillWidthFactor: pillWidthFactor.value
    property alias cfg_inactiveOpacity: inactiveOpacity.value
    property alias cfg_hoverOpacity: hoverOpacity.value
    property alias cfg_followThemeColors: followThemeColors.checked
    property alias cfg_activeColor: activeColor.color
    property alias cfg_inactiveColor: inactiveColor.color

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
