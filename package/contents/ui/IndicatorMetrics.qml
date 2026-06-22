/*
 * Plasma Gnome Pager — IndicatorMetrics.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The dot-strip sizing engine, extracted from WorkspaceIndicator as one single-responsibility unit so
 * the indicator is just layout + wiring and this math is independently unit-testable
 * (tst_indicatormetrics). A non-visual QtObject: the indicator feeds it the raw config requests + grid
 * shape + live panel allocation, and reads back the effective sizes plus the natural/floor extents.
 *
 * NATURAL vs EFFECTIVE: naturalDotSize is the upper bound (the config/themed request); the effective
 * dotSize SHRINKS below it to fit a crowded panel on EITHER axis — the major line length OR the cross
 * thickness (scale-to-fit) — floored at minDotSize so the dots stay legible. The pill thickness scales
 * in lockstep (pillSize = dotSize * pillThicknessRatio), so an independently-sized pill keeps its
 * proportion under shrink. In the common case (room available) effective == natural, byte-for-byte.
 *
 * NO BINDING LOOP (keep this when editing): the natural/floor extents depend ONLY on the requests +
 * factors + perLine/lineCount — never on availableMajor/Cross or the effective dotSize. The indicator
 * binds its Layout hints to the natural/floor extents (geometry-independent) and its visual sizes to
 * dotSize/pillSize (geometry-dependent), so the panel allocation can never feed back into the hints.
 */
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

QtObject {
    id: metrics

    // ── Inputs (bound by WorkspaceIndicator) ──────────────────────────────────────────────────────
    property int dotSizeRequest: Logic.DEFAULTS.dotSize     // px override; 0 = auto (HiDPI themed)
    property int pillSizeRequest: Logic.DEFAULTS.pillSize   // px pill thickness; 0 = auto (match dots)
    property real spacingFactor: Logic.DEFAULTS.spacingFactor
    property real pillWidthFactor: Logic.DEFAULTS.pillWidthFactor  // pill length as a multiple of pill thickness
    property real availableMajor: 0   // live panel allocation along the line axis (0 before layout)
    property real availableCross: 0   // live panel allocation across the stacked lines
    property int perLine: 0           // desktops per line (KWin columns)
    property int lineCount: 0         // number of stacked lines (KWin rows)

    // ── Natural / floor (geometry-INDEPENDENT — drive the indicator's Layout hints; no loop) ───────
    readonly property real naturalDotSize: dotSizeRequest > 0 ? dotSizeRequest : Kirigami.Units.iconSizes.small / 2
    // Active-pill thickness, independent of the dots (0 = auto = match the dot). pillThicknessRatio is
    // the natural pill thickness in DOT units (1 when auto) — the one quantity carrying the decoupling
    // into the otherwise-unchanged fit/extent formulas (a capsule stays pillWidthFactor thicknesses long).
    readonly property real naturalPillSize: pillSizeRequest > 0 ? pillSizeRequest : naturalDotSize
    readonly property real pillThicknessRatio: naturalPillSize / naturalDotSize
    // Legibility floor: half the default dot, clamped <= natural so a tiny configured dot never scales UP.
    readonly property real minDotSize: Math.min(naturalDotSize, Kirigami.Units.iconSizes.small / 4)
    // Longest a line can be (one capsule + the rest of a full line's dots + uniform gaps) at the natural
    // and floor dot size — the major-axis preferred/min hints. The capsule length is the pill thickness
    // (sized independently of the dot) times its aspect ratio pillWidthFactor.
    readonly property real naturalStripLength: Logic.lineExtent(perLine, naturalDotSize, naturalDotSize * spacingFactor, naturalPillSize * pillWidthFactor)
    readonly property real floorStripLength: Logic.lineExtent(perLine, minDotSize, minDotSize * spacingFactor, minDotSize * pillThicknessRatio * pillWidthFactor)
    // Stack of lineCount lines (one dot each + gaps) at the natural and floor dot size — the cross-axis
    // preferred/min hints. The pill-bearing line is as thick as max(dot, pill).
    readonly property real naturalCrossThickness: Logic.lineExtent(lineCount, naturalDotSize, naturalDotSize * spacingFactor, Math.max(naturalDotSize, naturalPillSize))
    readonly property real floorCrossThickness: Logic.lineExtent(lineCount, minDotSize, minDotSize * spacingFactor, minDotSize * Math.max(1, pillThicknessRatio))

    // ── Effective (geometry-DEPENDENT — the rendered sizes; read by each WorkspaceDot) ─────────────
    // Dot size that fills the allocated MAJOR length (capsule length in dot units = ratio * widthFactor)
    // and the allocated CROSS thickness (the pill-bearing line is max(1, ratio) thick). fitDotSize is
    // +Infinity for an unconstrained axis, so min keeps the other; a dot must fit BOTH, so the binding
    // constraint is the smaller fit.
    readonly property real majorFitDotSize: Logic.fitDotSize(availableMajor, perLine, pillThicknessRatio * pillWidthFactor, spacingFactor)
    readonly property real crossFitDotSize: Logic.fitDotSize(availableCross, lineCount, Math.max(1, pillThicknessRatio), spacingFactor)
    readonly property real fitDotSize: Math.min(majorFitDotSize, crossFitDotSize)
    // Shrink-to-fit, capped at natural, floored at minDotSize (== naturalDotSize when there is room).
    readonly property real dotSize: Math.max(minDotSize, Math.min(naturalDotSize, fitDotSize))
    readonly property real pillSize: dotSize * pillThicknessRatio   // scales in lockstep with the dot
    readonly property real pillWidth: pillSize * pillWidthFactor    // active capsule LENGTH (major axis)
    readonly property real dotSpacing: dotSize * spacingFactor      // uniform gap between every element
}
