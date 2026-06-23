/*
 * Plasma Gnome Pager — IndicatorMetrics.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Non-visual dot-strip sizing engine (unit-tested by tst_indicatormetrics). EFFECTIVE sizes shrink to fit
 * a crowded panel (floored at minDotSize); NATURAL/floor extents (the Layout hints) depend only on
 * requests/grid, never on geometry — keep that split or you get a binding loop.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

QtObject {
    id: metrics

    // Inputs (bound by WorkspaceIndicator).
    property int dotSizeRequest: Logic.DEFAULTS.dotSize     // px; 0 = auto (HiDPI themed)
    property int pillSizeRequest: Logic.DEFAULTS.pillSize   // px pill thickness; 0 = auto (match dots)
    property real spacingFactor: Logic.DEFAULTS.spacingFactor
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor  // pill length / pill thickness
    property real availableMajor: 0   // live panel allocation along the line axis (0 before layout)
    property real availableCross: 0   // live panel allocation across the stacked lines
    property int perLine: 0           // desktops per line (KWin columns)
    property int lineCount: 0         // stacked lines (KWin rows)

    // Natural / floor — geometry-INDEPENDENT, drive the Layout hints (no loop).
    readonly property real naturalDotSize: dotSizeRequest > 0 ? dotSizeRequest : Kirigami.Units.iconSizes.small / 2
    readonly property real naturalPillSize: pillSizeRequest > 0 ? pillSizeRequest : naturalDotSize
    readonly property real pillThicknessRatio: naturalPillSize / naturalDotSize  // pill thickness in dot units; carries the dot⇄pill decoupling
    readonly property real minDotSize: Math.min(naturalDotSize, Kirigami.Units.iconSizes.small / 4)  // legibility floor, clamped ≤ natural
    readonly property real naturalStripLength: Logic.lineExtent(perLine, naturalDotSize, naturalDotSize * spacingFactor, naturalPillSize * pillWidthFactor)
    readonly property real floorStripLength: Logic.lineExtent(perLine, minDotSize, minDotSize * spacingFactor, minDotSize * pillThicknessRatio * pillWidthFactor)
    readonly property real naturalCrossThickness: Logic.lineExtent(lineCount, naturalDotSize, naturalDotSize * spacingFactor, Math.max(naturalDotSize, naturalPillSize))
    readonly property real floorCrossThickness: Logic.lineExtent(lineCount, minDotSize, minDotSize * spacingFactor, minDotSize * Math.max(1, pillThicknessRatio))

    // Effective — geometry-DEPENDENT rendered sizes (read by each WorkspaceDot). fitDotSize is the
    // inverse of lineExtent; +Infinity on an unconstrained axis, so min() picks the binding axis.
    readonly property real majorFitDotSize: Logic.fitDotSize(availableMajor, perLine, pillThicknessRatio * pillWidthFactor, spacingFactor)
    readonly property real crossFitDotSize: Logic.fitDotSize(availableCross, lineCount, Math.max(1, pillThicknessRatio), spacingFactor)
    readonly property real fitDotSize: Math.min(majorFitDotSize, crossFitDotSize)
    readonly property real dotSize: Math.max(minDotSize, Math.min(naturalDotSize, fitDotSize))  // shrink-to-fit, capped natural, floored minDotSize
    readonly property real pillSize: dotSize * pillThicknessRatio   // scales in lockstep with the dot
    readonly property real pillWidth: pillSize * pillWidthFactor    // active capsule LENGTH (major axis)
    readonly property real dotSpacing: dotSize * spacingFactor      // uniform gap between every element
}
