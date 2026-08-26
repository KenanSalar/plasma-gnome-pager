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

    // Hover-background clearance: how much room the strip asks for AROUND itself, per axis, each as a
    // multiple of one line's thickness. The indicator zeroes both when the background is off (the same
    // neutralize-at-the-input idiom the ring style uses on the pill params), so no feature flag here.
    property real hoverLengthFactor: Logic.DEFAULTS.hoverLengthFactor        // extra length at EACH end
    property real hoverThicknessFactor: Logic.DEFAULTS.hoverThicknessFactor  // extra thickness on EACH side

    // Natural / floor — geometry-INDEPENDENT, drive the Layout hints (no loop).
    readonly property real naturalDotSize: dotSizeRequest > 0 ? dotSizeRequest : Kirigami.Units.iconSizes.small / 2
    readonly property real naturalPillSize: pillSizeRequest > 0 ? pillSizeRequest : naturalDotSize
    readonly property real pillThicknessRatio: naturalPillSize / naturalDotSize  // pill thickness in dot units; carries the dot⇄pill decoupling
    readonly property real minDotSize: Math.min(naturalDotSize, Kirigami.Units.iconSizes.small / 4)  // legibility floor, clamped ≤ natural
    // One line's thickness: a dot, or the pill where it is thicker. Also the unit the hover clearance is
    // measured in — NOT the whole strip, so a multi-row grid keeps the same margin instead of a multiple.
    readonly property real naturalLineThickness: Math.max(naturalDotSize, naturalPillSize)
    readonly property real naturalStripLength: Logic.lineExtent(perLine, naturalDotSize, naturalDotSize * spacingFactor, naturalPillSize * pillWidthFactor)
    readonly property real floorStripLength: Logic.lineExtent(perLine, minDotSize, minDotSize * spacingFactor, minDotSize * pillThicknessRatio * pillWidthFactor)
    readonly property real naturalCrossThickness: Logic.lineExtent(lineCount, naturalDotSize, naturalDotSize * spacingFactor, naturalLineThickness)
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
    readonly property real lineThickness: Math.max(dotSize, pillSize)   // rendered twin of naturalLineThickness

    // Conserved (capsule-bearing) line extents — the length/thickness of a line that HOLDS the capsule, which
    // is the MAX over all lines and is independent of the morph progress. The indicator pins the strip to these
    // so a cross-row morph can't resize+recenter it (else the dots "breathe"/drift). Effective (post-scale-to-fit).
    // Assumes pillWidth >= dotSize, the same assumption naturalStripLength already makes.
    readonly property real stripLength: Logic.lineExtent(perLine, dotSize, dotSpacing, pillWidth)
    readonly property real crossThickness: Logic.lineExtent(lineCount, dotSize, dotSpacing, lineThickness)

    // Hover-background clearance. The HINT side reads the natural thickness (feeding an effective size into
    // a Layout hint would close the loop implicitHeight → availableCross → dotSize → implicitHeight); its
    // *Effective twin reads the rendered one, so the drawn clearance shrinks with the dots. Never subtracted
    // from availableMajor/availableCross and never fed to fitDotSize, so dot sizing is untouched by all this.
    readonly property real hoverPadding: Logic.hoverPadding(naturalLineThickness, hoverLengthFactor)
    readonly property real hoverCrossPadding: Logic.hoverPadding(naturalLineThickness, hoverThicknessFactor)
    readonly property real hoverCrossPaddingEffective: Logic.hoverPadding(lineThickness, hoverThicknessFactor)
    readonly property real paddedStripLength: naturalStripLength + 2 * hoverPadding
    readonly property real paddedCrossThickness: naturalCrossThickness + 2 * hoverCrossPadding
    // The background's CROSS extent: grown from the strip, then capped at the cell (see Logic.hoverCrossExtent —
    // insetting the cell instead collapses it back onto the strip). Render side only, so no loop.
    readonly property real hoverCrossExtent: Logic.hoverCrossExtent(availableCross, crossThickness, hoverCrossPaddingEffective)
}
