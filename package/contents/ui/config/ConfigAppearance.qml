/*
 * Plasma Gnome Pager — ConfigAppearance.qml (Appearance settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Appearance page of the settings dialog. Built on ConfigPageBase (KDE title header + the shared
 * "Defaults" header action). Controls: the dimensionless ratios use ConfigSlider (its `value` is a
 * real, unlike the integer-only SpinBox) with a live read-out; dotSize is an integer slider where 0
 * reads as "Default" (the 0 = auto sentinel → HiDPI themed size in the widget). Colours use
 * org.kde.kquickcontrols.ColorButton (the canonical Plasma picker; this page is loaded lazily only
 * when the dialog opens, so the import never affects the always-on widget — robustness.md), disabled
 * while "Follow the color scheme" is on.
 *
 * Each `cfg_<key>` alias name MUST match a contents/config/main.xml entry exactly. This page fulfils
 * ConfigPageBase's contract: it binds `isModified` and handles `onDefaultsRequested`.
 */
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

ConfigPageBase {
    id: root

    property alias cfg_dotSize: dotSize.value
    property alias cfg_pillSize: pillSize.value
    property alias cfg_spacingFactor: spacingFactor.value
    property alias cfg_pillWidthFactor: pillWidthFactor.value
    property alias cfg_inactiveOpacity: inactiveOpacity.value
    property alias cfg_hoverOpacity: hoverOpacity.value
    property alias cfg_followThemeColors: followThemeColors.checked
    property alias cfg_activeColor: activeColor.color
    property alias cfg_inactiveColor: inactiveColor.color

    // Injected by the config dialog from the main.xml defaults; read by the Defaults handler below.
    property int cfg_dotSizeDefault
    property int cfg_pillSizeDefault
    property real cfg_spacingFactorDefault
    property real cfg_pillWidthFactorDefault
    property real cfg_inactiveOpacityDefault
    property real cfg_hoverOpacityDefault
    property bool cfg_followThemeColorsDefault
    property color cfg_activeColorDefault
    property color cfg_inactiveColorDefault

    // Single source for this page's keys + their compare kind; drives BOTH isModified and the
    // Defaults reset via ConfigPageBase.fieldChanged/resetField. The kind picks the comparison:
    // reals compare within epsilon, colours via Qt.colorEqual (QColor wrappers are identity-compared
    // by !==, not value), ints/bools exact — so no per-key comparison is hand-written here.
    readonly property var configKeys: [
        { n: "dotSize", t: "int" },
        { n: "pillSize", t: "int" },
        { n: "spacingFactor", t: "real" },
        { n: "pillWidthFactor", t: "real" },
        { n: "inactiveOpacity", t: "real" },
        { n: "hoverOpacity", t: "real" },
        { n: "followThemeColors", t: "bool" },
        { n: "activeColor", t: "color" },
        { n: "inactiveColor", t: "color" }
    ]

    // True when any key differs from its default (gates the base's Defaults action).
    isModified: configKeys.some(k => root.fieldChanged(root, k.n, k.t))
    onDefaultsRequested: configKeys.forEach(k => root.resetField(root, k.n))

    Kirigami.FormLayout {
        ConfigSlider {
            id: dotSize
            label: i18n("Dot size:")
            from: 0
            to: 64
            stepSize: 1
            // 0 = auto: the widget falls back to the HiDPI-aware themed size.
            format: v => v === 0 ? i18n("Default") : i18np("%1 px", "%1 px", Math.round(v))
        }

        ConfigSlider {
            id: pillSize
            // "Thickness" (not "size") to disambiguate from the "Pill length:" slider below — the two
            // controls are the pill's two axes — and so msgmerge can't fuzzy-collide it with "Pill length:".
            label: i18n("Pill thickness:")
            from: 0
            to: 64
            stepSize: 1
            // 0 = auto: the pill thickness matches the (effective) dot size, so the pill tracks the dots.
            format: v => v === 0 ? i18n("Match dots") : i18np("%1 px", "%1 px", Math.round(v))
        }

        ConfigSlider {
            id: spacingFactor
            label: i18n("Spacing:")
            from: 0.0
            to: 2.0
            stepSize: 0.05
            format: v => i18n("%1× dot", v.toFixed(2))
        }

        ConfigSlider {
            id: pillWidthFactor
            label: i18n("Pill length:")
            from: 1.0
            to: 10.0
            stepSize: 0.1
            // Length as a multiple of the PILL thickness (its aspect ratio), not the dot size.
            format: v => i18n("%1× pill", v.toFixed(1))
        }

        ConfigSlider {
            id: inactiveOpacity
            label: i18n("Inactive opacity:")
            from: 0.0
            to: 1.0
            stepSize: 0.01   // 1% increments for fine control (drag or arrow keys)
            format: v => Math.round(v * 100) + "%"
        }

        ConfigSlider {
            id: hoverOpacity
            label: i18n("Hover opacity:")
            from: 0.0
            to: 1.0
            stepSize: 0.01   // 1% increments for fine control (drag or arrow keys)
            format: v => Math.round(v * 100) + "%"
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
