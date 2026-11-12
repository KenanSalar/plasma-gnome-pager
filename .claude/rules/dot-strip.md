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

`WorkspaceIndicator` lays the strip out, `IndicatorMetrics` sizes it, and each `WorkspaceDot` is
one desktop. What follows is the contract between the three.

## The look

- **Each dot is its desktop; the current one grows in place into the pill** and the line pushes
  its neighbours along. One `dotSpacing` sits between every pair, pill or dot. A pill sliding over
  the dots needs clearance on each side, which forces wide gaps, and slots as wide as the pill
  spread the dots apart; both looked less like GNOME.
- **A switch conserves the line's length**: one element shrinks by what the other grows, so the
  panel cell stays put during the morph.
- **The "Filled & ring" style has no pill**: the indicator feeds `IndicatorMetrics` and every dot a
  pill factor of 1 and a pill size of 0 (`effPillWidthFactor`, `effPillSizeRequest`), and the dot
  draws its ring through `Logic.dotHasRing` and `Logic.dotBodyIsHollow`. Every pill-style formula
  is untouched by it.

## Sizes

- **Natural sizes come from the settings alone, effective sizes from the allocation.** The
  `Layout.*` hints and the implicit size read only the natural and floor extents; feeding a
  rendered size into them closes the loop `implicitHeight → availableCross → dotSize`.
- **The dots shrink to fit both axes**, never past `minDotSize`, and the pill keeps its ratio to
  them: `pillThicknessRatio` carries the whole dot-to-pill relationship, so `Logic.fitDotSize` and
  `Logic.lineExtent` serve both axes with different factors. `pillWidthFactor` is the pill's length
  over its own thickness.
- **A feature that changes the geometry is neutralised at the input.** The ring style's pill
  factors and the hover background's clearance factors are zeroed or set to 1 in the indicator,
  so `IndicatorMetrics` takes plain numbers and holds no feature flag.
- **The `strip` is pinned to `stripLength` × `crossThickness`**, the extents of a line holding
  the pill. Sized by its content, a switch between two lines would shrink it mid-morph and its
  `anchors.centerIn` would drag every dot.
- **The hover background's clearance feeds the hints but never the fit**: the panel grants it
  when there's room, and a cramped panel squeezes it away before the dots shrink, since the
  minimum hint is the bare strip.

## Layout

- **Rows mirror KWin's `desktopLayoutRows`**, with no setting of our own. Each row is its own
  single-line `Grid` inside an outer `Grid`; a single two-dimensional `Grid` would widen the pill's
  whole column. `globalIndex = line * perLine + index` maps a dot back into the flat arrays.
- **Rows are centred one by one, so their dots don't line up in columns**, which is the price of
  every row keeping the reflow look.
- **`gridVertical` is the one orientation every piece of geometry reads**: the metrics axes, the
  hints, the strip pin, both `Grid` flows, the hover background and `WorkspaceDot.vertical`.
  The panel's own `vertical` only feeds it. `singleLine` sets how many lines there are and
  `matchDesktopGrid` which way they run; the two compose into four layouts.
- **The first placement is instant**: the `animate` latch reaches each dot once the current
  desktop first resolves, so a reload shows the pill already grown.

## Input

- **A dot only reports `activated()`**; the indicator decides what it means, because only the
  indicator knows this screen's current desktop. A click on the current dot raises
  `activeClicked()`, any other `switchRequested(uuid)`, and scrolling only ever the second.
- **The hover state is the `wheelArea` OR whichever dot reports a hover**: a dot's `MouseArea`
  takes hover from the area beneath it, and a parent `HoverHandler` never sees it.
  `Logic.nextHoveredIndex` clears the index only when the dot leaving is the one recorded.
- **Any `desktopIds` change rebuilds every dot**, and the new dot under a still pointer reports
  no hover, so the background goes dark until the pointer moves. Keying the index by UUID
  doesn't help: the delegate is destroyed either way.
- **Each dot carries its own `ToolTipArea` and its own accessibility**: a button named after the
  desktop, checked when current, pressed through the same `activated()` as a click.
