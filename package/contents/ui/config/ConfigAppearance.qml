/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The Appearance settings page.
 */
pragma ComponentBehavior: Bound   // the occupancy combo's delegate reads outer ids

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

import "../logic.js" as Logic

ConfigPageBase {
    id: root

    property alias cfg_dotStyle: dotStyle.currentIndex
    property alias cfg_singleLine: singleLine.checked
    property alias cfg_matchDesktopGrid: matchDesktopGrid.checked
    property alias cfg_spacingFactor: spacingFactor.value
    property alias cfg_dotSize: dotSize.value
    property alias cfg_inactiveOpacity: inactiveOpacity.value
    property alias cfg_hoverOpacity: hoverOpacity.value
    property alias cfg_pillSize: pillSize.value
    property alias cfg_pillWidthFactor: pillWidthFactor.value
    property alias cfg_showHoverBackground: showHoverBackground.checked
    property alias cfg_hoverBackgroundOpacity: hoverBackgroundOpacity.value
    property alias cfg_hoverLengthFactor: hoverLengthFactor.value
    property alias cfg_hoverThicknessFactor: hoverThicknessFactor.value
    property alias cfg_showOccupancy: showOccupancy.checked
    property alias cfg_occupancyStyle: occupancyStyle.currentIndex
    property alias cfg_occupiedOpacity: occupiedOpacity.value
    property alias cfg_followThemeColors: followThemeColors.checked
    property alias cfg_activeColor: activeColor.color
    property alias cfg_inactiveColor: inactiveColor.color
    property alias cfg_occupiedColor: occupiedColor.color
    property alias cfg_hoverBackgroundColor: hoverBackgroundColor.color

    // The dialog sets these from main.xml.
    property int cfg_dotStyleDefault
    property bool cfg_singleLineDefault
    property bool cfg_matchDesktopGridDefault
    property real cfg_spacingFactorDefault
    property int cfg_dotSizeDefault
    property real cfg_inactiveOpacityDefault
    property real cfg_hoverOpacityDefault
    property int cfg_pillSizeDefault
    property real cfg_pillWidthFactorDefault
    property bool cfg_showHoverBackgroundDefault
    property real cfg_hoverBackgroundOpacityDefault
    property real cfg_hoverLengthFactorDefault
    property real cfg_hoverThicknessFactorDefault
    property bool cfg_showOccupancyDefault
    property int cfg_occupancyStyleDefault
    property real cfg_occupiedOpacityDefault
    property bool cfg_followThemeColorsDefault
    property color cfg_activeColorDefault
    property color cfg_inactiveColorDefault
    property color cfg_occupiedColorDefault
    property color cfg_hoverBackgroundColorDefault

    configKeys: [
        { n: "dotStyle", t: "int" },
        { n: "singleLine", t: "bool" },
        { n: "matchDesktopGrid", t: "bool" },
        { n: "spacingFactor", t: "real" },
        { n: "dotSize", t: "int" },
        { n: "inactiveOpacity", t: "real" },
        { n: "hoverOpacity", t: "real" },
        { n: "pillSize", t: "int" },
        { n: "pillWidthFactor", t: "real" },
        { n: "showHoverBackground", t: "bool" },
        { n: "hoverBackgroundOpacity", t: "real" },
        { n: "hoverLengthFactor", t: "real" },
        { n: "hoverThicknessFactor", t: "real" },
        { n: "showOccupancy", t: "bool" },
        { n: "occupancyStyle", t: "int" },
        { n: "occupiedOpacity", t: "real" },
        { n: "followThemeColors", t: "bool" },
        { n: "activeColor", t: "color" },
        { n: "inactiveColor", t: "color" },
        { n: "occupiedColor", t: "color" },
        { n: "hoverBackgroundColor", t: "color" }
    ]

    readonly property bool pillStyle: dotStyle.currentIndex === Logic.DOT_STYLE.Pill
    readonly property bool ringStyle: Logic.isRingStyle(dotStyle.currentIndex)

    Kirigami.FormLayout {
        // It decides which of the groups below apply, so it leads the page on its own.
        QQC2.ComboBox {
            id: dotStyle
            Kirigami.FormData.label: i18n("Pager style:")
            // The index is the stored value, in Logic.DOT_STYLE's order.
            model: [i18n("Sliding pill"), i18n("Filled & ring")]
            Layout.preferredWidth: root.fieldWidth
            // A ring-style dot is already a ring, so a stored Hollow ring marker becomes Filled.
            onActivated: {
                if (root.ringStyle && occupancyStyle.currentIndex === Logic.OCCUPANCY.Ring)
                    occupancyStyle.currentIndex = Logic.OCCUPANCY.Filled;
            }
        }

        ConfigSection {
            title: i18n("Layout")
        }
        QQC2.CheckBox {
            id: singleLine
            text: i18n("Show all desktops in a single line")
        }
        ConfigHint {
            text: i18n("Ignore the grid rows from System Settings and lay every desktop out in one strip along the panel (a single vertical strip on a vertical panel).")
        }
        QQC2.CheckBox {
            id: matchDesktopGrid
            text: i18n("Match the virtual-desktop grid layout")
            // Not greyed under a single line: with it, this turns that line across the panel.
        }
        ConfigHint {
            text: i18n("Arrange the dots like the desktop grid in System Settings (rows top to bottom) instead of running them down the panel. No effect on horizontal panels.")
        }
        ConfigSlider {
            id: spacingFactor
            label: i18n("Spacing:")
            from: 0.0
            to: 2.0
            stepSize: 0.05
            format: v => i18n("%1× dot", v.toFixed(2))
        }

        ConfigSection {
            title: i18n("Dots")
        }
        ConfigSlider {
            id: dotSize
            label: i18n("Dot size:")
            from: 0
            to: 64
            stepSize: 1
            format: v => v === 0 ? i18n("Default") : i18np("%1 px", "%1 px", Math.round(v))
        }
        ConfigPercentSlider {
            id: inactiveOpacity
            label: i18n("Inactive opacity:")
        }
        ConfigPercentSlider {
            id: hoverOpacity
            label: i18n("Hover opacity:")
        }

        ConfigSection {
            title: i18n("Active pill")
        }
        ConfigSlider {
            id: pillSize
            // "Thickness" sets it apart from "Pill length:", and keeps msgmerge from fuzzy-matching the two.
            label: i18n("Pill thickness:")
            enabled: root.pillStyle
            from: 0
            to: 64
            stepSize: 1
            format: v => v === 0 ? i18n("Match dots") : i18np("%1 px", "%1 px", Math.round(v))
        }
        ConfigSlider {
            id: pillWidthFactor
            label: i18n("Pill length:")
            enabled: root.pillStyle
            from: 1.0
            to: 10.0
            stepSize: 0.1
            format: v => i18n("%1× pill", v.toFixed(1))
        }

        ConfigSection {
            title: i18n("Hover background")
        }
        QQC2.CheckBox {
            id: showHoverBackground
            text: i18n("Highlight the whole pager on hover")
        }
        ConfigPercentSlider {
            id: hoverBackgroundOpacity
            label: i18n("Background opacity:")
            enabled: showHoverBackground.checked
        }
        ConfigSlider {
            id: hoverLengthFactor
            label: i18n("Extra length:")
            enabled: showHoverBackground.checked
            from: 0.0
            to: 3.0
            stepSize: 0.05
            format: v => i18n("%1× pill", v.toFixed(2))
        }
        ConfigSlider {
            id: hoverThicknessFactor
            label: i18n("Extra thickness:")
            enabled: showHoverBackground.checked
            from: 0.0
            to: 3.0
            stepSize: 0.05
            format: v => i18n("%1× pill", v.toFixed(2))
        }
        ConfigHint {
            text: i18n("Space the background leaves around the dots, at each end and on each side. Raise the thickness on a tall panel; it never grows past the panel.")
        }

        ConfigSection {
            title: i18n("Occupied desktops")
        }
        QQC2.CheckBox {
            id: showOccupancy
            text: i18n("Highlight desktops with open windows")
        }
        QQC2.ComboBox {
            id: occupancyStyle
            Kirigami.FormData.label: i18n("Indicator style:")
            enabled: showOccupancy.checked
            Layout.preferredWidth: root.fieldWidth
            // The index is the stored value, in Logic.OCCUPANCY's order.
            model: [i18n("Filled"), i18n("Inner dot"), i18n("Hollow ring")]
            // A ring-style dot is already a ring, so Hollow ring can't be picked there.
            delegate: QQC2.ItemDelegate {
                id: occStyleItem
                required property int index
                required property string modelData
                width: occupancyStyle.width
                text: occStyleItem.modelData
                enabled: !(root.ringStyle && occStyleItem.index === Logic.OCCUPANCY.Ring)
                highlighted: occupancyStyle.highlightedIndex === occStyleItem.index
            }
        }
        ConfigPercentSlider {
            id: occupiedOpacity
            label: i18n("Occupied opacity:")
            enabled: showOccupancy.checked
        }

        ConfigSection {
            title: i18n("Colors")
        }
        QQC2.CheckBox {
            id: followThemeColors
            text: i18n("Follow the color scheme")
        }
        KQuickControls.ColorButton {
            id: activeColor
            Kirigami.FormData.label: i18n("Active desktop:")
            enabled: !followThemeColors.checked
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
            enabled: !followThemeColors.checked && showOccupancy.checked
            showAlphaChannel: false
        }
        KQuickControls.ColorButton {
            id: hoverBackgroundColor
            // Named for the effect: the other rows read "<what> desktop:", and "Hover background" would
            // repeat the section's heading.
            Kirigami.FormData.label: i18n("Hover highlight:")
            // The opacity slider sets the alpha, so the two stay independent.
            enabled: !followThemeColors.checked && showHoverBackground.checked
            showAlphaChannel: false
        }
    }
}
