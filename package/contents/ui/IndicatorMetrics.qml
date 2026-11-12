/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot strip's sizes. Effective sizes shrink to fit the panel's allocation; natural and floor ones,
 * which the Layout hints read, come from the settings alone, since an allocation-dependent hint would
 * loop back through the allocation.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

import "logic.mjs" as Logic

QtObject {
    id: metrics

    property int dotSizeRequest: Logic.DEFAULTS.dotSize     // px; 0 = auto
    property int pillSizeRequest: Logic.DEFAULTS.pillSize   // px; 0 = the dot size
    property real spacingFactor: Logic.DEFAULTS.spacingFactor
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor
    property real availableMajor: 0   // along the lines; 0 before the first layout
    property real availableCross: 0
    property int perLine: 0
    property int lineCount: 0
    // In multiples of one line's thickness; 0 while the hover background is off.
    property real hoverLengthFactor: Logic.DEFAULTS.hoverLengthFactor
    property real hoverThicknessFactor: Logic.DEFAULTS.hoverThicknessFactor

    readonly property real naturalDotSize: dotSizeRequest > 0 ? dotSizeRequest : Kirigami.Units.iconSizes.small / 2
    readonly property real naturalPillSize: pillSizeRequest > 0 ? pillSizeRequest : naturalDotSize
    // The pill's thickness in dots, which carries every difference between the two.
    readonly property real pillThicknessRatio: naturalPillSize / naturalDotSize
    // Below this a dot stops being legible; capped at natural so a small configured dot never grows.
    readonly property real minDotSize: Math.min(naturalDotSize, Kirigami.Units.iconSizes.small / 4)
    readonly property real naturalLineThickness: Math.max(naturalDotSize, naturalPillSize)
    readonly property real naturalStripLength: Logic.lineExtent(perLine, naturalDotSize, naturalDotSize * spacingFactor, naturalPillSize * pillWidthFactor)
    readonly property real floorStripLength: Logic.lineExtent(perLine, minDotSize, minDotSize * spacingFactor, minDotSize * pillThicknessRatio * pillWidthFactor)
    readonly property real naturalCrossThickness: Logic.lineExtent(lineCount, naturalDotSize, naturalDotSize * spacingFactor, naturalLineThickness)
    readonly property real floorCrossThickness: Logic.lineExtent(lineCount, minDotSize, minDotSize * spacingFactor, minDotSize * Math.max(1, pillThicknessRatio))

    // Each axis's fit, infinite where nothing constrains it, so the smaller one decides.
    readonly property real majorFitDotSize: Logic.fitDotSize(availableMajor, perLine, pillThicknessRatio * pillWidthFactor, spacingFactor)
    readonly property real crossFitDotSize: Logic.fitDotSize(availableCross, lineCount, Math.max(1, pillThicknessRatio), spacingFactor)
    readonly property real fitDotSize: Math.min(majorFitDotSize, crossFitDotSize)
    readonly property real dotSize: Math.max(minDotSize, Math.min(naturalDotSize, fitDotSize))
    readonly property real pillSize: dotSize * pillThicknessRatio
    readonly property real pillWidth: pillSize * pillWidthFactor
    readonly property real dotSpacing: dotSize * spacingFactor
    readonly property real lineThickness: Math.max(dotSize, pillSize)

    // The extents of a line holding the pill, the longest at any point of a switch, which the strip is
    // pinned to. Like naturalStripLength, this assumes the pill is at least as long as a dot.
    readonly property real stripLength: Logic.lineExtent(perLine, dotSize, dotSpacing, pillWidth)
    readonly property real crossThickness: Logic.lineExtent(lineCount, dotSize, dotSpacing, lineThickness)

    // The hint-side padding reads the natural thickness, for the same loop as the hints; its Effective
    // twin shrinks with the dots. None of it feeds the fit, so the clearance never changes a dot's size.
    readonly property real hoverPadding: Logic.hoverPadding(naturalLineThickness, hoverLengthFactor)
    readonly property real hoverCrossPadding: Logic.hoverPadding(naturalLineThickness, hoverThicknessFactor)
    readonly property real hoverCrossPaddingEffective: Logic.hoverPadding(lineThickness, hoverThicknessFactor)
    readonly property real paddedStripLength: naturalStripLength + 2 * hoverPadding
    readonly property real paddedCrossThickness: naturalCrossThickness + 2 * hoverCrossPadding
    readonly property real hoverCrossExtent: Logic.hoverCrossExtent(availableCross, crossThickness, hoverCrossPaddingEffective)
}
