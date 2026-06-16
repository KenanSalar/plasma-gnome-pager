# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **GNOME-style virtual-desktop pager** for KDE Plasma 6 panels — small dots with a sliding
"pill" over the current workspace. It is a **pure-QML KPackage plasmoid** (no compiled C++,
no build step): plasmashell interprets the QML directly. "Building" means installing or
symlinking the `package/` directory; there is no compiler and no automated test suite.

**Current state: scaffold.** Structure is fully wired and the empty widget loads, but the
behavior is unimplemented. Files carry `TODO(impl)` markers. The ordered implementation
roadmap is in `TODO.txt` (Milestones 0–7) — consult it to know what to build next and in what
order ("make it work → look right → configurable → robust → ship").

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

**Representation model** — a panel pager renders inline, so the widget *is* its compact
representation: `main.qml` sets `preferredRepresentation: compactRepresentation` and
`compactRepresentation: WorkspaceIndicator {}`. `main.qml` (root `PlasmoidItem`) owns the data
sources, DBus helpers, and contextual actions; `WorkspaceIndicator.qml` lays out the dot strip
+ sliding pill; `WorkspaceDot.qml` is one dot.

**Config flow** — three files must agree:
- `package/contents/config/main.xml` (KConfigXT schema) — each `<entry name="X">` becomes
  `plasmoid.configuration.X`, read live and reactive in the widget.
- `package/contents/config/config.qml` — `ConfigModel` listing the settings categories.
- `package/contents/ui/config/*.qml` — the settings pages, two-way bound via
  `property alias cfg_<key>: control.value` where `<key>` matches the `main.xml` entry exactly.
- **Gotcha:** `ConfigCategory.source` paths resolve relative to `contents/ui/`, which is why
  config *pages* live in `contents/ui/config/` while the schema/categories live in
  `contents/config/`. Mixing this up yields an empty settings dialog. Defaults in `main.xml`
  apply even before the settings UI is built, so the widget can read config keys during early
  milestones.

Widget id (also the install folder name): `com.github.kenansalar.plasma-gnome-pager`.

## Commands

```bash
make dev        # symlink package/ -> ~/.local/share/plasma/plasmoids/<id> for live editing
make test       # plasmawindowed <id> — run standalone; QML errors print to the terminal
make restart    # kquitapp6 plasmashell && kstart plasmashell — reload the real panel
make dev-undev  # remove the dev symlink
make install / make update / make uninstall   # kpackagetool6 install/upgrade/remove
```

**Lint/format before installing** (the rules say `qmllint`/`qmlformat`, but on this Fedora KDE
system those names are **not** on `PATH` — use the `-qt6` suffix or the qt6 libexec path):

```bash
qmllint-qt6 package/contents/ui/*.qml package/contents/ui/config/*.qml   # treat warnings as errors
qmlformat-qt6 -i package/contents/ui/*.qml                                # or /usr/lib64/qt6/bin/qmllint
```

`qmllint` is the primary safety net — it flags the removed/renamed Plasma 6 symbols and
private-import mistakes that `robustness.md` warns about and that otherwise fail silently at
runtime on a new Plasma version.

## Verifying a change

There are no unit tests. The per-milestone verification loop (see `TODO.txt`) is:

1. `qmllint-qt6 …` clean (no warnings).
2. `make dev && make test` — watch the `plasmawindowed` terminal and
   `journalctl --user -f -t plasmashell` for QML errors/warnings.
3. `make restart` — confirm it still works in a real panel (some failures only show in-shell).
4. Sanity-check reactivity: switching desktops via keyboard (e.g. Ctrl+F1/F2) must update the
   widget, proving the `VirtualDesktopInfo` binding is live and not cached.
