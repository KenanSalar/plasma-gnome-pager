# CLAUDE.md

Plasma Gnome Pager (`com.github.kenansalar.plasma-gnome-pager`), a GNOME-style virtual-desktop
pager for KDE Plasma 6 panels: one dim dot per desktop, the current one morphed into a highlighted
pill. It is a pure-QML KPackage plasmoid (Qt 6, KF6 Kirigami, `X-Plasma-API-Minimum-Version` 6.0)
that plasmashell interprets directly, so there is no build step: "building" means symlinking or
installing `package/`. Branching logic lives in two `.pragma library` JavaScript files, linted by
ESLint 10; the QML is linted by qmllint and tested headless by qmltestrunner.

- **`main.qml` is the only file that touches the Plasma session.** The root `PlasmoidItem` reads
  every setting, owns the `TaskManager.VirtualDesktopInfo`, the KWin DBus writes and the
  context-menu actions, and passes plain values down, which keeps every other component
  headless-testable.
- **Desktops are read from `VirtualDesktopInfo` and written through KWin's DBus.** Bindings read
  the live UUID lists. A switch, add, remove or rename is `dispatch(Logic.<x>Spec(…))`, an async
  fire-and-forget call whose result comes back through those same bindings.
- **`WorkspaceIndicator.qml` is the full representation**, forced inline by
  `preferredRepresentation`. It lays out one `WorkspaceDot` per desktop and handles scrolling,
  handing the size math to `IndicatorMetrics.qml` and this monitor's current desktop to
  `ScreenCurrentDesktop.qml`.
- **`WindowAggregator.qml` holds the one `TasksModel`**, loaded only while the window-list
  tooltip, the occupied-dot markers or dynamic workspaces need it. `Logic.reduceWindowSnapshot`
  turns its snapshot into the tooltip text, a per-screen occupancy for the markers, and a global
  occupancy for `DynamicWorkspacesController.qml`.
- **`coordinator.js` is shared by every pager in the plasmashell process**, since a
  `.pragma library` loads once per engine. Through it only one instance adds or removes desktops,
  and the dynamic-workspaces settings stay one value across panels.

`package/contents/config/main.xml` is the settings schema and `package/contents/config/config.qml`
lists the two pages, which live in `package/contents/ui/config/` because `ConfigCategory.source`
resolves against `contents/ui/`.

## Where things go

A rule with a `paths:` glob loads only when Claude reads a matching file, never on a grep hit or a
failing test, so this table finds them.

| file | covers |
|------|--------|
| `.claude/rules/robustness.md` | the import surface and what each import is for, what KF6 removed, detecting APIs newer than 6.0, degrading to the global answer, DBus discipline, checking after an upgrade |
| `.claude/rules/plasmoid.md` | representations and their `Layout.*` hints, `Screen.*` on the placed item, context actions, the popup dialog, `metadata.json` |
| `.claude/rules/virtual-desktops.md` | the `VirtualDesktopInfo` members, per-screen current desktop, the reorder bindings, the KWin and kglobalaccel call shapes, checking a call with `busctl` |
| `.claude/rules/windows.md` | the one `TasksModel` and its three outputs, matching a window's screen, dynamic workspaces, the coordinator's election and setting sync |
| `.claude/rules/dot-strip.md` | the reflow look, natural against effective sizes, neutralising a feature at the input, the pinned strip, the row grid and orientation, input and hover |
| `.claude/rules/settings.md` | the page base and `configKeys`, `cfg_` names, combo indices, the shared slider, hint and section controls, greying dependent rows |
| `.claude/rules/qml.md` | QML as this tree writes it: files and imports, properties and bindings, connections, casts qmllint needs, positioners and `Loader`s |
| `.claude/rules/kirigami.md` | units, durations, theme colours, settings-page forms |
| `.claude/rules/qml-performance.md` | keeping the always-on widget cheap: bindings, the window model's churn, drawing, dropping hidden items, animation |
| `.claude/rules/ci-packaging.md` | the two PR jobs, the version's one home, the publish workflow, what the `.plasmoid` holds, the ESLint parser |
| `.claude/rules/code-style.md` | writing code and comments, the comment budget and its audit, the doc-comment format for each language |
| `.claude/rules/testing.md` | testing practice: the ISTQB principles, case design, levels, QtTest organisation, the `main.xml` walk, timing and events, assertions, doubles and seams, naming |
| `tests/README.md` | the unit, integration and manual e2e tiers, what each one mocks, adding a test |

- **A fact goes at its anchor**, the comment on the code it constrains. A rule names that code
  rather than restating it, and holds only what crosses files.
- **A code comment never cites a rule or this file**; it states its own reason.
- **Re-read `.claude/rules/code-style.md` before writing comments, and run its "Auditing a
  change" before reporting the work done**: only this file survives `/compact`.

## Commands

```bash
make dev          # compile catalogs, symlink package/ into ~/.local/share/plasma/plasmoids/
make test         # plasmawindowed: the widget standalone, QML errors in the terminal
make restart      # reload the real panel; plasmashell caches QML, so an edit alone shows nothing
make lint         # qmllint-qt6 over the UI, config pages and tests; a warning fails it
make lint-js      # ESLint over logic.js, coordinator.js and tests/shared/*.js; `npm ci` once first
make check        # headless qmltestrunner-qt6; check-unit / check-integration run one tier
make verify       # lint + lint-js + check: what CI runs
make messages     # re-extract the .pot from the QML and msgmerge every po/*.po
make package      # dist/<id>-<version>.plasmoid
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 qmltestrunner-qt6 -input tests/unit/tst_logic.qml
```

- **The Qt tools are `qmllint-qt6`, `qmltestrunner-qt6` and `qmlformat-qt6`** on this Fedora
  system; the unsuffixed names aren't on `PATH`.
- **`.contextProperties.ini` declares the `i18n*` and `Plasmoid` globals** for qmllint. If they
  start warning as unqualified, that file isn't being found; it isn't a code defect.
- **`.pragma library` and `.import` aren't JavaScript**, so `tools/eslint-qml-js-parser.mjs`
  rewrites them to comments before espree parses. The same directives rule out `tsc` and Prettier.
- **QML errors from the panel are in `journalctl --user -f -t plasmashell`**, which filters out
  `console.log`: debug with `console.warn`. `rm -rf ~/.cache/plasmashell/qmlcache` clears a stale
  compile that `make restart` didn't.

## Prohibitions violable from anywhere

### Robustness

- **Public QML imports only, never `org.kde.plasma.private.*`, and no compiled C++ plugin.**
  Private modules and C++ ABIs break on Plasma, Qt and KF6 point releases, and surviving those is
  why this widget exists. `robustness.md` holds the allowlist.
- **What the always-on widget instantiates imports only from that allowlist.** A config page may
  also use `org.kde.kquickcontrols`: the dialog loads it on demand, so a break there can't take
  the panel down.
- **Guard every index and UUID.** `desktopIds`, `desktopNames`, `currentDesktop` and the
  aggregator's arrays go briefly empty, or lag one another, during an add, a remove or a shell
  reload. A `Logic.*Spec` builder returns `null` for such input, and `dispatch(null)` does nothing.
- **No widget setting duplicates a KWin one.** Grid rows, the per-screen current desktop and
  per-screen occupancy follow KWin live, with no key of their own.

### Data flow

- **Only `main.qml` reads `Plasmoid.configuration`, and always as
  `Plasmoid.configuration.<key> ?? Logic.DEFAULTS.<key>`**: a new key can read back `undefined`
  for a frame, and a `bool` turns that into `false`, disabling the feature silently.
- **A new setting is five edits**: its `main.xml` entry, its `Logic.DEFAULTS` mirror
  (`tst_logic.qml` fails when the two drift), the `main.qml` read, the `cfg_<key>` alias and
  `configKeys` entry on its page, and the component property it feeds.
- **A default that depends on the theme or the display scale is `0 = auto` in `main.xml`**,
  resolved inside the component that renders it. A px or ms literal would lose HiDPI scaling.
- **A KWin write is a pure `*Spec` builder in `logic.js`, pinned by value in `tst_logic.qml`**,
  and goes out through `main.qml`'s `dispatch`. `toDBusArg` is the only code that builds a `DBus.*`
  argument; `new DBus.variant` wraps a plain value, never another `DBus.*` wrapper.
- **Branching logic goes in `logic.js`**, free of Plasma, Qt and i18n so `tst_logic.qml` runs it
  headless. The QML calls it and stays thin.
- **`logic.js` holds no mutable state**: every pager in the process shares one instance of it.
  State shared across pagers lives only in `coordinator.js`.
- **Anything a pager draws per monitor reads `WorkspaceIndicator.currentDesktop`**, never
  `vdi.currentDesktop`, which follows whichever monitor switched last when KWin switches desktops
  per screen.
- **Deciding that a desktop is empty counts every screen and every activity**; only what this
  monitor shows in this activity is filtered. KWin has one desktop set for all of them, and
  removing a desktop that only looks empty from here moves another activity's windows (#35).

### QML

- **Animations take their duration from `Logic.effectiveDuration`**, so reduced animations
  (`Kirigami.Units.longDuration === 0`) always make them instant.
- **A popup is a `PlasmaCore.Dialog`, never a `Kirigami.Dialog` or `PromptDialog`**: those parent
  to `applicationWindow().overlay`, which a plasmoid doesn't have, and clip to the panel.

### Internationalization

- **Every user-visible string is wrapped in `i18n`, `i18nc`, `i18np` or `i18ncp` in the QML.**
  `logic.js` returns raw strings for `main.qml` to format, since the `i18n*` globals don't exist
  under qmltestrunner.
- **Never translate DBus identifiers, KWin shortcut names (`"Overview"`, `"Grid View"`), KCM
  module names, icon names or theme tokens.**
- **A changed string means `make messages`, then committing only the changed `po/*.po`.** The
  `.pot` and the `.mo` under `package/contents/locale/` are generated and ignored.
- **`metadata.json`'s `Description` is translated by `Description[<lang>]` keys**, not the
  catalog. `Name` is the product name and stays untranslated.

### Tests

- **A test is `tst_<thing>.qml`**, the only name qmltestrunner finds: one component or the JS tier
  in `tests/unit/`, composed components on `tests/shared/VdiMock.qml` in `tests/integration/`.
- **Any warning fails an indicator test** (`failOnWarning` in `tests/shared/IndicatorTestCase.qml`).
- **A Plasma import added to a tested component has to load under offscreen qmltestrunner**;
  anything needing a live KWin or session bus stays in `main.qml`.
- **`main.qml`, the config pages and `RenameDialog.qml` are e2e-only**: check them with
  `make dev`, `make test` and `make restart`, then switch desktops by keyboard to confirm the
  bindings are live.

### Git and releases

- **PRs go into `main`. A release is a pushed `v*.*.*` tag equal to `metadata.json`'s
  `KPlugin.Version`, never a merge.** `publish.yml` drafts the GitHub release with the
  `.plasmoid`, which is published by hand; the KDE Store upload is manual too.
- **The required check is "Lint & headless tests"**, with "ESLint (strict, JS tier)" beside it.
- **Conventional Commits, PR titles included**: the release notes are generated from merged PR
  titles. Branches are `feat/`, `fix/`, `refactor/`, `perf/` or `docs/`, with the issue number
  ahead of the slug (`feat/23-match-desktop-grid-orientation`).

## Known gaps

- **A desktop reorder doesn't re-notify `desktopIds` or `desktopNames`**: libtaskmanager emits
  only `desktopPositionsChanged` (Plasma 6.5+). `WorkspaceIndicator` and `WindowAggregator`
  re-read on it; a new binding on either list anywhere else keeps the old order until a desktop is
  added or removed. Check one in-shell with an Overview Grid desktop drag.
- **KWin drops a mistyped DBus call, and a `createDesktop` with an empty name, without an error.**
  Nothing reaches the journal and nothing changes, which is why the specs are pinned by value.
- **There is no public per-output switch.** A switch sets KWin's one global `current`, which KWin
  routes to the active output; the stock pager's `requestActivateOnScreen` is C++-only.
- **`currentDesktopByScreenName` is a method with a signal, not a property**, so a binding to it
  evaluates once. `ScreenCurrentDesktop.qml` recomputes it on the signals.
- **`metadata.json`'s `Icon` has to be an icon-theme name.** Add Widgets resolves it only
  through the icon theme, and neither kpackagetool6, the `.plasmoid` nor the KDE Store installs a
  bundled SVG into one. `virtual-desktops` resolves on any theme through KDE's Breeze fallback.
- **Installing from Get New Widgets while `make dev`'s symlink is in place deletes `package/`
  through it**; `git restore package && make i18n` recovers. `make install` and `make update`
  refuse to run while the symlink exists for the same reason.
- **Orca can't announce the dots on Wayland**: its mouse review can't track the pointer, and the
  dots take no keyboard focus. Check accessibility with an AT-SPI tree dump instead.

## User Conventions

- Always call big files/objects/functions **'monolithic'** — no synonyms.
