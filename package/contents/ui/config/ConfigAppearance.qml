/*
 * Plasma Gnome Pager — ConfigAppearance.qml (Appearance settings page)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Appearance page, built on ConfigPageBase. Ratios use ConfigSlider; dotSize/pillSize are integer
 * sliders where 0 reads "Default"/"Match dots" (the 0 = auto sentinel). Colours use ColorButton, lazy-loaded
 * with the dialog so the import never affects the always-on widget. Each `cfg_<key>` MUST match main.xml.
 */
pragma ComponentBehavior: Bound   // the occupancyStyle delegate references outer ids (occupancyStyle/root)

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

ConfigPageBase {
    id: root

    property alias cfg_dotStyle: dotStyle.currentIndex
    property alias cfg_dotSize: dotSize.value
    property alias cfg_pillSize: pillSize.value
    property alias cfg_spacingFactor: spacingFactor.value
    property alias cfg_pillWidthFactor: pillWidthFactor.value
    property alias cfg_inactiveOpacity: inactiveOpacity.value
    property alias cfg_hoverOpacity: hoverOpacity.value
    property alias cfg_showOccupancy: showOccupancy.checked
    property alias cfg_occupancyStyle: occupancyStyle.currentIndex
    property alias cfg_occupiedOpacity: occupiedOpacity.value
    property alias cfg_followThemeColors: followThemeColors.checked
    property alias cfg_activeColor: activeColor.color
    property alias cfg_inactiveColor: inactiveColor.color
    property alias cfg_occupiedColor: occupiedColor.color

    // Injected by the config dialog from the main.xml defaults; read by the Defaults handler below.
    property int cfg_dotStyleDefault
    property int cfg_dotSizeDefault
    property int cfg_pillSizeDefault
    property real cfg_spacingFactorDefault
    property real cfg_pillWidthFactorDefault
    property real cfg_inactiveOpacityDefault
    property real cfg_hoverOpacityDefault
    property bool cfg_showOccupancyDefault
    property int cfg_occupancyStyleDefault
    property real cfg_occupiedOpacityDefault
    property bool cfg_followThemeColorsDefault
    property color cfg_activeColorDefault
    property color cfg_inactiveColorDefault
    property color cfg_occupiedColorDefault

    // This page's keys + compare kind; ConfigPageBase binds isModified + the Defaults reset off it
    // (reals within epsilon, colours via Qt.colorEqual).
    configKeys: [
        { n: "dotStyle", t: "int" },
        { n: "dotSize", t: "int" },
        { n: "pillSize", t: "int" },
        { n: "spacingFactor", t: "real" },
        { n: "pillWidthFactor", t: "real" },
        { n: "inactiveOpacity", t: "real" },
        { n: "hoverOpacity", t: "real" },
        { n: "showOccupancy", t: "bool" },
        { n: "occupancyStyle", t: "int" },
        { n: "occupiedOpacity", t: "real" },
        { n: "followThemeColors", t: "bool" },
        { n: "activeColor", t: "color" },
        { n: "inactiveColor", t: "color" },
        { n: "occupiedColor", t: "color" }
    ]

    // Which pager style is selected, by the dotStyle combo index (order matches Logic.DOT_STYLE / main.xml:
    // 0 = Sliding pill, 1 = Filled & ring). The pill knobs only apply to Sliding pill; Filled & ring disables
    // the redundant Hollow ring occupancy marker. Named once here so the index checks aren't repeated below.
    readonly property bool pillStyle: dotStyle.currentIndex === 0
    readonly property bool ringStyle: dotStyle.currentIndex === 1

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: dotStyle
            Kirigami.FormData.label: i18n("Pager style:")
            // Order MUST match Logic.DOT_STYLE / main.xml dotStyle (currentIndex is stored as the index).
            model: [i18n("Sliding pill"), i18n("Filled & ring")]
            Layout.preferredWidth: root.fieldWidth   // match the other field widths (ConfigPageBase.fieldWidth)
            // Filled & ring disables the Hollow ring occupancy marker (index 2) — the dot is already a ring —
            // so migrate a previously-chosen Hollow ring to Filled (0) when the user switches to it.
            onActivated: {
                if (root.ringStyle && occupancyStyle.currentIndex === 2)
                    occupancyStyle.currentIndex = 0;
            }
        }

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
            // "Thickness" (not "size") disambiguates from "Pill length:" below — the pill's two axes (also avoids an msgmerge fuzzy collision).
            label: i18n("Pill thickness:")
            enabled: root.pillStyle   // the pill only exists in the Sliding pill style
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
            enabled: root.pillStyle   // the pill only exists in the Sliding pill style
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

        QQC2.CheckBox {
            id: showOccupancy
            Kirigami.FormData.label: i18n("Occupied desktops:")
            text: i18n("Highlight desktops with open windows")
        }
        QQC2.ComboBox {
            id: occupancyStyle
            Kirigami.FormData.label: i18n("Indicator style:")
            enabled: showOccupancy.checked
            // Order MUST match Logic.OCCUPANCY / main.xml occupancyStyle (currentIndex is stored as the index).
            model: [i18n("Filled"), i18n("Inner dot"), i18n("Hollow ring")]
            // "Hollow ring" (index 2) is redundant in the Filled & ring pager style — the dot is ALREADY a
            // hollow ring — so disable that item there (selection blocked; a stored value is suppressed at runtime).
            delegate: QQC2.ItemDelegate {
                id: occStyleItem
                required property int index
                required property string modelData
                width: occupancyStyle.width
                text: occStyleItem.modelData
                enabled: !(root.ringStyle && occStyleItem.index === 2)
                highlighted: occupancyStyle.highlightedIndex === occStyleItem.index
            }
        }
        ConfigSlider {
            id: occupiedOpacity
            label: i18n("Occupied opacity:")
            enabled: showOccupancy.checked   // every indicator style uses the occupied-marker opacity
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
        KQuickControls.ColorButton {
            id: occupiedColor
            Kirigami.FormData.label: i18n("Occupied desktop:")
            enabled: !followThemeColors.checked   // the occupied marker; theme accent is used while following the scheme
            showAlphaChannel: false
        }
    }
}
