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
the windows open on that desktop), add/remove desktops, form-factor (vertical-panel) handling, the
settings UI, and robustness hardening (per-screen current desktop, scale-to-fit, transient-state
guards) are built; the remaining work is packaging/release. This file and
`.claude/rules/*` describe how the code is built, not the schedule or milestone roadmap (that
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
attached property (KWin connector name, e.g. `DP-1`) and calls
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
> and never refresh — there is no property to depend on. So `WorkspaceIndicator.currentDesktop` is a
> mutable source-of-truth property recomputed in `updateCurrentDesktop()`, driven by a
> `Connections { target: virtualDesktopInfo }` on those signals (plus `onScreenNameChanged` /
> `onVirtualDesktopInfoChanged` / `Component.onCompleted`); `activeIndex` and each dot's `active`
> bind off it, staying declarative. The integration mock duck-types the same method+signal (the
> default models the feature OFF: per-screen == global, so every pre-existing test stays valid), and
> `tst_logic.qml` covers `resolveCurrentDesktop`.

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
down as a plain `vertical` bool), and a multi-row grid mirroring KWin's `desktopLayoutRows`;
`WorkspaceDot.qml` is one element (a dot that morphs into the highlighted capsule when active — see
the Visual model below).

> **Gotcha (learned the hard way) — advertise width via `Layout.*`, not `implicitWidth` alone.**
> An inline full-representation that sets *only* `implicitWidth`/`implicitHeight` gets a **default
> square cell** (≈ panel thickness) from the panel: the centred dot `Row` then overflows its tiny
> cell and draws **on top of the neighbouring widgets**, and only that small cell is interactive
> (the dots outside it are dead to clicks/scroll/right-click). Fix: the representation root
> (`WorkspaceIndicator`) advertises its content extent via `Layout.minimum`/`preferred`/`maximum`
> on **both** axes (needs `import QtQuick.Layouts`). The MAJOR (line) axis — width on a horizontal
> panel, height on a vertical one (`vertical`) — pins `preferred == max == naturalStripLength` but
> drops `min` to a smaller `floorStripLength` so the panel can **compress** the strip; when it does,
> the dots scale down to fill the allocation (scale-to-fit, M6 — see the scale-to-fit gotcha below).
> The CROSS axis carries the line(s) (`min == preferred == naturalCrossThickness`) with its
> **maximum reset to `-1`** (Qt's unconstrained `+∞`) so the panel stretches it to the panel
> thickness and the centred grid sits in the middle. Asserted by
> `tst_workspaceindicator.qml::{test_advertisesWidthViaLayout,test_verticalAdvertisesHeightViaLayout}`.
> Do **not** wrap the representation root in another item (e.g. a `ToolTipArea`) that doesn't
> forward these `Layout` hints — that reintroduces the square cell.

**Visual model — REFLOW: each element morphs dot⇄capsule (no overlay).** Each `WorkspaceDot`
*is* a workspace and renders as a dim circle (`Kirigami.Theme.textColor` @ `inactiveOpacity`,
`dotSize` across) when inactive, and morphs into a longer highlighted **capsule** (the "pill":
`Kirigami.Theme.highlightColor` @ full opacity, `pillWidth` along the major axis) when `active`.
There is **no** separate overlay. Switching morphs two elements at once (old capsule → dot, new dot
→ capsule) and the line reflows between them. **Form factor (M4):** the major axis is horizontal on
a horizontal panel and vertical on a vertical one (`vertical`, from `Plasmoid.formFactor`); the dot
morphs `width` or `height` accordingly (`radius` stays `dotSize/2` so the ends keep stadium-round).
When KWin's grid has more than one row, the strip is several such reflow lines stacked along the
cross axis (mirroring `VirtualDesktopInfo.desktopLayoutRows`) — see the multi-row gotcha below.
Hover brighten (M3) is a *separate* inactive-only state driven by
`containsMouse`; `logic.js::dotOpacity(active, hovered, inactiveOpacity, hoverOpacity)` returns
`1.0` for the active capsule and `hovered ? hoverOpacity : inactiveOpacity` otherwise (so hovering
the active capsule does nothing). This replaced an earlier *sliding overlay pill* — which could not
give GNOME's uniform spacing (a wide overlay needs clearance, forcing wide dot gaps) — and matches
how GNOME and the KDE `compact_pager` actually work.

> **Uniform spacing + reflow — don't reintroduce the overlay or a coupled slot.**
> One uniform `spacing` (`dotSpacing = dotSize * spacingFactor`, default `spacingFactor 0.5`)
> sits between **every** adjacent element, so the pill-to-dot gap equals the dot-to-dot gap (the
> GNOME look). The active element simply grows **in place**; its neighbours are pushed out by the
> line and can never be covered or clipped — so there is **no** `pillOverhang`/`pillEndGap`/`pillX`
> math. This is **not** the previously-rejected *uniform-slot* model (every slot as wide as the
> pill, which spread the dots far apart): here inactive dots stay `dotSize`-tight and only the
> active one is longer. Size is advertised by a **formula** on the major axis (at the natural dot
> size) — `naturalStripLength = perLine > 0 ? pillWidth + (perLine-1)*(dotSize+dotSpacing) : dotSize`
> — and the cross axis carries the lines
> (`naturalCrossThickness = lineCount*dotSize + (lineCount-1)*dotSpacing`),
> not the live positioner extent, so the panel cell stays put during the morph and when no element
> is active (a switch **conserves total length**: the shrinking and growing elements cancel). For a
> single line `perLine == desktopCount` and `lineCount == 1`, recovering the M3 1-D width formula.
> Guarded by `tst_workspaceindicator.qml::{test_uniformSpacing,test_exactlyOneCapsule,
> test_transientStaleNoCapsuleWidthStable,test_gridSizingTwoRows}`. The metric property names
> (`dotSize`, `pillWidthFactor`, `spacingFactor`, `inactiveOpacity`, `hoverOpacity`) match the
> `main.xml` settings keys exactly (see "Config flow" below).
>
> **Scale-to-fit (M6 major axis; cross axis post-M6) — shrink the dots to the allocation on BOTH axes,
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
> live major length with `perLine` and the real `pillWidthFactor` (one capsule + dots); the CROSS fit
> reads the live cross thickness with `lineCount` and **`pillFactor == 1`** (no capsule — every line is
> one dot thick, so it is the exact inverse of `naturalCrossThickness`). It returns `+Infinity` when
> there's nothing to fit (non-positive `available`/`count`/denominator), so the unconstrained axis keeps
> natural and `min` picks the other. The crucial constraint: **the `Layout.*` hints are computed from
> the NATURAL/floor sizes only** (`naturalStripLength`/`floorStripLength`/`naturalCrossThickness`/
> `floorCrossThickness`), never the effective `dotSize` — the fits read the live `width`/`height`, so
> feeding the effective size back into the hints would be a binding loop. The cross-axis `Layout`
> **minimum drops to `floorCrossThickness`** (mirroring the major axis's `floorStripLength`) so a thin
> panel can compress the thickness; preferred stays `naturalCrossThickness`, maximum stays `-1` (free to
> fill the thickness). Everything *downstream* (`pillWidth`, `dotSpacing`, each `WorkspaceDot`, the
> `Grid` spacing) reads the effective `dotSize`, so the whole strip scales in lockstep. Common case (room
> available on both axes): `fitDotSize >= naturalDotSize`, so effective == natural and the look is
> byte-for-byte unchanged. Guarded by `tst_workspaceindicator.qml::{test_scaleDotsShrinkOnNarrowWidth,
> test_scaleDotsUnchangedWhenAmple,test_scaleDotsShrinkOnShortHeightVertical,
> test_scaleDotsShrinkOnThinCrossMultiRow,test_scaleDotsCrossUnchangedWhenAmpleThickness,
> test_scaleDotsShrinkOnThinCrossVertical,test_advertisesWidthViaLayout,
> test_verticalAdvertisesHeightViaLayout,test_gridSizingTwoRows}` +
> `tst_logic.qml::{test_fitDotSize,test_fitDotSizeUnbounded}`.
>
> **Multi-row grid (M4) — mirror KWin, don't add a setting; nested positioners, not a 2-D Grid.**
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

> **Rename — a public `setDesktopName(id, name)` DBus write + a `PlasmaCore.Dialog`, NOT
> `Kirigami.PromptDialog`.** "Rename Current Desktop…" is a `Plasmoid.contextualAction` (gated by the
> `enableRename` key) that renames `vdi.currentDesktop` via `kwinCall(... "setDesktopName", [DBus.string(uuid),
> DBus.string(name)])` (the verified `ss` signature on `org.kde.KWin.VirtualDesktopManager`). It is
> menu-only / current-desktop (no per-dot trigger), so `WorkspaceIndicator`/`WorkspaceDot` are untouched.
> The new name comes back through the live `desktopNames` binding — **no cache** (the read/write split).
> The name is validated by pure `logic.js::sanitizeDesktopName` (trim, reject empty/whitespace → `""`
> no-op sentinel, cap length); unit-tested. Text entry is a **`PlasmaCore.Dialog`** (TextField +
> Cancel/Rename, positioned by `visualParent: root.fullRepresentationItem` + `location: Plasmoid.location`
> + `hideOnWindowDeactivate`, the stock `AppletAlternatives` idiom) **declared directly** with
> `visible:false` — *not* wrapped in a `Loader` (a `Loader` is for `Item`s; a `Dialog` is a top-level
> `Window`, kept cheap by not realising a surface until shown) and *not* `Kirigami.PromptDialog`, whose
> base `Kirigami.Dialog` parents to `applicationWindow().overlay` — **undefined in a plasmoid**, so it
> would clip to the thin panel (robustness.md). The dialog + action + DBus live in `main.qml` (e2e-only).

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

**Window-list tooltip — windows-per-desktop from the PUBLIC `TasksModel`, NOT the private
`PagerModel`.** The tooltip's `subText` is the stock KDE pager's window list ("N Windows:" + a
rich-text `<ul>` of titles + "…and N other windows", a separate "N Minimized Windows:" section),
gated by the `showWindowList` key. The stock pager builds this from a **private** `PagerModel`/
`WindowModel` (`org.kde.plasma.private.pager`) — forbidden (robustness.md, the #1 break cause). We
reproduce the exact *presentation* from the public `org.kde.taskmanager` `TasksModel` + `ActivityInfo`
instead. The split, following the project's data-source-vs-pure-logic rule:
> - **`main.qml` (e2e boundary, not headless-testable)** owns the live model. A `Loader` gated by
>   `showTooltips && showWindowList` (so the always-on model cost is **zero** when the list is off —
>   qml-performance.md) loads a `TooltipAggregator` Item holding ONE unfiltered
>   `TasksModel { groupMode: GroupDisabled; filterByActivity: true }` (one row per window; current
>   activity only). An `Instantiator` materialises the rows so role values can be read **by name**
>   (a C++ `QAbstractItemModel` has no `model.get(i)`); a debounced `Qt.callLater(rebuild)` (driven by
>   the model's `dataChanged`/`onObjectAdded`/`onObjectRemoved` + `vdi.desktopIdsChanged`) snapshots
>   the rows, calls the pure grouping, then wraps each result with `i18ncp`/`i18nc` into the HTML
>   `subText`. The per-desktop strings flow DOWN as a plain `desktopTooltips` array, index-aligned
>   with `desktopIds` (exactly parallel to `desktopNames`): `main.qml` → `WorkspaceIndicator`
>   (`desktopTooltips`) → each `WorkspaceDot.tooltipText` by `globalIndex` → `ToolTipArea.subText`
>   (with `textFormat: Text.RichText`). The sub-components never touch `TasksModel`, so they stay
>   headless-testable.
> - **`logic.js` (pure, unit-tested)** does the grouping/truncation with NO Plasma/i18n deps:
>   `groupWindowsByDesktop(windows, desktopIds)` → per-desktop `{ visible:[title…], minimized:[title…] }`
>   (a window belongs to a desktop when `isWindow && (onAll || desktops.indexOf(uuid) !== -1)`);
>   `windowListMaximum(count)` (the stock rule: 4, but all 5 when exactly 5); `sanitizeHtml` (escapes
>   `<>&'"` and the no-break space ` ` — **not** the ordinary space, which must still wrap). i18n
>   formatting stays in `main.qml` because `i18n*` is a plasmoid global, absent under `qmltestrunner`.
>
> **Gotcha — `as`-cast dynamic `Loader.item`/`Instantiator.objectAt()` to a NAMED inline component, or
> qmllint flags `missing-property`.** `Loader.item` and `Instantiator.objectAt(i)` are typed `QObject`,
> so reading a dynamic property off them (`tooltipLoader.item.desktopTooltips`, `o.display`) warns. Fix
> exactly like the stock pager's `itemAt(i) as WindowDelegate`: declare the loaded item and the row as
> named inline components (`component TooltipAggregator: Item {…}`, `component WindowRow: QtObject {…}`)
> and cast — `(tooltipLoader.item as TooltipAggregator).desktopTooltips`,
> `winInstantiator.objectAt(i) as WindowRow`. Capitalised `TasksModel` roles (`VirtualDesktops`,
> `IsOnAllVirtualDesktops`, `IsMinimized`, `IsWindow`) aren't valid lowercase identifiers, so they can't
> be `required property`s — read them off the var `model` inside `WindowRow`; only the lowercase
> `display` (the title) is a required property. Normalise `VirtualDesktops` with `.map(x => String(x))`
> before comparing to `desktopIds` (the role elements may be UUID-variant wrappers, not plain strings).
> Guarded by `tst_logic.qml::{test_windowListMaximum,test_sanitizeHtml,test_groupWindowsByDesktop}` +
> `tst_workspaceindicator.qml::test_dotsReceiveTooltipText` (and short-array/multi-row variants) +
> `tst_workspacedot.qml::{test_tooltipShowsSubText,test_tooltipTextFormatIsRichText}`. The aggregator
> itself is e2e-only (verify in-shell).

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
behaviour — `enableScroll`, `scrollWrap`, `showTooltips`, `showWindowList` (the window list in the
tooltip; only applies when `showTooltips` is on — the `ConfigGeneral` checkbox is `enabled:` off it),
`enableAddRemove`, `enableRename` (the "Rename Current Desktop…" menu entry), `animationDuration`;
appearance — `dotSize`, `spacingFactor`, `pillWidthFactor`, `inactiveOpacity`, `hoverOpacity`,
`followThemeColors`, `activeColor`, `inactiveColor`. The settings UI is two files that must agree
with the schema:
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
  always-on widget), so a break there cannot kill the running pager. The config pages + `config.qml`
  are **e2e-only** (the dialog needs `org.kde.plasma.configuration`), so they are not in the headless
  test harness — `make lint` covers them, but verify behaviour in-shell.
- **Defaults button:** the Plasma applet config dialog footer is only Apply/Discard/Cancel — it has
  **no** Defaults button. `ConfigPageBase` adds one **once** as a header `Kirigami.Action` (gated by
  `root.isModified`, firing `root.defaultsRequested()`); each derived page fulfils that contract by
  **binding** `isModified` (any `cfg_<key>` differs from its `cfg_<key>Default`) and **handling**
  `onDefaultsRequested` (reset every `cfg_<key>` to its `cfg_<key>Default`). `cfg_<key>Default` is a
  property the dialog injects from the schema default — declared on the page with no initializer so
  `main.xml` stays the single source of truth.
- **Gotcha:** `ConfigCategory.source` paths resolve relative to `contents/ui/`, which is why
  config *pages* live in `contents/ui/config/` while the schema/categories live in
  `contents/config/`. Mixing this up yields an empty settings dialog.

> **Gotcha — reserve a config slider's value-label width or the slider jitters.** A slider in a
> `RowLayout` with a `Layout.fillWidth` track plus a value read-out `Label` makes the track/handle
> appear to jump while dragging, because the label's implicit width changes with the value
> (`"45%" → "100%"`, and even `"1.0× dot" → "4.0× dot"` since digits differ in a proportional font),
> reflowing the row. `ConfigSlider.qml` fixes this with a single `format` closure (value → display
> string): each call site supplies `format` once, and the component uses it for BOTH the live
> read-out AND the reserved width — pinning the label (via `TextMetrics`) to the wider of
> `format(from)`/`format(to)` + a small buffer. Because every formatter here is monotonic in string
> width with magnitude AND the sentinel sliders put their special text at `from` (`0 → "Default"`),
> reserving over the two extremes bounds every value between them (no separate `widestText` to keep
> in sync). `snapMode` defaults to `SnapAlways` in the component; callers just set `from/to/stepSize`
> + `format`.

> **Gotcha — theme/HiDPI-derived defaults use a `0 = auto` sentinel.** A KConfigXT default is a
> fixed literal, so it cannot be `Kirigami.Units.iconSizes.small / 2` or `Kirigami.Units.longDuration`
> — baking a px/ms literal would lose HiDPI/theme scaling (kirigami.md). Instead `dotSize` and
> `animationDuration` default to `0` meaning "auto", and the sentinel is resolved **inside the
> components** (the indicator's `dotSize`, and `Logic.effectiveDuration` for the morph) — NOT in
> `main.qml`, because the components are the headless-tested rendering layer (`main.qml` does import
> Kirigami, but only for the rename dialog's spacing, and is not itself headless-testable).
> `effectiveDuration` also
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

## Internationalization (i18n)

All user-visible strings are wrapped at the call site in `i18n`/`i18nc`/`i18np`/`i18ncp` (with
`@…` context comments on the tooltip strings) — they live **only in the QML** (`main.qml` + the
config pages). `logic.js` is deliberately **i18n-free**: it keeps strings raw and the formatting
(i18n + HTML) happens in `main.qml`, because `logic.js` is headless-unit-tested where the `i18n*`
globals don't exist (see "Config flow"/the window-list section). So extraction scans `*.qml` only.

- **Domain (auto-bound):** the Plasma runtime sets the QML `KLocalizedContext` domain to
  `plasma_applet_<KPlugin.Id>` = `plasma_applet_com.github.kenansalar.plasma-gnome-pager`, so the
  bare `i18n(...)` calls resolve to our catalog with **no** explicit domain wiring in QML.
- **Source vs. artifact:** `po/<domain>.pot` (template) + `po/<lang>.po` (per-language) are the
  committed **source of truth**; the compiled `po/<lang>.po → package/contents/locale/<lang>/`
  `LC_MESSAGES/<domain>.mo` catalogs are **generated** (gitignored). `kpackagetool6` ships the
  package tree verbatim and does **no** compilation, so the `.mo` must exist under `package/`
  before packaging — `make i18n` compiles them and `install`/`update`/`dev` depend on it.
- **Workflow:** `make messages` extracts via `xgettext` (ki18n keyword set, so contexts + plural
  forms come through) into the `.pot` and `msgmerge`s every `.po`; `make i18n` compiles each `.po`
  (`msgfmt --check`) into the package. Add a language by `msginit --locale=<ll>` from the `.pot`,
  translating, and `make i18n` (README "Translations" has the recipe). Shipped: English (source) +
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

## Verifying a change

There is a headless QML test harness (`tests/`, run with `make check`) split into two tiers:
**unit** (`tests/unit/`, one component in isolation, e.g. `WorkspaceDot`) and **integration**
(`tests/integration/`, components composed + reactive wiring, e.g. `WorkspaceIndicator` driven
by a `QtObject` mock standing in for `VirtualDesktopInfo`). Run a single tier with
`make check-unit` / `make check-integration`. It can only cover the Kirigami-only components;
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
