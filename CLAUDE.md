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
and switches on click; a wider highlight "pill" slides over the active dot. Not built yet:
scroll/hover, add/remove desktops, form-factor (vertical-panel) handling, the settings UI, and
robustness hardening. The ordered roadmap — what to build next, in what order — lives in
`TODO.txt`; this file and `.claude/rules/*` describe how the code is built, not the schedule.

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
`WorkspaceIndicator.qml` lays out the dot strip + sliding pill; `WorkspaceDot.qml` is one dot.

**Visual model — one sliding pill overlay, not per-dot highlight.** The active desktop is shown
by a **single** overlay `Rectangle` (the "pill", `Kirigami.Theme.highlightColor`) that
`WorkspaceIndicator` draws on top of the active dot and slides via `Behavior on x`. Every
`WorkspaceDot` is always the same dim circle (`Kirigami.Theme.textColor` @ `inactiveOpacity`);
`WorkspaceDot.active` is kept (used by tests, reserved for the planned hover state) but does not
change the dot's look.

> **Decoupling — pill length and dot spacing are independent; don't re-couple them.**
> `pillWidthFactor` sets the pill length relative to a dot, and `dotSpacing` is **derived**
> (`pillOverhang + pillEndGap`, where `pillOverhang = (pillWidth - dotSize) / 2`) so a longer
> pill keeps a constant clearance to its neighbours and **never covers them**, while the dots
> stay tight. An earlier *uniform-slot* layout (each dot's slot as wide as the pill) coupled the
> two, so a longer pill forced wider dot spacing — do not reintroduce it. The indicator reserves
> a half-pill `pillOverhang` at each end so the pill never clips. The metrics (`dotSize`,
> `pillWidthFactor`, `inactiveOpacity`, `pillEndGap`) are named to match the keys the settings UI
> will expose.
> `tests/integration/tst_workspaceindicator.qml::test_pillDoesNotCoverNeighbours` guards the
> no-overlap invariant.

> **Gotcha — animate the first *placement*, not the first frame.** The pill slide is gated by a
> `slideEnabled` latch flipped via `Qt.callLater` once `activeIndex` is first valid, so the pill
> **jumps** to the right desktop on shell reload (even when `VirtualDesktopInfo` populates a
> frame late) and only later switches animate. The `Behavior` is also guarded against
> `Kirigami.Units.longDuration === 0` (reduce-animations) so motion becomes an instant jump.

> **Gotcha (learned the hard way) — a `fullRepresentation` is mandatory.** A Plasma 6
> applet that defines **only** a `compactRepresentation` (no `fullRepresentation`) instantiates
> **no representation at all**: `compactRepresentationItem`/`fullRepresentationItem` stay `null`,
> nothing renders, `expanded` is stuck `true`, and there is **no error** in the journal — the
> widget just silently shows nothing. The moment a `fullRepresentation` exists, the compact one
> instantiates too. The working idiom for a standalone inline widget: make the content the
> `fullRepresentation` and set `preferredRepresentation: fullRepresentation` so it always shows
> inline (never a popup, never the default compact icon). Confirmed against
> develop.kde.org/docs/plasma/widget ("display widget directly in panel").

**Config flow (not present yet)** — the widget currently reads **no**
`plasmoid.configuration.*` keys, so the config subsystem was removed as unused scaffold
(YAGNI). When settings are wired to behaviour, re-create it as three files that must agree:
- `package/contents/config/main.xml` (KConfigXT schema) — each `<entry name="X">` becomes
  `plasmoid.configuration.X`, read live and reactive in the widget.
- `package/contents/config/config.qml` — `ConfigModel` listing the settings categories.
- `package/contents/ui/config/*.qml` — the settings pages, two-way bound via
  `property alias cfg_<key>: control.value` where `<key>` matches the `main.xml` entry exactly.
- **Gotcha:** `ConfigCategory.source` paths resolve relative to `contents/ui/`, which is why
  config *pages* live in `contents/ui/config/` while the schema/categories live in
  `contents/config/`. Mixing this up yields an empty settings dialog. Defaults in `main.xml`
  apply even before the settings UI is built, so the widget can read config keys as soon as the
  schema exists.

Widget id (also the install folder name): `com.github.kenansalar.plasma-gnome-pager`.

## Commands

```bash
make dev        # symlink package/ -> ~/.local/share/plasma/plasmoids/<id> for live editing
make test       # plasmawindowed <id> — run standalone; QML errors print to the terminal
make restart    # kquitapp6 plasmashell && kstart plasmashell — reload the real panel
make check      # all headless QML tests (unit + integration): QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input tests/<tier>
make check-unit / make check-integration   # run a single tier (tests/unit, tests/integration)
make lint       # qmllint-qt6 package/contents/ui/*.qml
make dev-undev  # remove the dev symlink
make install / make update / make uninstall   # kpackagetool6 install/upgrade/remove
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
(`logic.js` + `tests/unit/tst_logic.qml`) that needs no Plasma deps. The verification loop
(also in `TODO.txt`) is:

1. `make check` — all tiers green (offscreen `qmltestrunner-qt6`; non-zero exit on failure).
2. `make lint` (`qmllint-qt6 …`) clean (no warnings). Two warnings are **expected non-defects**
   and can be ignored: `i18n(...)` flagged `unqualified` (a plasmoid global) and any `DBus.*`
   constructor flagged `unresolved-type` (runtime JS types the plugin provides).
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
