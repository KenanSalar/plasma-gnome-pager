# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **GNOME-style virtual-desktop pager** for KDE Plasma 6 panels — small dots with a sliding
"pill" over the current workspace. It is a **pure-QML KPackage plasmoid** (no compiled C++,
no build step): plasmashell interprets the QML directly. "Building" means installing or
symlinking the `package/` directory; there is no compiler. There **is** a headless QML
test harness (`make check` — see "Verifying a change"), split into **unit** and
**integration** tiers, though it covers only the Kirigami-only components, not `main.qml`.

The dot strip renders one dim circle per virtual desktop, reflects the current desktop live,
and switches on click; the active dot morphs into a wider highlight "pill" (the reflow model
below). Scroll/hover, per-dot tooltips (desktop name + an optional GNOME/stock-pager-style list of
the windows open on that desktop), add/remove/rename desktops, GNOME-style dynamic workspaces
(auto-maintain one empty trailing desktop; default off; one global behaviour across panels), an
independently-sized active pill, screen-reader accessibility, form-factor (vertical-panel) handling,
the settings UI, and robustness hardening (per-screen current desktop, scale-to-fit, transient-state
guards) are built. This file and
`.claude/rules/*` describe how the code is built, not the schedule or roadmap (that
history lives in git history and the GitHub Releases).

## The rules are the law — read them first

`.claude/rules/*.md` are this project's authoritative, highest-priority guidance and override
general habits. They are detailed and specific; do not re-derive or contradict them:

- **`robustness.md`** — read first. This widget exists *because* other GNOME pagers break on
  Plasma upgrades. The two non-negotiables: **public QML imports only (never
  `org.kde.plasma.private.*`)** and **pure QML (no C++ plugin)**. Every change is judged
  against "does this survive a Plasma/Qt/KF6 point upgrade?"
- **`plasmoid.md`** — applet structure, `PlasmoidItem` root, representations, config wiring,
  packaging/dev loop.
- **`virtual-desktops.md`** — the core domain: the read/write split (below) and exact KWin
  DBus call shapes.
- **`qml.md`**, **`kirigami.md`**, **`qml-performance.md`** — language conventions, units/theme
  (Plasma 6 moved these from `PlasmaCore` to `Kirigami`), and keeping the always-on panel
  widget cheap.

## Architecture (the parts that span files)

**Read/write split for virtual desktops** — this is the central design decision:
- **Read** live, reactive state with `TaskManager.VirtualDesktopInfo` (`desktopIds` (UUIDs),
  `currentDesktop`, `numberOfDesktops`, `desktopNames`). Bind to it; never cache — it updates
  when desktops change by *any* means (keyboard, another pager, settings).
- **Write** (switch/add/remove) via KWin DBus (`org.kde.plasma.workspace.dbus`), which is
  **async fire-and-forget**. You do not get a return value; you issue the call and let
  `VirtualDesktopInfo` report the new state. Desktops are keyed by **UUID strings**, not
  indices — map UI dot → desktop via `vdi.desktopIds[i]`.

**Per-screen current desktop (Plasma 6.7 "switch desktops independently for each screen").** The
desktop *set* (`desktopIds`/`desktopNames`/`numberOfDesktops`/`desktopLayoutRows`) is **global**;
only *which* desktop is "current" can differ **per output**. So each pager must reflect ITS
monitor's current — using `vdi.currentDesktop` (the global/active-output current) makes every
pager follow whichever monitor switched, the exact symptom this feature breaks. `WorkspaceIndicator`
therefore resolves its own current: it reads its panel's output name from the QtQuick `Screen.name`
attached property (KWin connector name, e.g. `DP-1`) and injects it into **`ScreenCurrentDesktop.qml`**
(a non-visual resolver extracted from the indicator), which calls
`vdi.currentDesktopByScreenName(screenName)` (public, in `org.kde.taskmanager`). The
perScreen-vs-global decision is the pure `Logic.resolveCurrentDesktop(perScreen, global)` —
**prefer the per-screen value, fall back to the global** — so it degrades to single-desktop
behaviour when the feature is off, the screen is unknown, or the API is absent (older Plasma; guarded
with `typeof … === "function"`). No config key: it auto-mirrors KWin (see "Mirror System Settings").
There is **no public per-output _write_** — `switchTo` still sets the one global `current`, which KWin
routes to the active output; interacting with a pager makes its output active, so click/scroll target
that monitor. (Read API verified live: `currentDesktopByScreenName("DP-6")` ≠ `("DP-5")` when the two
monitors are on different desktops.)

> **Gotcha — `currentDesktopByScreenName` is a METHOD with a SIGNAL, not a notifying property —
> so it needs an imperative recompute, not a plain binding.** `VirtualDesktopInfo` exposes the
> per-screen current as a method (`currentDesktopByScreenName(name)`) plus a
> `currentDesktopForScreenChanged(screenName)` signal (and the global `currentDesktopChanged`). A
> binding like `currentDesktop: vdi.currentDesktopByScreenName(screenName)` would evaluate **once**
> and never refresh — there is no property to depend on. So `ScreenCurrentDesktop.currentDesktop` (the
> extracted resolver) is a mutable source-of-truth property recomputed in `updateCurrentDesktop()`,
> driven by a `Connections { target: virtualDesktopInfo }` on those signals (plus `onScreenNameChanged` /
> `onVirtualDesktopInfoChanged` / `Component.onCompleted`); the indicator forwards it as its own
> `currentDesktop`, and `activeIndex` and each dot's `active` bind off it, staying declarative. The
> integration mock duck-types the same method+signal (the default models the feature OFF: per-screen ==
> global, so every pre-existing test stays valid); `tst_logic.qml` covers `resolveCurrentDesktop` and
> `tst_screencurrentdesktop.qml` covers the resolver's reactive recompute + the typeof degrade.

> **Gotcha — DBus typed-arg constructors are lowercase, and `variant` takes a _plain_ value.**
> The `org.kde.plasma.workspace.dbus` module exports `new DBus.string(s)`, `new DBus.int32(n)`,
> `new DBus.uint32(n)`, `new DBus.variant(v)`, etc. (verified from `dbusplugin.qmltypes`). Two
> traps:
> 1. There is **no** `DBus.QDBusVariant` type — it evaluates to `undefined` and throws
>    `TypeError: Type error` at call time (qmllint also flags it `unresolved-type`).
> 2. `new DBus.variant(...)` must wrap a **plain JS value**, not another DBus wrapper. Its
>    constructor takes a `QJSValue`, so `new DBus.variant(new DBus.string(uuid))` wraps a *gadget
>    object* and KWin silently rejects the type — the call is dropped with no error and nothing
>    switches. Pass the bare string: `new DBus.variant(uuid)`.
>
> Correct switch-to-desktop call (verified working end-to-end):
> `"arguments": [new DBus.string("org.kde.KWin.VirtualDesktopManager"), new DBus.string("current"), new DBus.variant(uuid)]`
> on `iface: "org.freedesktop.DBus.Properties", member: "Set"`. Validate a DBus shape
> independently with
> `busctl --user call org.kde.KWin /VirtualDesktopManager org.freedesktop.DBus.Properties Set ssv "org.kde.KWin.VirtualDesktopManager" "current" s "<uuid>"`.

**Representation model** — a panel pager renders inline, so the dot strip is the applet's
**full** representation, forced to always show inline: `main.qml` sets
`preferredRepresentation: fullRepresentation` and `fullRepresentation: WorkspaceIndicator {}`.
`main.qml` (root `PlasmoidItem`) owns the data sources, DBus helpers, and contextual actions;
`WorkspaceIndicator.qml` lays out the dot strip — a row or column per `Plasmoid.formFactor` (passed
down as a plain `vertical` bool), and a multi-row grid mirroring KWin's `desktopLayoutRows` — and is
layout + scroll + wiring only: it delegates the size math to **`IndicatorMetrics.qml`** (the sizing
engine) and the per-screen current to **`ScreenCurrentDesktop.qml`**, both non-visual units extracted
from it and each independently unit-tested. `WorkspaceDot.qml` is one element (a dot that morphs into
the highlighted capsule when active — see the Visual model below).

> **Gotcha (learned the hard way) — advertise width via `Layout.*`, not `implicitWidth` alone.**
> An inline full-representation that sets *only* `implicitWidth`/`implicitHeight` gets a **default
> square cell** (≈ panel thickness) from the panel: the centred dot `Row` then overflows its tiny
> cell and draws **on top of the neighbouring widgets**, and only that small cell is interactive
> (the dots outside it are dead to clicks/scroll/right-click). Fix: the representation root
> (`WorkspaceIndicator`) advertises its content extent via `Layout.minimum`/`preferred`/`maximum`
> on **both** axes (needs `import QtQuick.Layouts`). The MAJOR (line) axis — width on a horizontal
> panel, height on a vertical one (`vertical`) — pins `preferred == max == naturalStripLength` but
> drops `min` to a smaller `floorStripLength` so the panel can **compress** the strip; when it does,
> the dots scale down to fill the allocation (scale-to-fit — see the scale-to-fit gotcha below).
> The CROSS axis carries the line(s) (`min == preferred == naturalCrossThickness`) with its
> **maximum reset to `-1`** (Qt's unconstrained `+∞`) so the panel stretches it to the panel
> thickness and the centred grid sits in the middle. Asserted by
> `tst_indicator_layout.qml::{test_advertisesWidthViaLayout,test_verticalAdvertisesHeightViaLayout}`.
> Do **not** wrap the representation root in another item (e.g. a `ToolTipArea`) that doesn't
> forward these `Layout` hints — that reintroduces the square cell.

**Visual model — REFLOW: each element morphs dot⇄capsule (no overlay).** Each `WorkspaceDot`
*is* a workspace and renders as a dim circle (`Kirigami.Theme.textColor` @ `inactiveOpacity`,
`dotSize` across) when inactive, and morphs into a longer highlighted **capsule** (the "pill":
`Kirigami.Theme.highlightColor` @ full opacity, `pillWidth` along the major axis, `pillSize` across)
when `active`. **The pill is sized independently of the dots** (see the independent-pill gotcha
below): its cross-axis *thickness* is the effective `pillSize` (config key `pillSize`, `0 = auto =
match the dots`) and its *length* is `pillSize * pillWidthFactor`, so a thick pill can sit over tiny
dots (or vice versa). By default `pillSize` tracks `dotSize`, recovering the original look exactly.
There is **no** separate overlay. Switching morphs two elements at once (old capsule → dot, new dot
→ capsule) and the line reflows between them. **Form factor:** the major axis is horizontal on
a horizontal panel and vertical on a vertical one (`vertical`, from `Plasmoid.formFactor`); the dot
morphs `width` or `height` accordingly (`radius` is `min(width,height)/2` — half the shorter, cross
axis — so the ends keep stadium-round in both orientations and at any pill thickness).
When KWin's grid has more than one row, the strip is several such reflow lines stacked along the
cross axis (mirroring `VirtualDesktopInfo.desktopLayoutRows`) — see the multi-row gotcha below.
Hover brighten is a *separate* inactive-only state driven by
`containsMouse`; the dot BODY's opacity is resolved by
`logic.js::dotOpacity(active, hovered, occupied, style, inactiveOpacity, hoverOpacity, occupiedOpacity)`
(`1.0` active → `hoverOpacity` → `occupiedOpacity` only in the **Filled** occupancy style → else
`inactiveOpacity`) and its colour by `logic.js::dotColor(active, occupied, style, activeC, inactiveC,
occupiedC)` (active colour → the occupied colour in the **Filled** style → else inactive). The
**occupied-dot indicator** (config `showOccupancy`, default OFF) marks desktops that hold windows,
reusing the same shared `WindowAggregator` snapshot the dynamic-workspaces controller consumes (no new
data source/DBus), index-aligned with `desktopIds` and gated on `showOccupancy` in the indicator so a
stale array is harmless when off. It is fed the **PER-SCREEN** occupancy array (`screenOccupancy` —
only windows physically on THIS pager's monitor), NOT the global `desktopOccupancy` the controller
gets (see the per-screen occupancy gotcha below). `occupancyStyle` (`Logic.OCCUPANCY`: **Filled** / **InnerDot** / **Ring**,
mirrors the `main.xml` index + the `ConfigAppearance` combo) picks HOW: **Filled** recolours the dot
body to the occupied colour at `occupiedOpacity`; **InnerDot** and **Ring** keep the normal dim dot and
draw an OVERLAY on top (a centred dot / a hollow rim ring) at `occupiedOpacity` via
`logic.js::{innerDotVisible,ringOverlayVisible}` — both `WorkspaceDot` sibling Rectangles centred on the
capsule with independent opacity. The marker colour is `occupiedColor` (its own config key; the theme
accent when `followThemeColors`), so all three styles share one colour + the one `occupiedOpacity`
slider. This replaced an earlier *sliding overlay pill* — which could not
give GNOME's uniform spacing (a wide overlay needs clearance, forcing wide dot gaps) — and matches
how GNOME and the KDE `compact_pager` actually work.

> **Filled & ring style (`dotStyle`, `Logic.DOT_STYLE`) — a SECOND top-level look: no pill, the body
> ITSELF becomes a hollow ring (distinct axis from `occupancyStyle`).** `dotStyle` (config key, combo
> "Pager style:") selects the OVERALL look: `0 = Pill` (the REFLOW model above, default) or `1 = Ring`
> ("Filled & ring" — the dhruv8sh "Desktop Indicator" look: every dot the same size, current = a solid
> filled circle, non-current = a HOLLOW RING — transparent fill + border). Two mechanical effects, both
> isolated so the Pill look (and every prior test) is **byte-for-byte unchanged** when `dotStyle == Pill`:
> (1) **No pill (uniform sizing)** — the active element must not widen. The indicator NEUTRALIZES the pill
> params in ring mode (`effPillWidthFactor = 1`, `effPillSizeRequest = 0`) and feeds those to BOTH
> `IndicatorMetrics` and each `WorkspaceDot`, so `pillThicknessRatio → 1` and the active extent collapses
> to `dotSize`. **`IndicatorMetrics` is UNTOUCHED** — it just receives uniform inputs (so its unit tests
> stay valid). (2) **Ring body — OUTLINE decoupled from INTERIOR.** Two independent pure predicates drive
> `WorkspaceDot`'s capsule Rectangle: `Logic.dotHasRing(dotStyle, active)` (`Ring && !active`) draws the
> ring **outline** (`border.width = Logic.ringThickness(dotSize)` = `max(1, round(dotSize*0.18))`, shared
> with the Ring-occupancy overlay's rim; `border.color = resolvedInactive`) for
> EVERY non-current dot; `Logic.dotBodyIsHollow(dotStyle, active, occupied, occupancyStyle)` makes the
> **interior** `color: "transparent"` unless the `Filled` occupancy marker fills it, and
> `Logic.dotBodyFilled(...)` (`dotHasRing && !dotBodyIsHollow`) names the third state (ring outline + filled
> interior). The whole body is
> drawn at **full opacity** in this style (`opacity: ringStyle ? 1.0 : dotOpacity(...)`) — crisp solid
> rings (the user's ask) — so the occupied **fill carries its own alpha**, baked in via
> `Qt.rgba(resolvedOccupied.r/g/b, occupiedOpacity)`, leaving the outline opaque. **Occupancy COMPOSES**
> (per the user's note "reuse the ones we have except the hollow ring"): a `Filled`-occupied dot is the
> ring outline PLUS a filled interior ("ring and dot background" — the outline must NOT vanish, that was a
> bug); `InnerDot` keeps the hollow ring + its centre dot; the `Ring` OCCUPANCY overlay is SUPPRESSED
> (`ringOverlayVisible` gained a `dotStyle` arg) because the body is already a ring. `dotColor`/`dotOpacity`/
> `innerDotVisible` are reused **unchanged**. The single `dotStyle === Ring` comparison lives in one
> predicate `Logic.isRingStyle(dotStyle)` (used by `dotHasRing`/`dotBodyIsHollow`/`ringOverlayVisible` and the
> two QML `ringStyle` properties). **Config robustness:** the `ConfigAppearance` "Indicator style"
> combo DISABLES the "Hollow ring" item via a custom delegate when Filled & ring is selected, and the
> "Pager style" combo's `onActivated` **migrates** a previously-chosen Hollow ring occupancy → Filled on
> switch (needs `pragma ComponentBehavior: Bound` for the delegate's outer-id refs; both the disable and
> the migration key off one `root.ringStyle` bool, and the pill sliders off `root.pillStyle`). The two
> pill-only sliders (Pill thickness/length) are `enabled:`-off under this style. Guarded by
> `tst_logic.qml::{test_dotStyleConstants,test_isRingStyle,test_ringThickness,test_dotHasRing,test_dotBodyIsHollow,test_dotBodyFilled,test_ringOverlayVisible}` +
> `tst_workspacedot.qml::{test_filledRingStyleInactiveIsHollow,test_filledRingStyleOccupancyComposition}` +
> `tst_indicator_layout.qml::test_filledRingStyleNoPill`. The config disable/migration is e2e-only (config
> pages aren't headless-tested). More styles are planned — `DOT_STYLE` is the extension point.

> **Uniform spacing + reflow — don't reintroduce the overlay or a coupled slot.**
> One uniform `spacing` (`dotSpacing = dotSize * spacingFactor`, default `spacingFactor 0.5`)
> sits between **every** adjacent element, so the pill-to-dot gap equals the dot-to-dot gap (the
> GNOME look). The active element simply grows **in place**; its neighbours are pushed out by the
> line and can never be covered or clipped — so there is **no** `pillOverhang`/`pillEndGap`/`pillX`
> math. This is **not** the previously-rejected *uniform-slot* model (every slot as wide as the
> pill, which spread the dots far apart): here inactive dots stay `dotSize`-tight and only the
> active one is longer. Size is advertised by a **formula** on the major axis (at the natural dot
> size) — `naturalStripLength = perLine > 0 ? pillWidth + (perLine-1)*(dotSize+dotSpacing) : dotSize`
> (with `pillWidth = naturalPillSize * pillWidthFactor`) — and the cross axis carries the lines
> (`naturalCrossThickness = lineCount*max(dotSize,pillSize) + (lineCount-1)*dotSpacing`),
> not the live positioner extent, so the panel cell stays put during the morph and when no element
> is active (a switch **conserves total length**: the shrinking and growing elements cancel). For a
> single line `perLine == desktopCount` and `lineCount == 1`, recovering the 1-D width formula.
> Guarded by `tst_indicator_morph.qml::{test_uniformSpacing,test_exactlyOneCapsule,
> test_transientStaleNoCapsuleWidthStable}` + `tst_indicator_layout.qml::test_gridSizingTwoRows`. The metric property names
> (`dotSize`, `pillSize`, `pillWidthFactor`, `spacingFactor`, `inactiveOpacity`, `hoverOpacity`) match
> the `main.xml` settings keys exactly (see "Config flow" below).
>
> **Scale-to-fit (major axis, with the cross axis added later) — shrink the dots to the allocation on BOTH axes,
> never overflow; NATURAL vs EFFECTIVE size.** When the natural strip would exceed the panel-allocated
> length on **either** axis (many desktops on a crowded panel; a multi-row grid on a thin panel), the
> dots/pill **shrink** to fill the allocation instead of drawing over the neighbours or past the panel
> thickness (robustness.md). `naturalDotSize` is the upper bound (the config/themed request); the rendered
> `dotSize = max(minDotSize, min(naturalDotSize, fitDotSize))` — capped at natural, floored at
> `minDotSize` (a legibility floor, `min(naturalDotSize, iconSizes.small/4)`, clamped ≤ natural so a
> tiny configured dot never scales UP). **`fitDotSize = min(majorFitDotSize, crossFitDotSize)`**: a dot
> must fit BOTH axes, so the binding constraint is the smaller fit. Both reuse the one pure
> `Logic.fitDotSize(available, count, pillFactor, spacingFactor)`, the algebraic **inverse of
> `lineExtent`** — the dot size that makes a full line exactly fill `available`: the MAJOR fit reads the
> live major length with `perLine` and `pillThicknessRatio * pillWidthFactor` (the capsule length in
> dot units; `== pillWidthFactor` when the pill tracks the dots); the CROSS fit reads the live cross
> thickness with `lineCount` and **`max(1, pillThicknessRatio)`** (the pill-bearing line is the thicker
> of dot/pill; `== 1`, recovering the exact inverse of `naturalCrossThickness`, when the pill is no
> thicker than a dot). It returns `+Infinity` when
> there's nothing to fit (non-positive `available`/`count`/denominator), so the unconstrained axis keeps
> natural and `min` picks the other. The crucial constraint: **the `Layout.*` hints are computed from
> the NATURAL/floor sizes only** (`naturalStripLength`/`floorStripLength`/`naturalCrossThickness`/
> `floorCrossThickness`), never the effective `dotSize` — the fits read the live `width`/`height`, so
> feeding the effective size back into the hints would be a binding loop. The cross-axis `Layout`
> **minimum drops to `floorCrossThickness`** (mirroring the major axis's `floorStripLength`) so a thin
> panel can compress the thickness; preferred stays `naturalCrossThickness`, maximum stays `-1` (free to
> fill the thickness). Everything *downstream* (`pillSize`, `pillWidth`, `dotSpacing`, each
> `WorkspaceDot`, the `Grid` spacing) reads the effective `dotSize` — the effective `pillSize = dotSize *
> pillThicknessRatio`, so dots AND an independently-sized pill scale in lockstep (the configured
> dot:pill proportion is preserved under shrink). Common case (room
> available on both axes): `fitDotSize >= naturalDotSize`, so effective == natural and the look is
> byte-for-byte unchanged. **All of this size math lives in the non-visual `IndicatorMetrics.qml`** —
> the indicator feeds it the requests + grid shape + live `availableMajor`/`availableCross` geometry and
> forwards its outputs unchanged — so it is now **directly** unit-tested (`tst_indicatormetrics.qml`) as
> well as through the indicator. Guarded by `tst_indicatormetrics.qml` +
> `tst_indicator_layout.qml::{test_scaleDotsShrinkOnNarrowWidth,
> test_scaleDotsUnchangedWhenAmple,test_scaleDotsShrinkOnShortHeightVertical,
> test_scaleDotsShrinkOnThinCrossMultiRow,test_scaleDotsCrossUnchangedWhenAmpleThickness,
> test_scaleDotsShrinkOnThinCrossVertical,test_advertisesWidthViaLayout,
> test_verticalAdvertisesHeightViaLayout,test_gridSizingTwoRows}` +
> `tst_logic.qml::{test_fitDotSize,test_fitDotSizeUnbounded}`.
>
> **Independent pill thickness — `pillSize` is decoupled from `dotSize` via ONE ratio; reuse the fit
> math, don't fork it.** The pill's cross-axis *thickness* is its own config key `pillSize` (`Int`, `0
> = auto = match the dots`); the dots keep `dotSize`. The decoupling is carried entirely by **one**
> derived quantity in `IndicatorMetrics`: `pillThicknessRatio = naturalPillSize / naturalDotSize`
> (`1` when auto, because `naturalPillSize` falls back to `naturalDotSize`). With it, the existing pure
> `Logic.fitDotSize`/`Logic.lineExtent` are reused **unchanged** — only their *factor arguments*
> change: the capsule length in dot units becomes `pillThicknessRatio * pillWidthFactor` (major fit /
> `naturalStripLength` `activeExtent = naturalPillSize * pillWidthFactor`) and the cross "pill factor"
> becomes `max(1, pillThicknessRatio)` (cross fit / `naturalCrossThickness` `activeExtent =
> max(naturalDotSize, naturalPillSize)`). The effective thickness `pillSize = dotSize *
> pillThicknessRatio` and `pillWidth = pillSize * pillWidthFactor`. `WorkspaceDot` takes `pillSize` as
> an input and its capsule cross axis is `active ? pillSize : dotSize` (radius `min(width,height)/2`).
> Because the line is then as thick as its tallest element (the capsule when `pillSize > dotSize`), the
> inner per-line `Grid` MUST centre elements on the **cross axis** (`verticalItemAlignment:
> Grid.AlignVCenter` horizontal / `horizontalItemAlignment: Grid.AlignHCenter` vertical) — otherwise the
> positioner top/left-aligns the smaller inactive dots against the taller pill (guarded by
> `test_inactiveDotCentredAgainstThickPill{Horizontal,Vertical}`). The effective `pillSize = dotSize *
> ratio` also floors in lockstep: at an extreme-narrow panel `dotSize` clamps at `minDotSize` and the
> pill at `minDotSize * ratio`, neither shrinking further (`test_pillFloorAtExtremeNarrow`).
> **`pillWidthFactor` is now relative to the PILL thickness, not the dot** (config label "× pill"),
> i.e. the pill's aspect ratio. When `ratio == 1` (the default, or any dot-size-only change) every
> formula collapses to the pre-existing one, so the look — and every prior test — is byte-for-byte
> unchanged. Guarded by `tst_indicator_layout.qml::{test_autoPillTracksDotSize,
> test_independentThickerPill,test_pillThicknessAdvertisedOnCrossAxis,test_pillScalesWithFitShrink}` +
> `tst_workspacedot.qml::test_independentPillThickness` + `tst_logic.qml` defaults (the `pillSize` key).
>
> **Multi-row grid — mirror KWin, don't add a setting; nested positioners, not a 2-D Grid.**
> KWin's `desktopLayoutRows` (read live off `VirtualDesktopInfo`, null-guarded, ≥1) splits the
> desktops into that many **lines** via `Logic.gridColumns(count, rows)` (= `ceil(count/rows)`,
> the per-line count) + `Logic.chunk(ids, perLine)`. Each line is an **independent single-line
> reflow strip** (tight dots + the in-place pill), so a grid is just `lineCount` lines stacked on
> the cross axis — every row keeps the exact dots+pill look. This is **two nested `Grid`
> positioners** (outer = lines along the cross axis, inner = dots along the major axis; each fixes
> only its line dimension to `1` and leaves the other `-1`/auto), **not** one 2-D `Grid` — a single
> `Grid` would size each column to its widest cell, so the active capsule would fatten its **whole
> column** across all rows. The trade-off: lines are **centred independently** (a short/last line is
> narrower than the line holding the pill), i.e. **not column-aligned** — that's the deliberate cost
> of keeping each row's exact look. We **mirror** KWin's grid (System Settings → Virtual Desktops →
> "Rows") rather than add a widget setting, so it updates reactively and never disagrees with KWin.
> The dot's flat-list position is `globalIndex = line*perLine + indexInLine` (for `desktopNames`).
> Guarded by `test_grid*` (mirrors-rows, uneven-last-line, reactive-to-rows, second-line capsule,
> vertical transpose) + `tst_logic.qml::{test_gridColumns,test_chunk}`.

> **Grid ORIENTATION toggle (`matchDesktopGrid`) — a presentation choice, distinct from the grid SHAPE
> (still mirrored, no setting).** On a vertical panel the strip is normally *transposed* (lines along the
> cross/horizontal axis, dots along the major/vertical axis) so a single-row strip flows nicely DOWN the
> panel — but that same transpose stacks a multi-row grid (e.g. KWin Rows=2 over 2 vertically-stacked
> desktops) **side-by-side**, which surprised an issue reporter who wanted it to match their vertical
> desktop layout (issue #23). The row COUNT is still mirrored from KWin (`desktopLayoutRows` — no widget
> knob, see above); only the on-screen ORIENTATION is ours to choose, and there is **no** KWin setting to
> mirror for it — so `matchDesktopGrid` (Bool, default OFF, `ConfigAppearance` "Vertical panels:") is an
> appropriate widget toggle (NOT a duplicate of a System Settings knob). The whole feature is **one derived
> bool** in `WorkspaceIndicator`: `readonly property bool gridVertical: vertical && !matchDesktopGrid`,
> substituted for the raw panel `vertical` at the SIX geometry sites — `availableMajor`/`availableCross`,
> the `Layout.*` size hints, the `strip` size pin (`strip.width`/`height`, see the strip-pin gotcha below),
> the outer `strip` Grid flow, the inner `lineStrip` Grid flow + item alignment,
> and `WorkspaceDot.vertical` (the capsule's elongation axis). Truth table: horizontal panel → always
> `false` (toggle inert); vertical + OFF → `true` (transpose preserved, byte-for-byte, every prior test
> green); vertical + ON → `false` (the grid renders in KWin orientation — rows top-to-bottom, columns
> left-to-right — exactly like a horizontal panel, matching the stock pager). Applies to **all row counts**
> (a single-row strip on a vertical panel also renders horizontally when ON — chosen for literal grid
> fidelity; scale-to-fit shrinks it to the panel thickness, never overflows). `IndicatorMetrics` is
> **untouched** (orientation-agnostic — it only sees `availableMajor`/`availableCross`). Guarded by
> `tst_indicator_layout.qml::{test_gridVerticalResolution,test_matchDesktopGridFaithfulMultiRow,
> test_matchDesktopGridReporterCase,test_matchDesktopGridIgnoredHorizontal}`; the existing
> `test_gridVerticalTranspose` pins the default-OFF transpose. The config page is e2e-only.

> **Single-line layout (`singleLine`) — collapse the grid into ONE line; ORTHOGONAL to `matchDesktopGrid` (count
> vs direction), so they COMPOSE into four layouts.** `singleLine` (Bool, default off, `ConfigAppearance`
> "Multiple rows: Show all desktops in a single line") **ignores KWin's rows** and lays every desktop out in a
> single line, regardless of `desktopLayoutRows`. Mechanically it is ONE line: `desktopRows = singleLine ? 1 :
> <KWin rows>`, so `perLine = desktopCount`, `lineCount = 1` — no new geometry. Crucially it does NOT touch
> `gridVertical`: `singleLine` sets the line COUNT, `matchDesktopGrid` sets the DIRECTION (`gridVertical = vertical
> && !matchDesktopGrid`, unchanged), so the two are **independent** and their 2×2 gives four vertical-panel
> layouts: neither = transposed grid; `matchDesktopGrid` = KWin grid (rows down, columns across); `singleLine` =
> one VERTICAL strip with a vertical pill (what the issue #23 reporter wanted — they keep KWin Rows>1 for their
> overview but want a clean vertical strip, so they can't just set Rows=1); `singleLine` + `matchDesktopGrid` =
> one HORIZONTAL row with a horizontal pill (a later #23 ask — a flat row across a vertical panel). So the
> `ConfigAppearance` "Match…" checkbox is NOT greyed under `singleLine` — it composes. Everything downstream
> (strip-pinning, scale-to-fit, morph) is parameterized by `perLine`/`lineCount`/`gridVertical`, so all four just
> work. Guarded by `tst_indicator_layout.qml::{test_singleLineCollapsesGridToOneLine,
> test_singleLineVerticalStripHasVerticalPill,test_singleLineHorizontalRowOnVerticalPanel}` + the `singleLine` rows
> in `test_gridVerticalResolution` + `tst_logic.qml` defaults. The config page is e2e-only.

> **Gotcha — PIN the `strip` Grid to the conserved extent, never leave it content-sized (multi-row morph
> "breathing").** The outer `strip` Grid is `anchors.centerIn: parent`. If it sizes to its CONTENT (its
> implicit size), a multi-row morph makes the dots drift: during a switch the de-activating capsule animates
> `pillWidth → dotSize` in one line while the activating one animates `dotSize → pillWidth` in ANOTHER line, so
> with `Δ = pillWidth − dotSize` and progress `f` the content width is `L + Δ·max(1−f, f)` — it **dips by Δ/2
> at f=0.5** and the centred strip re-centres every frame, dragging all dots ("breathing"). A SINGLE-LINE (or
> same-row) switch keeps both morphing dots in one line, so the length is conserved (`L + Δ`, constant) → no
> drift — which is why only multi-row CROSS-line switches show it. Fix: pin `strip.width`/`strip.height` to the
> **effective conserved extents** `IndicatorMetrics.{stripLength,crossThickness}` (= `Logic.lineExtent(perLine,
> dotSize, dotSpacing, pillWidth)` / `lineExtent(lineCount, …, max(dotSize,pillSize))` — the length of a
> capsule-bearing line, the MAX, independent of `f`), swapped by `gridVertical` like the `implicitWidth/Height`
> hints. These are the **effective** (post-scale-to-fit) analogs of `naturalStripLength`/`naturalCrossThickness`
> and must stay EFFECTIVE (natural would overflow under compression); they feed ONLY the strip, never the
> `Layout.*` hints (those stay natural — the binding-loop gotcha). No loop: `strip` is a child, its size never
> feeds back into `indicator.width`. Trade-off: a multi-row grid whose current desktop is in a SHORT trailing
> line renders ~Δ/2 left of centre at rest (the footprint is now constant instead of re-centring per switch —
> which also removes a pre-existing rest jump); common layouts (single row, even grids, current in a full line)
> are unchanged. Assumes `pillWidth ≥ dotSize` (same as `naturalStripLength`). Guarded by
> `tst_indicatormetrics.qml::{test_stripLengthMatchesFormula,test_crossThicknessMatchesFormula,
> test_stripLengthTracksEffectiveUnderShrink}` + `tst_indicator_layout.qml::test_multiRowStripPinnedRegardlessOfCapsule`
> (deterministic proxy) + `tst_indicator_morph.qml::test_crossRowMorphDoesNotDriftOtherDots` (samples mid-morph).

> **Gotcha — animate the first *placement*, not the first frame.** The morph is gated by an
> `animate` latch flipped via `Qt.callLater` once `activeIndex` is first valid, so the active
> element is **already a capsule** on shell reload (no grow-in from a dot, even when
> `VirtualDesktopInfo` populates — or `currentDesktop` resolves — a frame late) and only later
> switches morph. The latch is passed down to each `WorkspaceDot` and gates its `Behavior on
> width/color/opacity`; the Behaviors are also guarded against `Kirigami.Units.longDuration === 0`
> (reduce-animations) so the morph becomes instant.

> **Gotcha (learned the hard way) — a `fullRepresentation` is mandatory.** A Plasma 6
> applet that defines **only** a `compactRepresentation` (no `fullRepresentation`) instantiates
> **no representation at all**: `compactRepresentationItem`/`fullRepresentationItem` stay `null`,
> nothing renders, `expanded` is stuck `true`, and there is **no error** in the journal — the
> widget just silently shows nothing. The moment a `fullRepresentation` exists, the compact one
> instantiates too. The working idiom for a standalone inline widget: make the content the
> `fullRepresentation` and set `preferredRepresentation: fullRepresentation` so it always shows
> inline (never a popup, never the default compact icon). Confirmed against
> develop.kde.org/docs/plasma/widget ("display widget directly in panel").

**Interactions — scroll, hover, tooltips, add/remove/rename.** The branching logic (clamp/wrap, hi-res
wheel accumulation, never-remove-last, dot/capsule opacity, name validation) lives in
`package/contents/ui/logic.js` (pure `.pragma library`, unit-tested by `tests/unit/tst_logic.qml`
with no Plasma deps); the QML is a thin caller. Config flags flow one way: `main.qml` reads
`plasmoid.configuration.*` → passes plain booleans to `WorkspaceIndicator` → each `WorkspaceDot`, so
the tested sub-components never touch `plasmoid.configuration`. `main.qml` owns add/remove/rename (KWin
DBus `createDesktop`/`removeDesktop`/`setDesktopName` + `Plasmoid.contextualActions`, gated by
`enableAddRemove` / `enableRename`, never removing the last desktop via `logic.js::canRemoveDesktop`).

> **Gotcha — "Configure Virtual Desktops…" is a GUI launch, NOT a DBus/`logic.js` spec.** A fourth,
> **always-shown** (no config key — matches the stock pager) `Plasmoid.contextualAction` opens the
> SYSTEM virtual-desktops KCM via the public KF6 `org.kde.kcmutils` `KCM.KCMLauncher.openSystemSettings(name)`
> — what the stock `org.kde.plasma.pager` does. The module name is platform-branched in `main.qml`'s
> `openVirtualDesktopsKcm()` (`Qt.platform.pluginName.includes("wayland") ? "kcm_kwin_virtualdesktops" :
> "kcm_kwin_virtualdesktops_x11"`). Because it's an imperative GUI launch (not a
> `{service,path,iface,member,args}` DBus write), it stays a direct `main.qml` function — it does NOT
> go through `dispatch`/`logic.js` (which is DBus-spec-only) and adds no test. This is **distinct from**
> the "Configure Workspaces…" entry Plasma auto-adds, which opens THIS widget's own settings. The
> `org.kde.kcmutils` import is added to robustness.md's allowlist — public KF6, a hard Plasma dependency
> (effectively always present, like the Breeze-icon fallback), so importing it into the always-on
> `main.qml` is safe. e2e-only (verify in-shell).

> **Gotcha — KWin DBus call SHAPES live in pure `logic.js`, so they are unit-tested (not e2e-only).**
> Each write's exact `{ service, path, iface, member, args:[{t,v}] }` is built by a pure
> `logic.js::{switchSpec, addSpec, removeSpec, renameSpec}` (with the robustness guards folded IN, so
> they're tested too: a transient-empty uuid, never-remove-last via `canRemoveDesktop`, and a blank
> rename via `sanitizeDesktopName` each return **`null` = no-op**; `removeLastDesktop` resolves the
> target via `lastDesktopId` first). `main.qml` is then a thin `dispatch(spec)`: it maps each arg
> `{t,v}` to the order-sensitive `DBus.*` constructor in `toDBusArg` — `t` mirrors a DBus signature
> letter (`"s"` string, `"u"` uint32, `"i"` int32, `"v"` variant), and the `"v"` case is the LONE
> place that `new DBus.variant(v)`-wraps a plain value (the silent-fail gotcha below). The shapes — the
> exact strings/types KWin drops silently when wrong, and the most upgrade-fragile thing in the widget
> — are pinned by `tst_logic.qml::{test_switchSpec, test_addSpec, test_removeSpec, test_renameSpec}`;
> only the trivial 4-case `toDBusArg` map needs the real DBus plugin and stays the in-shell smoke test.

> **Gotcha — pill-click action: a SEPARATE `activeClicked()` signal + kglobalaccel `invokeShortcut`, not
> a switch.** Clicking the ALREADY-CURRENT desktop's pill runs the configurable `pillClickAction` (default
> `None`); clicking any OTHER dot still switches, and SCROLL is unaffected. The split is by SIGNAL, not a
> `main.qml` branch, because the active-vs-inactive test needs the PER-SCREEN current desktop, which only
> exists in the indicator (`WorkspaceIndicator.currentDesktop`, from `ScreenCurrentDesktop`) — `main.qml`
> has only the global `vdi.currentDesktop`. So `WorkspaceDot` is UNTOUCHED (still emits `activated()`); the
> indicator's delegate branches on the dot's own `active` — `onActivated: workspaceDot.active ?
> indicator.activeClicked() : indicator.switchRequested(modelData)` — and `handleWheel` only ever emits
> `switchRequested`, so scroll can NEVER reach the pill action (true by construction, incl. the 1-desktop +
> wrap no-op). `main.qml` maps the new signal to `dispatch(Logic.pillClickSpec(pillClickAction))`. The
> DBus SHAPES stay pure/tested like the others: `Logic.pillClickSpec(action)` → `invokeShortcutSpec(name)`
> on the PUBLIC `org.kde.kglobalaccel` `/component/kwin` `invokeShortcut(s)` — `None`/unknown → `null`
> (no-op), else TOGGLE the KWin shortcut by its **unique name** (`"Show Desktop"`/`"Overview"`/`"Grid
> View"` — DBus identifiers, so NEVER i18n-wrapped; note "Grid" → `"Grid View"`). kglobalaccel is chosen
> over the direct effect DBus (`/org/kde/KWin/Effect/Overview/<ver>`) precisely because that path carries a
> version suffix that breaks across KWin upgrades (robustness.md); no new import (reuses `DBus`). Guarded
> by `tst_logic.qml::{test_pillClickConstants,test_pillClickSpec,test_invokeShortcutSpec}` +
> `tst_indicator_input.qml::{test_clickActiveDotEmitsActiveClicked,test_clickInactiveDotEmitsSwitchRequested,
> test_scrollNeverEmitsActiveClicked}` + `tst_indicator_morph.qml::test_clickActiveCapsuleEmitsActiveClicked`
> (the real-mouseClick e2e variant). The live shortcut invocation has side-effects, so it stays e2e-only.

> **Rename — a public `setDesktopName(id, name)` DBus write + a `PlasmaCore.Dialog`, NOT
> `Kirigami.PromptDialog`.** "Rename Current Desktop…" is a `Plasmoid.contextualAction` (gated by the
> `enableRename` key) that renames `vdi.currentDesktop` via `root.dispatch(Logic.renameSpec(uuid, name))`
> — the pure builder emits the verified `setDesktopName(ss)` shape on `org.kde.KWin.VirtualDesktopManager`,
> which `dispatch`/`toDBusArg` turn into the DBus call (see the call-SHAPES gotcha above). It is
> menu-only / current-desktop (no per-dot trigger), so `WorkspaceIndicator`/`WorkspaceDot` are untouched.
> The new name comes back through the live `desktopNames` binding — **no cache** (the read/write split).
> The name is validated by pure `logic.js::sanitizeDesktopName` (trim, reject empty/whitespace → `""`
> no-op sentinel, cap length); unit-tested. Text entry is a **`PlasmaCore.Dialog`** (TextField +
> Cancel/Rename + `hideOnWindowDeactivate`, the stock `AppletAlternatives` idiom) **declared directly**
> with `visible:false` — *not* wrapped in a `Loader` (a `Loader` is for `Item`s; a `Dialog` is a top-level
> `Window`, kept cheap by not realising a surface until shown) and *not* `Kirigami.PromptDialog`, whose
> base `Kirigami.Dialog` parents to `applicationWindow().overlay` — **undefined in a plasmoid**, so it
> would clip to the thin panel (robustness.md). The dialog *view* is its own **`RenameDialog.qml`** (the
> directly-declared `PlasmaCore.Dialog`, exposing `signal accepted(uuid, name)`); `main.qml` instantiates
> it, sets `visualParent: root.fullRepresentationItem` + `location: Plasmoid.location`, and turns
> `accepted` into the DBus write. The **action + DBus stay in `main.qml`** (the e2e boundary);
> `RenameDialog.qml` is view-only and likewise e2e-only (a top-level `Window`, not headless-testable).

> **Gotcha (learned the hard way) — scroll: a `MouseArea { acceptedButtons: Qt.NoButton; onWheel }`
> *behind* the dots, NOT a `WheelHandler`.** A `WheelHandler` did **not** deliver wheel reliably in
> a real panel. The working pattern (KWin's `KeyboardLayoutSwitcher`): a MouseArea that accepts
> **no buttons** and sits **below** the dots — a wheel over a dot propagates down to it (dots have
> no `onWheel`), while clicks, hover and right-clicks pass straight through to the dots / the applet.
> Accumulate `angleDelta.y` into 120-unit notches (touchpads send sub-notch deltas) via
> `logic.js::accumulateWheel`. **Verify with a real `mouseWheel()` event test** (`qmltestrunner`
> supports it), not just by calling the handler — event-routing is the part that breaks, and a
> handler-only test will pass while the widget is dead in-shell.

> **Gotcha (learned the hard way) — tooltip: a per-dot `PlasmaCore.ToolTipArea` inside
> `WorkspaceDot`, NOT one wrapping the representation.** A single strip-level `ToolTipArea` as the
> representation root mis-positioned the tooltip (showed over the *pill*, or not at all when the
> cell was mis-sized) **and** broke applet sizing (see the `Layout.*` gotcha above). Each
> `WorkspaceDot` carries its own `ToolTipArea` (`mainText: desktopName`,
> `active: showTooltips && desktopName !== ""`); the indicator feeds every dot its name + the flag.
> `ToolTipArea` is a **public C++ type** in `org.kde.plasma.core` (not in the module's `qmldir`;
> prototype `QQuickItem`, so it has `containsMouse`/`active`/`mainText` but is **not** a `MouseArea`
> — no `onClicked`). It loads and tracks hover under headless `qmltestrunner`, so `WorkspaceDot`
> importing `org.kde.plasma.core` does **not** break the unit/integration tiers.

> **Accessibility — each `WorkspaceDot` is a named, pressable button for screen readers.** The dot's
> root sets `Accessible.role: Accessible.Button`, `Accessible.name: desktopName` (the same string the
> tooltip shows; tracks it live), `Accessible.checkable: true` + `Accessible.checked: dot.active` (so an
> AT can tell WHICH dot is the current desktop — otherwise every dot is an identically-roled button), and
> `Accessible.onPressAction: dot.activated()` — so Orca announces each dot as a button named after its
> desktop, reports the current one as checked, and an AT-driven press switches through the **same**
> `activated()` → `switchRequested` path as a pointer click. `Accessible` is part of `QtQuick` (no
> extra import) and the per-dot a11y lives on the element (not the indicator), staying headless-testable
> (`tst_workspacedot.qml::{test_accessibleExposesButtonRole,test_accessibleCheckedTracksActive,test_accessiblePressEmitsActivated}`).
> Keyboard *switching* itself is KWin's global `Ctrl+F<n>` (reflected live via `VirtualDesktopInfo`),
> so the dots add **no** Tab-focus/key handling of their own — deliberately out of scope.
> **Verify the live exposure with an AT-SPI tree dump** (pyatspi — find the `plasmashell` app, recurse
> for `*button*` nodes), **not** Orca hover: Orca's mouse-review is broken on **Wayland** (it can't track
> the pointer) and the dots aren't Tab-focusable, so neither hover nor focus-tracking announces them — an
> Orca-on-Wayland limitation, **not** the widget's (so user-facing copy should attribute it to Orca, not
> undersell the widget). A correct dump shows `[button] name='Desktop 1'
> states=checked,checkable,focusable,sensitive` (current) and `Desktop 2` without `checked`; an AT client
> (Orca) must be running so Qt activates its a11y bridge. Full recipe in the project memory
> (`verify-a11y-via-atspi-tree-dump`).

**Window-list tooltip — windows-per-desktop from the PUBLIC `TasksModel`, NOT the private
`PagerModel`.** The tooltip's `subText` is the stock KDE pager's window list ("N Windows:" + a
rich-text `<ul>` of titles + "…and N other windows", a separate "N Minimized Windows:" section),
gated by the `showWindowList` key. The stock pager builds this from a **private** `PagerModel`/
`WindowModel` (`org.kde.plasma.private.pager`) — forbidden (robustness.md, the #1 break cause). We
reproduce the exact *presentation* from the public `org.kde.taskmanager` `TasksModel` + `ActivityInfo`
instead. The split, following the project's data-source-vs-pure-logic rule:
> - **`main.qml` (e2e boundary, not headless-testable)** owns the `Loader`, not the model itself: the
>   live `TasksModel` lives in `WindowAggregator.qml` (the desktop set flows in as the **injected**
>   `virtualDesktopInfo: vdi` property — not closure-captured `vdi`). The `Loader` is gated by
>   `(showTooltips && showWindowList) || dynamicWorkspaces` (so the always-on model cost is **zero**
>   when neither the window list nor dynamic workspaces needs it — qml-performance.md) and loads the
>   `WindowAggregator` Item (shared by both features) holding ONE unfiltered
>   `TasksModel { groupMode: GroupDisabled; filterByActivity: true }` (one row per window; current
>   activity only). An `Instantiator` materialises the rows so role values can be read **by name**
>   (a C++ `QAbstractItemModel` has no `model.get(i)`); a debounced `Qt.callLater(rebuild)` (driven by
>   the model's `dataChanged` — **role-filtered** via `Logic.dataChangeAffectsRoles(roles, relevantRoles)`
>   so the high-frequency `IsActive` focus churn KWin emits on every window-focus change never triggers a
>   no-op regroup (an empty/absent roles list is Qt's "all changed" → still rebuilds) — plus the
>   Instantiator's `onObjectAdded`/`onObjectRemoved` + `virtualDesktopInfo.desktopIdsChanged`) snapshots
>   the rows, calls the pure grouping, then wraps each result with `i18ncp`/`i18nc` into the HTML
>   `subText`. **`relevantRoles` is conditional on an injected `windowListActive` bool (`=
>   showTooltips && showWindowList`):** the aggregator can be live purely for dynamic-workspace
>   occupancy, and occupancy reads none of the title/minimised state, so when the window list is off
>   the set drops `Qt.DisplayRole` + `IsMinimized` (leaving the occupancy roles `VirtualDesktops`/
>   `IsOnAllVirtualDesktops`/`IsWindow`/`SkipPager`/`ScreenGeometry` — the last in BOTH branches, for
>   per-screen occupancy) — title-rename and minimise-toggle churn then no
>   longer wakes a rebuild whose tooltip output `main.qml` would discard, and `rebuild()` skips building
>   the HTML `<ul>`s entirely (leaves `desktopTooltips` `[]`). Toggling the list at runtime flips
>   `windowListActive`, and `onWindowListActiveChanged` forces the one rebuild that repopulates/clears
>   the tooltips. The SAME snapshot also feeds `Logic.computeDesktopOccupancy` → `desktopOccupancy` (GLOBAL,
>   all monitors) for the dynamic-workspaces controller AND `Logic.computeDesktopOccupancyForScreen` →
>   `screenOccupancy` (PER-SCREEN, this monitor — for the occupied-dot indicator; see the per-screen
>   occupancy gotcha below) — one model, THREE outputs. All three
>   outputs are reassigned **compare-before-assign** (`Logic.arraysShallowEqual`): a QML `var`/object
>   property notifies on every reassignment to a fresh reference (which each freshly-built array is —
>   no contents compare), so keeping the old reference when contents match is what stops an identical
>   occupancy snapshot waking the dynamic controller (or an identical tooltip array re-firing every
>   dot's binding) on unrelated window churn. The per-desktop strings flow DOWN as a plain `desktopTooltips` array, index-aligned
>   with `desktopIds` (exactly parallel to `desktopNames`): `main.qml` → `WorkspaceIndicator`
>   (`desktopTooltips`) → each `WorkspaceDot.tooltipText` by `globalIndex` → `ToolTipArea.subText`
>   (with `textFormat: Text.RichText`). The sub-components never touch `TasksModel`, so they stay
>   headless-testable.
> - **`logic.js` (pure, unit-tested)** does the grouping/truncation with NO Plasma/i18n deps:
>   `groupWindowsByDesktop(windows, desktopIds)` → per-desktop `{ visible:[title…], minimized:[title…] }`
>   (a window belongs to a desktop when `isWindow && (onAll || desktops.indexOf(uuid) !== -1)`);
>   `windowListMaximum(count)` (the stock rule: 4, but all 5 when exactly 5); `sanitizeHtml` (escapes
>   `<>&'"` and the no-break space ` ` — **not** the ordinary space, which must still wrap);
>   `dataChangeAffectsRoles(changedRoles, relevantRoles)` (the rebuild gate above — true when a read role
>   changed OR `changedRoles` is empty/absent = Qt's "all changed", false for pure focus/stacking churn);
>   `arraysShallowEqual(a, b)` (flat-primitive element-wise compare, identity/null/length guarded — the
>   compare-before-assign guard the aggregator uses so an unchanged occupancy/tooltip array skips its
>   `var` reassignment and the downstream notification it would otherwise always fire).
>   i18n formatting stays in `main.qml` because `i18n*` is a plasmoid global, absent under `qmltestrunner`.
>
> **Gotcha — `as`-cast dynamic `Loader.item`/`Instantiator.objectAt()` to a NAMED inline component, or
> qmllint flags `missing-property`.** `Loader.item` and `Instantiator.objectAt(i)` are typed `QObject`,
> so reading a dynamic property off them (`tooltipLoader.item.desktopTooltips`, `o.display`) warns. Fix
> exactly like the stock pager's `itemAt(i) as WindowDelegate`: cast to a named type. The loaded item
> is the **file-based** `WindowAggregator` type (`package/contents/ui/WindowAggregator.qml`, a top-level
> `Item`), so `main.qml` casts `(tooltipLoader.item as WindowAggregator).desktopTooltips`; the row is a
> named inline `component WindowRow: QtObject {…}` declared **inside `WindowAggregator.qml`**, cast there
> as `winInstantiator.objectAt(i) as WindowRow`. Capitalised `TasksModel` roles (`VirtualDesktops`,
> `IsOnAllVirtualDesktops`, `IsMinimized`, `IsWindow`, `SkipPager`, `ScreenGeometry`) aren't valid lowercase identifiers, so they can't
> be `required property`s — read them off the var `model` inside `WindowRow`; only the lowercase
> `display` (the title) is a required property. Normalise `VirtualDesktops` with `.map(x => String(x))`
> before comparing to `desktopIds` (the role elements may be UUID-variant wrappers, not plain strings),
> and snapshot `ScreenGeometry` (a `QRect` role) into a plain `{x,y,width,height}` so `logic.js` stays Plasma-free.
> Guarded by `tst_logic.qml::{test_windowListMaximum,test_sanitizeHtml,test_groupWindowsByDesktop,test_dataChangeAffectsRoles,test_arraysShallowEqual}` +
> `tst_indicator_content.qml::test_dotsReceiveTooltipText` (and short-array/multi-row variants) +
> `tst_workspacedot.qml::{test_tooltipShowsSubText,test_tooltipTextFormatIsRichText}`. The aggregator
> itself — including the `windowListActive` role/format gating and the compare-before-assign — is
> e2e-only (verify in-shell).

> **Per-screen occupancy (Plasma 6.7 per-output desktops) — the indicator reflects ITS monitor, the
> dynamic controller stays GLOBAL.** The occupied-dot indicator must mark a desktop occupied only when a
> window on that desktop is **physically on this pager's monitor** (else a window on monitor 1 lights the
> same dot on every monitor — the symptom). Virtual desktops are global UUIDs; a window's monitor is its
> `TasksModel.ScreenGeometry` role (a `QRect`; there is **no** screen-NAME role). We match it to the
> pager's own output rect — `WorkspaceIndicator.screenRect = Qt.rect(Screen.virtualX, Screen.virtualY,
> Screen.width, Screen.height)` (the `Screen` attached property; it has **no** `geometry`), which
> `main.qml` reads off `fullRepresentationItem` (Screen.* is only valid on the placed representation) and
> injects into `WindowAggregator` (mirroring how `virtualDesktopInfo` is injected). The decision is the
> pure `Logic.computeDesktopOccupancyForScreen(windows, ids, screenRect)` / `windowOccupiesDesktopOnScreen`,
> which **match by rect ORIGIN `(x,y)` only** — outputs have unique top-lefts, while width/height differ
> between the two sources under per-output scaling — so it tolerates fractional scaling (integer `===`,
> exact). It **degrades to global** (never hides a window) when the target rect is absent (pager not yet
> placed → identical to `computeDesktopOccupancy`, so single-monitor is byte-for-byte unchanged) or a
> window has no own screen rect. This is **unconditional, no config key** — it auto-mirrors KWin exactly
> like the per-screen *current desktop* feature (mirror System Settings, don't add a redundant widget knob). Crucially the
> aggregator emits TWO occupancy arrays from the one snapshot: `screenOccupancy` (per-screen) → the
> indicator, and `desktopOccupancy` (GLOBAL) → the `DynamicWorkspacesController` — the desktop SET is
> global and coordinated across panels, so a per-screen view there would make panels fight over the
> trailing empty. Guarded by `tst_logic.qml::{test_windowOccupiesDesktopOnScreen,
> test_computeDesktopOccupancyForScreen,test_computeDesktopOccupancyForScreenDegradesToGlobal}`; the live
> `ScreenGeometry` read + the coordinate-space assumption (that role's origin == `Screen.virtualX/Y`) are
> e2e-only — **verify on a real multi-monitor rig** (a mismatch would mark nothing occupied).

**Dynamic workspaces (GNOME-style) — auto-maintain ONE empty trailing desktop; default OFF; one
GLOBAL behaviour across panels.** When enabled, the widget keeps exactly one empty desktop at the
end: populate the last desktop and a new empty one is appended; trim surplus trailing empties back to
one. It reuses the **same** shared `WindowAggregator` `TasksModel` as the window-list tooltip (the
Loader gate is the OR of the two features), which now also emits a per-desktop occupancy `bool[]`
(`desktopOccupancy`, index-aligned with `desktopIds`). The split mirrors the rest of the project —
pure decision in `logic.js`, e2e wiring in `main.qml`:

> **Gotcha — the Loader-OR means "aggregator live" no longer implies "show the window list".** Since
> the aggregator can now be loaded purely for dynamic workspaces, `main.qml`'s `desktopTooltips` MUST
> be gated by `showTooltips && showWindowList` independently of the Loader being active — otherwise
> enabling dynamic workspaces resurfaces the window-list tooltip the user turned off. `desktopOccupancy`
> stays ungated (it's what dynamic workspaces consumes).
>
> **Mutually exclusive with manual add/remove.** Dynamic workspaces and the `enableAddRemove`
> right-click entries manage desktops in conflicting ways (the controller instantly trims a
> manually-added empty / re-adds a removed trailing empty), so the Add/Remove `contextualActions` are
> gated `enableAddRemove && !dynamicWorkspaces` (hidden on EVERY panel — `dynamicWorkspaces` is global,
> `enableAddRemove` per-panel) and the `ConfigGeneral` checkbox is `enabled: !dynamicWorkspaces.checked`
> (greyed, value preserved — non-destructive, returns when dynamic is off), with a hint label. Rename
> is untouched (it doesn't conflict).
> - **`logic.js` (pure, unit-tested)**: `windowOccupiesDesktop(window, uuid)` — occupancy membership
>   that, UNLIKE the tooltip's `windowIsOnDesktop`, **excludes** on-all-desktops AND `skipPager`
>   windows (an on-all window would pin every desktop as non-empty, so nothing could ever be empty)
>   and **includes** minimized ones (a minimized window still occupies its desktop — GNOME + the KWin
>   "Dynamic Workspaces" scripts agree); `computeDesktopOccupancy(windows, desktopIds)` → the `bool[]`;
>   `dynamicWorkspacePlan(occupancy, desktopIds)` → ONE action per cycle (`{kind:"add"}` at 0 trailing
>   empties, `{kind:"remove", uuid}` of the LAST at ≥2, else `null`), so reactive re-triggering
>   converges to exactly one trailing empty. **Only the trailing run is managed — empty MIDDLE desktops
>   are left alone** (an earlier `dynamicRemoveMiddle` option was removed as unreliable). Every transient
>   frame is a no-op: `null` on absent arrays, an empty set, or `occupancy.length !== desktopIds.length`
>   (occupancy lags a just-changed desktop set by a frame). `formatDynamicDesktopName(prefix, number,
>   fallback)` → `"<prefix> N"`, **never empty**. Removal reuses `canRemoveDesktop`.
> - **`DynamicWorkspacesController.qml` (its own non-visual component, headless-tested)**: a debounced
>   `scheduleDynamic` → `evaluateDynamic` that, when this instance is the elected writer (below), runs the
>   pure plan and emits `dispatchRequested(spec)` — the single `addSpec`/`removeSpec`, which `main.qml`
>   feeds to `dispatch`; a per-instance `dynBusy` lock (cleared on the injected vdi's `desktopIdsChanged`
>   — the signal our own write landed — with a named `busyFallbackMs` (750 ms) `Timer` fallback) stops it
>   re-firing before its change reflects. Triggered by `onDesktopOccupancyChanged`, the vdi's
>   `desktopIdsChanged`, and its own setting changes. Inputs (`dynamicEnabled`/`namePrefix`/
>   `defaultPrefix`/`virtualDesktopInfo`/`desktopOccupancy`) flow IN as plain values and side effects flow
>   OUT as the two signals `dispatchRequested`/`syncConfigRequested`, so the controller is Plasma-free —
>   extracted out of `main.qml` for exactly that (single responsibility + headless testability).
>
> **Gotcha — the desktop SET is GLOBAL, so this must be a SINGLE global behaviour: `coordinator.js`
> (`.pragma library`, shared ONCE per plasmashell engine).** Two panels (multi-monitor) both see the
> last desktop fill and BOTH `createDesktop` → the surplus is trimmed → a visible **flash** of the
> dots/pill (and inconsistent naming). plasmashell runs every applet in ONE process/QML engine, and a
> `.pragma library` is instantiated ONCE per engine, so `coordinator.js`'s module state is **shared
> across all pager instances** — the only pure-QML way to coordinate them (robustness.md: no private
> imports, no C++). It provides: (1) **single-WRITER election** — `Logic.electDynamicWriter(registry)`
> (pure, tested) picks the lowest-token present instance; only it issues add/remove, killing the flash;
> (2) **GLOBAL setting SYNC** — `dynamicWorkspaces` AND `dynamicNamePrefix` are ONE global value:
> `publish()` records it and pushes it to every instance (the `onSync` callback each passed to `join`),
> which the controller re-emits as `syncConfigRequested` for `main.qml` to mirror into its OWN
> `Plasmoid.configuration` (the one Plasma write kept at the e2e boundary) — so toggling/renaming on ANY
> panel applies everywhere and every settings dialog agrees (a true global toggle; the writer election
> is STILL needed because all panels are then enabled). If the shared-engine assumption ever failed,
> each instance would seed/own its global and elect itself — the per-instance behaviour — degraded,
> never crashing.
>
> **Gotcha — KWin silently DROPS `createDesktop` when the name is empty.** An empty-name auto-create
> no-ops with no error (the "feature does nothing" symptom we hit). `Logic.formatDynamicDesktopName`
> therefore always returns a non-empty `"<prefix> N"` (prefix synced via the coordinator, default the
> i18n `"Desktop"` passed IN from `main.qml` so `logic.js` stays i18n-free). KWin's `removeDesktop(uuid)`
> reassigns any windows itself, so removal needs no window-shifting.
>
> **Gotcha — config bindings (and their `onChanged`) evaluate BEFORE `Component.onCompleted`.** So a
> coordinator write during binding setup would use the sentinel token `0` (not joined yet) and register
> a phantom "enabled" instance that wins the election (`0 < every real token`) and stalls the real
> writer — the bug that made the feature "do nothing". Guard every coordinator write until
> `dynToken !== 0` (`join()` never returns 0); the controller's `Component.onCompleted` joins first, then
> adopts the global (if a sibling seeded it) or seeds it from this instance's stored config. `main.qml`'s
> `syncConfigRequested` handler is value-guarded and the controller's `publishDynamicConfig` only
> republishes a value that DIFFERS from the coordinator's authoritative global, so the
> sync→`onChanged`→publish path can't loop. Writing
> `Plasmoid.configuration.<key>` from the applet (not just the config dialog) is what persists + mirrors
> the synced value.
>
> Guarded by `tst_logic.qml::{test_computeDesktopOccupancy,test_dynamicWorkspacePlan,
> test_formatDynamicDesktopName,test_electDynamicWriter}` + `tst_coordinator.qml` (the coordinator
> state machine, incl. the multi-instance election + writer-handoff chain) +
> `tst_dynamicworkspacescontroller.qml` (the controller's reactive state machine — add/remove specs,
> busy-lock, convergence over re-evaluations, single-writer election, setting sync — driven headless via a
> `VdiMock` + injected occupancy, the controller emitting its specs as signals). The live occupancy model
> and the cross-instance SHARING (one `.pragma library` per real plasmashell engine) remain **e2e-only**
> (verify in-shell). New files: `package/contents/ui/coordinator.js`,
> `package/contents/ui/WindowAggregator.qml` (the shared `TasksModel`, extracted out of `main.qml`;
> feeds both the window-list tooltip and dynamic-workspace occupancy),
> `package/contents/ui/DynamicWorkspacesController.qml` (the dynamic-workspaces controller, extracted out
> of `main.qml`), `tests/unit/tst_coordinator.qml`, `tests/unit/tst_configslider.qml`,
> `tests/integration/tst_dynamicworkspacescontroller.qml`.

**Config flow.** Every key lives in `package/contents/config/main.xml` (KConfigXT) and is read
**live** in `main.qml`, then passed DOWN as plain values: `main.xml` → `main.qml`
(`Plasmoid.configuration.<key> ?? Logic.DEFAULTS.<key>`) → `WorkspaceIndicator` → `WorkspaceDot`.
This keeps the sub-components free of `plasmoid.configuration` so they stay headless-testable.
`Logic.DEFAULTS` (a frozen object in `logic.js`) is the **single source of truth for the QML-side
fallback defaults** — referenced by `main.qml`'s `??` guards AND by the indicator/dot property
defaults, so the same literal is no longer written three times and cannot drift. `main.xml` stays
the SCHEMA source; `Logic.DEFAULTS` mirrors it. (Theme/HiDPI render fallbacks — the auto `dotSize`,
the `Kirigami.Theme.*` colours — are NOT in `DEFAULTS`; they live in the components, see the sentinel
gotcha below.) The keys:
behaviour — `enableScroll`, `scrollWrap`, `invertScroll` (flip the wheel-direction → desktop
mapping), `pillClickAction` (what clicking the ALREADY-CURRENT desktop's pill does — a
`ConfigGeneral` combo whose index mirrors `Logic.PILL_CLICK_ACTION`: `0 = None` (default off, a
no-op), `1 = Show Desktop`, `2 = Overview`, `3 = Grid`; the three actions TOGGLE a KWin global
shortcut — see the pill-click gotcha below), `showTooltips`, `showWindowList` (the window list in the
tooltip; only applies when `showTooltips` is on — the `ConfigGeneral` checkbox is `enabled:` off it),
`enableAddRemove`, `enableRename` (the "Rename Current Desktop…" menu entry), `dynamicWorkspaces`
(GNOME-style auto add/remove of one empty trailing desktop, default off; GLOBAL across panels via
`coordinator.js`), `dynamicNamePrefix` (base name for auto-created desktops — a `String` edited via a
`ConfigGeneral` `TextField`, `"" = the i18n default "Desktop"`; also globally synced), `animationDuration`;
appearance — `dotStyle` (the OVERALL look, a `ConfigAppearance` combo whose index mirrors
`Logic.DOT_STYLE`: `0 = Sliding pill` (default, the REFLOW look), `1 = Filled & ring` (no pill;
current = filled circle, others = hollow rings — see the Filled & ring gotcha below)),
`singleLine` (Bool, default off — ignore KWin's grid ROWS and lay every desktop out in ONE line; forces
`desktopRows = 1`. ORTHOGONAL to `matchDesktopGrid` (count vs direction): see the single-line gotcha below),
`matchDesktopGrid` (Bool, default off — on a VERTICAL panel run the layout ACROSS the panel instead of down it;
for a multi-row grid that mirrors KWin orientation (rows top-to-bottom), and with `singleLine` it makes the one
line horizontal — see the grid-orientation gotcha above; a presentation toggle, not a grid-shape knob),
`dotSize`, `pillSize` (active-pill thickness, sized independently of the dots; `0 =
auto = match the dots`), `spacingFactor`, `pillWidthFactor` (pill length as a multiple of the PILL
thickness — "× pill"; both pill keys are ignored/greyed in the Filled & ring style),
`inactiveOpacity`, `hoverOpacity`, `showOccupancy` (occupied-dot indicator,
default off — mark desktops that hold windows) + `occupiedOpacity` (marker opacity, all styles) +
`occupancyStyle` (Filled/InnerDot/Ring, a `ConfigAppearance` combo whose index mirrors `Logic.OCCUPANCY`),
`followThemeColors`, `activeColor`, `inactiveColor`, `occupiedColor` (the occupied-marker colour, used
when not following the theme). The settings UI is two files that must agree with the schema:
- `package/contents/config/config.qml` — `ConfigModel` listing the settings categories
  (Behavior, Appearance).
- `package/contents/ui/config/*.qml` — the settings pages (`ConfigGeneral`, `ConfigAppearance`),
  two-way bound via `property alias cfg_<key>: control.value` where `<key>` matches the `main.xml`
  entry exactly. Both pages subclass the shared **`ConfigPageBase.qml`** (a `Kirigami.ScrollablePage`
  — on robustness.md's allowlist; the stock `KCM.SimpleKCM` is just a subclass) so the dialog renders
  the standard KDE title header + spacing + scrolling AND each page gets the Defaults header action
  for free (see below). Every numeric metric (sizes, ratios, opacities, duration — including the
  integer keys) uses the shared `ConfigSlider.qml`; only the colours use `org.kde.kquickcontrols`
  `ColorButton` — a public module that is NOT on robustness.md's allowlist but is acceptable here
  **only because a config page is lazy-loaded** (instantiated by the settings dialog, never by the
  always-on widget), so a break there cannot kill the running pager. The config **pages**
  (`ConfigGeneral`/`ConfigAppearance`/`config.qml`) are **e2e-only** (the dialog needs
  `org.kde.plasma.configuration`), so they are not in the headless test harness — `make lint` covers
  them, but verify behaviour in-shell. The shared `ConfigSlider` control is the exception: being
  Kirigami-only it **is** headless-unit-tested by `tests/unit/tst_configslider.qml`.
- **Defaults button:** the Plasma applet config dialog footer is only Apply/Discard/Cancel — it has
  **no** Defaults button. `ConfigPageBase` adds one **once** as a header `Kirigami.Action` (gated by
  `root.isModified`, firing `root.defaultsRequested()`) **and** owns the whole contract off a single
  `configKeys` property (a `{ n, t }` list): the base **binds** `isModified` (any `cfg_<key>` differs
  from its `cfg_<key>Default`, via the type-aware `fieldChanged` helper) and **handles**
  `onDefaultsRequested` (reset every key to its `cfg_<key>Default` via `resetField`). So a derived page
  declares only its `configKeys` list (plus the QML-required `cfg_<key>` aliases) — it no longer
  repeats the `isModified`/`onDefaultsRequested` bindings. `cfg_<key>Default` is a property the dialog
  injects from the schema default — declared on the page with no initializer so `main.xml` stays the
  single source of truth.
- **Gotcha:** `ConfigCategory.source` paths resolve relative to `contents/ui/`, which is why
  config *pages* live in `contents/ui/config/` while the schema/categories live in
  `contents/config/`. Mixing this up yields an empty settings dialog.

> **Gotcha — reserve the value-label width AND fix the track width; the slider is NOT `fillWidth`.**
> `ConfigSlider.qml` makes two coupled layout decisions. **(1) Reserve the read-out width** or the
> slider jitters: the value `Label`'s implicit width changes with the value (`"45%" → "100%"`, and
> even `"1.0× dot" → "4.0× dot"` since digits differ in a proportional font), reflowing the row so the
> track/handle appear to jump while dragging. A single `format` closure (value → display string)
> supplies BOTH the live read-out AND the reserved width — the component pins the label (via
> `TextMetrics`) to the wider of `format(from)`/`format(to)` + a small buffer. Because every formatter
> here is monotonic in string width with magnitude AND the sentinel sliders put their special text at
> `from` (`0 → "Default"`), reserving over the two extremes bounds every value between them (no
> separate `widestText` to keep in sync). **(2) Fix the track width**: the `Slider` is a FIXED
> `Layout.preferredWidth == Layout.minimumWidth == ConfigSlider.trackWidth` (the named constant
> `Kirigami.Units.gridUnit * 18`; `ConfigPageBase.fieldWidth` is pinned to the same metric so non-slider
> fields line up) — it is the value **`Label`** that is
> `Layout.fillWidth` (and right-aligned), NOT the track. A `fillWidth` track stretches to its
> `FormLayout` field column, which the Behavior page's long checkbox labels widen well beyond the
> slider-only Appearance page — so the sliders rendered *different lengths* across the two pages.
> Pinning the track and letting the right-aligned read-out absorb any extra column width keeps both
> pages' sliders matched (the trade-off: on a wide page the read-out sits at the column's right edge,
> gapped from the slider). `snapMode` defaults to `SnapAlways` in the component; callers just set
> `from/to/stepSize` + `format`.

> **Gotcha — theme/HiDPI-derived defaults use a `0 = auto` sentinel.** A KConfigXT default is a
> fixed literal, so it cannot be `Kirigami.Units.iconSizes.small / 2` or `Kirigami.Units.longDuration`
> — baking a px/ms literal would lose HiDPI/theme scaling (kirigami.md). Instead `dotSize`, `pillSize`
> (`0 = match the dots` → the effective `dotSize`, via `pillThicknessRatio == 1`), and
> `animationDuration` default to `0` meaning "auto", and the sentinel is resolved **inside the
> components** (`IndicatorMetrics`'s `dotSize`/`pillSize`, and `Logic.effectiveDuration` for the morph) —
> NOT in `main.qml`, because the components are the headless-tested rendering layer (`main.qml` is the
> e2e boundary, not itself headless-testable). `effectiveDuration` also
> folds in the reduce-animations guard (`Kirigami.Units.longDuration === 0` always wins → instant),
> so `animationDuration` overrides the duration but can never re-enable motion the user turned off.
> The dimensionless ratios (`spacingFactor`/`pillWidthFactor`/`inactiveOpacity`/`hoverOpacity`) are
> plain literal defaults. Colours follow the scheme unless `followThemeColors` is false, then
> `activeColor`/`inactiveColor` apply (`Logic.dotColor`; the binding still references the live
> `Kirigami.Theme.*` so it re-evaluates on a colour-scheme change).

> **Gotcha — guard every config read with `?? Logic.DEFAULTS.<key>`.** `readonly property bool
> enableScroll: Plasmoid.configuration.enableScroll ?? Logic.DEFAULTS.enableScroll`. A freshly-added
> schema can read back `undefined` for a frame (or until the widget is removed/re-added), and a bare
> `bool` then collapses to `false`, **silently disabling every interaction**. The `??` fallback comes
> from `Logic.DEFAULTS` (the SSOT mirror of the schema defaults; see "Config flow") and is a no-op
> once the value is real (`false ?? true === false`). After editing `main.xml`, reload with
> `make restart`; if keys still read stale, `rm -rf ~/.cache/plasmashell/qmlcache` or remove/re-add
> the widget.

Widget id (also the install folder name): `com.github.kenansalar.plasma-gnome-pager`.

> **Gotcha (learned the hard way) — `metadata.json` `Icon` must be an icon-theme NAME, NOT a
> bundled file.** The "Add Widgets" chooser (and `Plasmoid.icon`) resolve `Icon` only via the icon
> theme — a relative/bundled path like `../icons/pager.svg` (or any `contents/icons/*.svg`) renders
> the broken-image `?` placeholder, **never** the file. This is a confirmed Plasma limitation, not a
> path-syntax mistake: KDE has **no** mechanism to resolve a plasmoid's bundled icon for the chooser
> (a KDE dev's words: *"That does seem bad. Might be worth formally supporting this"*). A bundled SVG
> only shows in the chooser if it's installed into the icon **theme** (e.g.
> `~/.local/share/icons/hicolor/scalable/apps/<name>.svg`) — which `kpackagetool6`, the `.plasmoid`
> zip, and the KDE Store's "Get New Widgets" (KNewStuff) do **not** do; only distro packaging (AUR/RPM
> `make install`-style steps) or a manual copy would. So a *custom* chooser icon **cannot** work for
> Store users (chicken-and-egg: the chooser needs the icon **before** the widget ever runs, so no
> first-run self-install can fix the first impression). The popular widgets all sidestep this by
> naming a stock icon (`plasma-panel-colorizer` → `desktop`, the weather widget → `weather-clear`)
> and shipping their custom SVG only for *in-widget* / KDE-Store-product-page use.
>
> We therefore ship **`Icon: "virtual-desktops"`** — a standard Breeze icon (a desktop grid with one
> cell highlighted; semantically a pager) that is **safe on any theme + any install method, Store
> included**. It is **monochrome**, so it recolors to the scheme/accent; many themes (Papirus, etc.)
> ship their **own** `virtual-desktops` so it renders native to the active theme, and the ones that
> don't (pure Adwaita/HighContrast — they inherit only `hicolor` and lack the name) still resolve it
> via **KDE's always-present Breeze fallback** (KDE's icon loader injects Breeze regardless of the
> active theme — the same backstop that keeps Plasma's own UI from ever showing broken icons). Note
> `virtual-desktops` is a KDE/Breeze name, **not** a freedesktop-spec-standard name, so the guarantee
> rests on that Breeze fallback — which can only be absent if the Breeze icon set is uninstalled, at
> which point Plasma itself is broken. (Verified live across Breeze, Fedora, and Catppuccin global
> themes and the Breeze icon set.)

## Internationalization (i18n)

All user-visible strings are wrapped at the call site in `i18n`/`i18nc`/`i18np`/`i18ncp` (with
`@…` context comments on the tooltip strings) — they live **only in the QML** (`main.qml` + the
config pages). `logic.js` is deliberately **i18n-free**: it keeps strings raw and the formatting
(i18n + HTML) happens in `main.qml`, because `logic.js` is headless-unit-tested where the `i18n*`
globals don't exist (see "Config flow"/the window-list section). So extraction scans `*.qml` only.

- **Domain (auto-bound):** the Plasma runtime sets the QML `KLocalizedContext` domain to
  `plasma_applet_<KPlugin.Id>` = `plasma_applet_com.github.kenansalar.plasma-gnome-pager`, so the
  bare `i18n(...)` calls resolve to our catalog with **no** explicit domain wiring in QML.
- **Source vs. artifact:** the committed **source of truth** is the per-language `po/<lang>.po`
  files (human-authored translations). BOTH the `po/<domain>.pot` template AND the compiled
  `po/<lang>.po → package/contents/locale/<lang>/LC_MESSAGES/<domain>.mo` catalogs are **generated
  and gitignored** (`po/*.pot` + `package/contents/locale/`): the `.pot` is re-extracted from the
  QML by `make messages` on every run (nothing in the build *reads* the committed copy — `xgettext`
  overwrites it, then `msgmerge` reads that fresh copy), so committing it only adds date +
  line-number churn. `kpackagetool6` ships the package tree verbatim and does **no** compilation, so
  the `.mo` must exist under `package/` before packaging — `make i18n` compiles them and
  `install`/`update`/`dev` depend on it.
- **Workflow:** `make messages` (re)extracts via `xgettext` (ki18n keyword set, so contexts +
  plural forms come through) into the `.pot` and `msgmerge`s every `.po`; `make i18n` compiles each
  `.po` (`msgfmt --check`) into the package. Commit only the changed `.po` (the `.pot` is ignored).
  Add a language by running `make messages` (to regenerate the local `.pot`), then `msginit
  --locale=<ll>` from it, translating, and `make i18n` (README "Translations" has the recipe). Shipped: English (source) +
  12 translation catalogs (`de`, `fr`, `es`, `el`, `it`, `tr`, `pt`, `pt_BR`, `ar`, `zh_CN`, `ru`,
  `ja`) — note `pt`/`pt_BR` are separate catalogs, and plural-form counts vary (1 for `zh_CN`/`ja`,
  3 for `ru`, 6 for `ar`).
- **`metadata.json` Name/Description** are translated by **language-suffixed JSON keys**
  (`Description[de]`), **not** the `.mo` catalog. `Name` stays the product proper-noun.
- **The qmllint `i18n` "unqualified" warning is NOT a translation concern.** It fired because the
  `i18n*`/`Plasmoid` globals are `KLocalizedContext` context properties qmllint can't statically
  resolve. `./.contextProperties.ini` (`[General] disableUnqualifiedAccess = "i18n,…,Plasmoid"`,
  KDE's own mechanism) declares them so they no longer warn — while a *genuine* unqualified access
  is still caught. `make lint` is now fully clean. Adding catalogs alone would not have done this.

## Commands

```bash
make dev        # symlink package/ -> ~/.local/share/plasma/plasmoids/<id> for live editing
make test       # plasmawindowed <id> — run standalone; QML errors print to the terminal
make restart    # reload the real panel (systemd user service if active, else kquitapp6 + setsid -f plasmashell)
make check      # all headless QML tests (unit + integration): QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input tests/<tier>
make check-unit / make check-integration   # run a single tier (tests/unit, tests/integration)
make lint       # qmllint-qt6 the widget UI + ui/config/*.qml + config/config.qml + tests/{unit,integration,shared}/*.qml
make lint-js    # ESLint (strict, --max-warnings 0) the pure-JS tier: contents/ui/{logic,coordinator}.js + tests/shared/*.js (run `npm install` once first)
make verify     # all static + headless gates in one go: lint + lint-js + check
make messages   # extract translatable strings -> po/<domain>.pot, then msgmerge each po/*.po
make i18n       # compile po/*.po -> package/contents/locale/<lang>/LC_MESSAGES/<domain>.mo (install/update/dev depend on it)
make dev-undev  # remove the dev symlink
make install / make update / make uninstall   # kpackagetool6 install/upgrade/remove (install/update compile catalogs first)
make package    # build dist/<id>-<version>.plasmoid (zip of package/ with metadata.json at the archive root; depends on i18n)
```

**Lint/format before installing** (the rules say `qmllint`/`qmlformat`, but on this Fedora KDE
system those names are **not** on `PATH` — use the `-qt6` suffix or the qt6 libexec path):

```bash
qmllint-qt6 package/contents/ui/*.qml   # treat warnings as errors
qmlformat-qt6 -i package/contents/ui/*.qml                                # or /usr/lib64/qt6/bin/qmllint
```

`qmllint` is the primary safety net — it flags the removed/renamed Plasma 6 symbols and
private-import mistakes that `robustness.md` warns about and that otherwise fail silently at
runtime on a new Plasma version.

**ESLint covers the JS tier** (the `.qml` is qmllint's job — ESLint cannot lint QML). `make lint-js`
runs `eslint . --max-warnings 0` (strict, warnings-as-errors) over the only lintable JavaScript:
`contents/ui/{logic,coordinator}.js` + `tests/shared/*.js`. The rule set is **correctness-only**
(`@eslint/js` recommended + the strict signature rules `no-unused-vars` with `^_` ignores /
`no-unassigned-vars` / `no-useless-assignment` / `preserve-caught-error`, mirroring the FitnessMain
project); stylistic rules (`no-var`/`prefer-const`/`curly`) are deliberately **off** because the
house style is `var` + braceless ifs. Config: `eslint.config.mjs`. These are dev-only Node deps
(`package.json` + committed `package-lock.json`, **not** shipped in the `.plasmoid`); provision once
with `npm install` (or `npm ci` in CI). No TypeScript/`tsc` and no Prettier — see the gotcha below.

> **Gotcha — the JS files are QML `.pragma library` modules, so standard JS tooling can't parse them
> raw.** Every `.js` here opens with `.pragma library` (and `coordinator.js`/`elements.js` add
> `.import "x.js" as Y`) — QML engine directives that are **syntax errors** to espree, `tsc`, and
> Prettier alike. ESLint is made to work via a tiny **custom parser** (`tools/eslint-qml-js-parser.mjs`)
> that rewrites those 1-2 directive lines to line-preserving comments (`.import … as Logic` →
> `/​* global Logic *​/`, so `no-undef` sees the cross-module binding) before delegating to `espree`;
> line/column numbers stay exact. This is a **custom parser, NOT a flat-config processor** — a
> processor emits a nested virtual filename (`logic.js/0_qml.js`) the `files` globs don't match, so the
> rules silently never run (verified: it was a no-op). Because top-level `function`/`var` are implicit
> QML exports, `no-unused-vars` uses `vars: "local"`. The same directive wall is **why there is no
> `tsc`/checkJs type-checking** (tsc has no parser hook and would need a temp-copy build + ~37 functions
> of `@param` JSDoc, duplicating `tst_logic.qml`) **and no Prettier** (it errors instead of skipping).
> A TS-aware editor will still red-underline the `.pragma`/`.import` lines — that's the editor's
> built-in JS validator, harmless, and unrelated to `make lint-js`.

## Verifying a change

There is a headless QML test harness (`tests/`, run with `make check`) split into two tiers:
**unit** (`tests/unit/`, one component in isolation, e.g. `WorkspaceDot`) and **integration**
(`tests/integration/`, components composed + reactive wiring, e.g. `WorkspaceIndicator` driven
by a `QtObject` mock standing in for `VirtualDesktopInfo`). The `WorkspaceIndicator` suite is split
by concern into `tst_indicator_{morph,layout,input,content}.qml`, all deriving from the shared base
`tests/shared/IndicatorTestCase.qml` (it owns the component factory, the `VdiMock`/legacy doubles,
the `switchRequested` spy, the desktop-set fixtures, and the dot-tree locators; qmltestrunner imports
but never executes it). Run a single tier with `make check-unit` / `make check-integration`. It can only cover the Kirigami-only components;
`main.qml`/`PlasmoidItem` is **not** testable headless (it needs plasmashell + KWin + a session
bus), so it still relies on the manual in-shell loop below. New logic should come with a test
(see `tests/README.md`); when branching logic is added, extract it into a pure-JS tier
(`logic.js` + `tests/unit/tst_logic.qml`) that needs no Plasma deps. The verification loop is:

1. `make check` — all tiers green (offscreen `qmltestrunner-qt6`; non-zero exit on failure).
2. `make lint` (`qmllint-qt6 …`) clean — **zero warnings**. The `i18n*`/`Plasmoid`
   `KLocalizedContext` globals qmllint can't statically resolve are declared in
   `./.contextProperties.ini` (so they no longer flag `unqualified`, while a genuine unqualified
   access still does — see "Internationalization (i18n)"). A `DBus.*` constructor may print an
   `unresolved-type` info on some qmllint versions (runtime JS types the plugin provides) — benign.
   Then `make lint-js` (ESLint, strict, `--max-warnings 0`) clean for the JS tier — needs
   `npm install` once (see "Lint/format before installing"). `make verify` runs check + lint + lint-js.
3. `make dev && make test` — watch the `plasmawindowed` terminal and
   `journalctl --user -f -t plasmashell` for QML errors/warnings.
4. `make restart` — confirm it works in a real panel (some failures only show in-shell).
5. Sanity-check reactivity: switching desktops via keyboard (e.g. Ctrl+F1/F2) must update the
   widget, proving the `VirtualDesktopInfo` binding is live and not cached.

**Debugging notes:**
- **`plasmawindowed` renders the applet's _full_ representation, not the compact one.** With a
  compact-only widget it shows nothing, so it falsely "loaded clean." Since the dots are now the
  full representation it *is* a valid smoke test — but the real placement test is a panel.
- **`console.log` from a plasmoid is filtered out of the journal; `console.warn`/`console.error`
  come through.** Use `console.warn` for ad-hoc debugging, under `journalctl --user -t plasmashell`.
- **plasmashell caches the QML per shell session.** Editing the symlinked package is not enough —
  `make restart` (or remove/re-add the widget) to load changes. `rm -rf ~/.cache/plasmashell/qmlcache`
  if a stale compile is suspected.
- To tell "applet didn't load" from "representation didn't render," log from the root
  `Component.onCompleted` (always runs if `main.qml` loads) vs the representation's `onCompleted`.

## User Conventions

- Always call big files/objects/functions **'monolithic'** — no synonyms.
