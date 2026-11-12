# CLAUDE.md

Plasma Gnome Pager (`com.github.kenansalar.plasma-gnome-pager`), a GNOME-style virtual-desktop
pager for KDE Plasma 6 panels: one dim dot per desktop, the current one grown into a highlighted
pill. Pure QML on Qt 6 and KF6 Kirigami, with its decisions in two JavaScript modules;
plasmashell interprets the package as it is, so there is no build step. `main.qml` is the
only file that touches the Plasma session: it reads the settings and the desktops and passes plain
values down to components that load headless. Desktops are read from
`TaskManager.VirtualDesktopInfo` and written through KWin's DBus, fire and forget, the result
coming back through the same bindings.

## Where things go

Rules load only when Claude *reads* a file their `paths:` glob matches, never on a grep hit or a
failing test, so this table finds them. A rule missed where needed gets a wider glob, never a copy
here.

| file | covers |
|------|--------|
| `.claude/rules/robustness.md` | the import surface and what each import is for, what KF6 removed, detecting APIs newer than 6.0, degrading to the global answer, DBus discipline, checking after an upgrade |
| `.claude/rules/plasmoid.md` | representations and their `Layout.*` hints, `Screen.*` on the placed item, context actions, the popup dialog, `metadata.json` |
| `.claude/rules/virtual-desktops.md` | the `VirtualDesktopInfo` members, per-screen current desktop, the reorder bindings, the KWin and kglobalaccel call shapes, checking a call with `busctl` |
| `.claude/rules/windows.md` | the one `TasksModel` and its three outputs, matching a window's screen, dynamic workspaces, the coordinator's election and setting sync |
| `.claude/rules/dot-strip.md` | the reflow look, natural against effective sizes, neutralising a feature at the input, the pinned strip, the row grid and orientation, input and hover |
| `.claude/rules/settings.md` | the page base and `configKeys`, `cfg_` names, combo indices, the shared slider, hint and section controls, greying dependent rows |
| `.claude/rules/qml.md` | QML as this tree writes it: files and imports, the JavaScript as ES modules, properties and bindings, connections, what qmllint can't see, positioners and `Loader`s |
| `.claude/rules/kirigami.md` | units, durations, theme colours, settings-page forms |
| `.claude/rules/qml-performance.md` | keeping the always-on widget cheap: bindings, the window model's churn, drawing, dropping hidden items, animation |
| `.claude/rules/ci-packaging.md` | a new QML module in CI, where the version and the plugin Id are spelled, compiling catalogs before packing, what ships, where oxfmt takes its indentation |
| `.claude/rules/code-style.md` | writing code and comments, the comment budget and its audit, the doc-comment format for each language |
| `.claude/rules/testing.md` | testing practice: the ISTQB principles, case design, levels, QtTest organisation, the `main.xml` walk, timing and events, assertions, doubles and seams, naming |
| `tests/README.md` | the unit, integration and manual e2e tiers, what each one mocks, adding a test |

- **A fact goes at its anchor**, the comment on the code it constrains. A coupling across files
  goes in a rule, and a prohibition violable from anywhere here.
- **File headers and doc comments are the most current tier: link, don't restate.** Two copies of
  one argument is the failure mode, and a rule restating a comment holds the copy to delete.
- **A code comment never cites a rule or this file.** Every comment states its own reason; the
  pointing runs the other way, a rule naming the code.
- **Re-read `.claude/rules/code-style.md` before writing comments, and audit each one a change
  adds against its "Auditing a change" before reporting the work done**: only this file survives
  `/compact`. Explain why, never what; be terse; never narrate or write a changelog.

## Commands

```bash
make dev          # compile catalogs, symlink package/ into ~/.local/share/plasma/plasmoids/
make test         # plasmawindowed: the widget standalone, QML errors in the terminal
make restart      # reload the real panel; plasmashell caches QML, so an edit alone shows nothing
make lint         # qmllint-qt6 over the UI, config pages and tests; a warning fails it
make lint-js      # oxlint over the .mjs modules; `npm ci` once first
make format       # oxfmt over the JS, JSON and YAML; format-check fails on a file it would change
make check        # headless qmltestrunner-qt6; check-unit / check-integration run one tier
make verify       # lint + lint-js + format-check + check: what CI runs
make messages     # re-extract the .pot from the QML and msgmerge every po/*.po
make package      # dist/<id>-<version>.plasmoid
QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 qmltestrunner-qt6 -input tests/unit/tst_logic.qml
```

The Qt tools carry Fedora's `-qt6` suffix; `CONTRIBUTING.md` says how to match it elsewhere and
which packages a fresh system needs. QML errors from the panel reach
`journalctl --user -f -t plasmashell`, which drops `console.log`, so debug with `console.warn`.
`rm -rf ~/.cache/plasmashell/qmlcache` clears a stale compile that `make restart` didn't.

## Prohibitions violable from anywhere

### Robustness

- **Public QML imports only, from `robustness.md`'s table, never `org.kde.plasma.private.*`, and no
  compiled C++ plugin.** Private modules and C++ ABIs break on Plasma, Qt and KF6 point releases,
  and surviving those is why this widget exists.
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
- **A KWin write is a pure `*Spec` builder in `logic.mjs`, pinned by value in `tst_logic.qml`**, and
  goes out through `main.qml`'s `dispatch`.
- **Branching logic goes in `logic.mjs`**, free of Plasma, Qt and i18n so `tst_logic.qml` runs it
  headless. The QML calls it and stays thin.
- **`logic.mjs` holds no mutable state**: every pager in the process shares one instance of it.
  State shared across pagers lives only in `coordinator.mjs`.
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

## Internationalization

- **Every user-visible string is wrapped in `i18n`, `i18nc`, `i18np` or `i18ncp` in the QML.**
  `logic.mjs` returns raw strings for `main.qml` to format, since the `i18n*` globals don't exist
  under qmltestrunner.
- **Never translate DBus identifiers, KWin shortcut names (`"Overview"`, `"Grid View"`), KCM
  module names, icon names or theme tokens.**
- **A changed string means `make messages`, then committing only the changed `po/*.po`.** The
  `.pot` and the `.mo` under `package/contents/locale/` are generated and ignored.
- **`metadata.json`'s `Description` is translated by `Description[<lang>]` keys**, not the
  catalog. `Name` is the product name and stays untranslated.

## Testing and CI

- **A change to `main.qml`, the settings pages or `RenameDialog.qml` is checked in the shell**:
  `make dev`, `make test` and `make restart`, then switching desktops by keyboard to see the
  bindings follow. Nothing headless can build them.
- **PRs go into `main`, and a release is a pushed `v*.*.*` tag equal to `metadata.json`'s
  `KPlugin.Version`, never a merge.** `publish.yml` leaves a draft that is published by hand; the
  KDE Store upload is manual too.
- **The required check is "Lint & headless tests"**, with "Oxlint (JS tier)" and "Oxfmt (format
  check)" beside it.
- **Conventional Commits, PR titles included**: the release notes are generated from merged PR
  titles. Branches are `feat/`, `fix/`, `refactor/`, `perf/` or `docs/`, with the issue number
  ahead of the slug (`feat/23-match-desktop-grid-orientation`).

## Known gaps

- **A desktop reorder doesn't re-notify `desktopIds` or `desktopNames`**: libtaskmanager emits
  only `desktopPositionsChanged` (Plasma 6.5+), and `virtual-desktops.md` says what a binding on
  either list owes. Check one in the shell with an Overview Grid desktop drag.
- **KWin drops a mistyped DBus call, and a `createDesktop` with an empty name, without an error.**
  Nothing reaches the journal and nothing changes, which is why the specs are pinned by value.
- **There is no public per-output switch.** A switch sets KWin's one global `current`, which KWin
  routes to the active output; the stock pager's `requestActivateOnScreen` is C++-only.
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
