---
paths:
  - package/contents/ui/WorkspaceIndicator.qml
  - package/contents/ui/IndicatorMetrics.qml
  - package/contents/ui/WorkspaceDot.qml
  - tests/shared/IndicatorTestCase.qml
  - tests/integration/tst_indicator_*.qml
  - tests/unit/tst_indicatormetrics.qml
  - tests/unit/tst_workspacedot.qml
---

# The dot strip

**`WorkspaceIndicator` lays the strip out, `IndicatorMetrics` sizes it, and each `WorkspaceDot` is
one desktop.**

## Look

- **The current dot grows into the pill in place; never draw the pill as an overlay or make every
  slot pill-wide.** One `dotSpacing` sits between every pair: an overlay needs clearance on each
  side, and pill-wide slots spread the dots apart.
- **The advertised length is the formula, never the live extent**: a switch trades a growing
  element for a shrinking one, so the cell holds still while the pill moves.
- **A style without a pill feeds the metrics a pill factor of 1 and an auto pill size**, as the
  ring style does through `effPillWidthFactor` and `effPillSizeRequest`. The dots take the rendered
  `dotSize`, `pillSize` and `pillWidth` from the metrics, so no pill formula learns which style is
  on.

## Sizes

- **The `Layout.*` hints and the implicit size read only natural and floor sizes**, never a
  rendered one, which loops through the allocation back into `dotSize`. Everything drawn reads
  the effective sizes, which shrink to fit both axes and stop at `minDotSize`.
- **The pill's relation to the dots is `pillThicknessRatio` alone**, which lets `Logic.fitDotSize`
  and `Logic.lineExtent` serve both axes. `pillWidthFactor` is the pill's length over its own
  thickness, not the dot's.
- **A setting that changes the geometry is zeroed at the input while its feature is off**, as
  `effHoverLengthFactor` and `effHoverThicknessFactor` are, so `IndicatorMetrics` holds no feature
  flag.
- **The `strip` stays pinned to `stripLength` × `crossThickness`.** Sized by its content, it
  shrinks halfway through a switch between rows, and `anchors.centerIn` drags every dot.
- **The hover clearance feeds the hints but never the fit, and the minimum hint is the bare
  strip**, so a cramped panel squeezes out the clearance before the dots shrink.

## Layout

- **The row count is KWin's `desktopLayoutRows`, never a setting of ours.** Each row is its own
  single-line `Grid` inside an outer one; a single two-dimensional `Grid` widens the pill's whole
  column. The rows centre one by one, so their dots don't line up in columns.
- **Anything index-aligned with `desktopIds` is read at `globalIndex`**, `line * perLine + index`.
- **Geometry reads `gridVertical`, never the panel's `vertical`**: the metrics axes, the hints,
  the strip pin, both `Grid` flows, the hover background and `WorkspaceDot.vertical`. `singleLine`
  sets how many lines there are and `matchDesktopGrid` which way they run, and the two compose.
- **Every `Behavior` on a dot waits for the `animate` latch**, which the indicator sets once the
  current desktop first resolves, so a reload shows the pill already grown.

## Input

- **A dot reports only `activated()`, and the indicator decides what it means**, since only it
  knows this screen's current desktop: `activeClicked()` for the current dot,
  `switchRequested(uuid)` for any other. Scrolling emits only `switchRequested`.
- **Strip hover is `wheelArea.containsMouse` or a hovered dot's index**, since a dot takes the hover
  from the area beneath it and a parent `HoverHandler` never fires. `Logic.nextHoveredIndex` clears
  the index only when the dot leaving is the one recorded.
- **A `desktopIds` change rebuilds every dot**, and the new dot under a still pointer reports no
  hover until it moves. Keying the index by UUID doesn't help: the delegate is destroyed either way.
- **Tooltips and accessibility live on each dot**: its own `ToolTipArea`, and a checkable button
  named after the desktop whose press goes through `activated()`.
