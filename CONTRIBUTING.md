# Contributing

I maintain this in my spare time, and bug reports, translations, and patches are all welcome. This
file covers what isn't obvious from the README, which already has the [development
loop](README.md#development) and the [translation recipe](README.md#translations).

If you'd like to help but don't write QML: translate the widget into a language it doesn't ship
yet, send a screenshot for the README, or reproduce someone else's bug report. Multi-monitor,
vertical panels, and fractional scaling are where this widget breaks — someone running `main` on
hardware I can't test is worth more to me than most patches.

## Before you build something

Open an issue before writing a feature. I review everything here myself and my time is limited, so
a short conversation up front beats a weekend of work I end up declining. Typos, doc fixes,
translations, and small bug fixes don't need this — just send them.

What I'm likely to decline is anything that widens the widget past being a pager: it shows virtual
desktops and switches between them, and window management or system monitoring belongs elsewhere.

## Pull requests

Open yours against `main` — it's the only long-lived branch, and merging ships nothing on its own:
a release is a pushed `v*.*.*` tag.

Branch names follow the type of the work — `feat/`, `fix/`, `refactor/`, `perf/`, `docs/` — with
the issue number in front of the slug where there is one, like
`feat/23-match-desktop-grid-orientation`.

## Getting set up

There's no build step — plasmashell interprets the QML directly, so "building" means symlinking the
package and reloading the shell. You do need three things a KDE install doesn't pull in on its own:

```bash
sudo dnf install qt6-qtdeclarative-devel gettext nodejs npm   # Fedora
npm ci                                                        # once, for ESLint
```

`qt6-qtdeclarative-devel` is what carries `qmllint-qt6` and `qmltestrunner-qt6`; gettext is needed
even if you never touch a `.po`, because `make dev` compiles the catalogs.

The `-qt6` suffix is a Fedora naming habit and the Makefile calls the tools by it. Elsewhere
they're unsuffixed — Arch ships them in `qt6-declarative`, Debian and Ubuntu in
`qt6-declarative-dev-tools` alongside `qml6-module-qttest` — usually under `/usr/lib/qt6/bin`
(`ls /usr/lib/qt6/bin` to check). Link them into your `PATH` under the names the Makefile wants:

```bash
ln -s /usr/lib/qt6/bin/qmllint       ~/.local/bin/qmllint-qt6
ln -s /usr/lib/qt6/bin/qmltestrunner ~/.local/bin/qmltestrunner-qt6
```

With that in place, the loop is:

```bash
make dev      # symlink package/ into ~/.local/share/plasma/plasmoids
make test     # run it standalone; QML errors print to the terminal
make restart  # reload the panel — plasmashell caches QML, so editing alone isn't enough
```

The rest of the targets are in the [README](README.md#development).

## Before you push

```bash
make verify
```

That runs lint, lint-js, and the headless tests — exactly what CI runs. Both linters treat
warnings as errors, so a stray unused property fails the build; running it locally saves a
round-trip. On GitHub the required check is **Lint & headless tests**; **ESLint (strict, JS tier)**
runs beside it, and I'll ask you to fix that one too.

If your PR shows no checks at all, that isn't your fault — a new contributor's first workflow run
waits for me to approve it.

## Two rules that aren't negotiable

**Public QML imports only — never `org.kde.plasma.private.*`. And no compiled C++ plugin.**

This widget exists because other GNOME-style pagers keep breaking on Plasma point releases, and
those two things are why. Private modules carry no stability guarantee and are rebuilt in lockstep
with plasmashell; a C++ plugin links against Qt and KF6 ABIs and stops loading the moment they're
upgraded. This one survived 6.6 → 6.7 untouched, and I'd like to keep it that way. If a feature
looks like it needs a private import, there's almost always a public equivalent in
`org.kde.taskmanager` or on KWin's DBus interface.

In practice that fixes the import surface to this, and adding to it is a conversation:

```qml
import QtQuick
import QtQml                                  // Instantiator, in the window aggregator
import QtQuick.Layouts
import QtQuick.Controls as QQC2               // config pages only
import org.kde.plasma.plasmoid                // PlasmoidItem, the Plasmoid attached property
import org.kde.plasma.core as PlasmaCore      // Types, Action, ToolTipArea
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.configuration           // ConfigModel, in contents/config/config.qml
import org.kde.plasma.workspace.dbus as DBus  // the KWin DBus writes
import org.kde.kirigami as Kirigami           // Units, Theme, Icon, FormLayout
import org.kde.taskmanager as TaskManager     // VirtualDesktopInfo, TasksModel
import org.kde.kcmutils as KCM                // opening a System Settings page
```

The settings pages get a little more latitude — `org.kde.kquickcontrols` for the colour buttons —
because the config dialog is loaded on demand, so a break there can't take the running panel with
it. Nothing the always-on widget instantiates gets that leeway.

Imports are un-versioned on Plasma 6: `import QtQuick`, not `import QtQuick 2.15`. And if you're
adapting code from a Plasma 5 widget or an older tutorial, much of what it reaches for no longer
exists — `PlasmaCore.Units` is now `Kirigami.Units`, `PlasmaCore.Theme` is `Kirigami.Theme`,
`PlasmaCore.IconItem` is `Kirigami.Icon`, and the root item is a `PlasmoidItem` rather than an
`Item`. `make lint` catches the renamed symbols. The root item it can't — `Item` is still a valid
QML type, so that one fails silently: the applet loads, renders nothing at all, and puts nothing in
the journal.

## Writing the code

Size and space everything with `Kirigami.Units`, and take colours from `Kirigami.Theme` unless the
user has opted into custom ones — hardcoded pixels look wrong under fractional scaling.

Put branching logic in `package/contents/ui/logic.js` rather than inside a QML binding. It's a
pure `.pragma library` with no Plasma dependencies, so it can be unit-tested, and that's where
most of the coverage lives. Wrap user-visible strings in `i18n()` and run `make messages`
afterwards.

New behaviour should come with a test, named `tst_<thing>.qml` — `qmltestrunner` finds nothing
else. One component in isolation goes in `tests/unit/`, components wired together in
`tests/integration/`; [tests/README.md](tests/README.md) covers the split and the mocks. `main.qml`
needs a live plasmashell and KWin, so changes there are verified through the `make dev` →
`make test` → `make restart` loop instead.

Virtual desktops have a read/write split worth knowing before you touch them. **Read** state from
`TaskManager.VirtualDesktopInfo` and bind to it — it updates whichever way the desktop changed, a
keyboard shortcut or another pager included, so a cached index only drifts out of sync. **Write**
through KWin's DBus interface, which is async fire-and-forget: you issue the call and let
`VirtualDesktopInfo` report the result back. Desktops are keyed by UUID, never by index, so map a
dot through `desktopIds[i]` rather than counting. The exact call shapes are built in `logic.js`
(`switchSpec`, `addSpec`, `removeSpec`, `renameSpec`) and pinned by tests, because KWin silently
drops a call whose argument types are wrong — no error, nothing happens.

Both of those sources go briefly empty during a desktop add/remove or a shell reload; `desktopIds`
can be `[]` for a frame. Guard every index and UUID before using it. A fair number of the tests
exist only to hold that line.

## Commit messages

Conventional Commits, with an optional scope:

```
feat: add "Filled & ring" pager style
fix: pin the dot strip so multi-row morphs don't drift the dots
fix(i18n): correct punctuation and spacing in the Polish catalog
```

Nothing enforces this — it's the house style. Use it for the PR title too: the release notes are
generated from merged PR titles, so that's the line that ends up in the changelog. If you've
contributed to KDE upstream: this repo doesn't use the `BUG:` footer convention from
invent.kde.org.

## Translations

The [README has the recipe](README.md#translations). A translation PR should contain
`po/<lang>.po`, plus optionally a `Description[<lang>]` key in `package/metadata.json`.

Reviewing one, I check that `msgfmt --check` passes, that nothing is fuzzy or untranslated, and
that the plural-form count matches the language. Punctuation and `%1` placeholders have to mirror
the source string — a dropped colon or a missing `…` shows up in the settings dialog.

## Reporting bugs

Tell me your Plasma version (`plasmashell --version`), your distro, and how you installed the
widget. Panel orientation and monitor layout matter too — several bugs have only ever appeared on
multi-monitor or fractional-scaling setups.

If it misbehaves rather than just looking wrong, the logs are usually the difference between a
report I can fix and one I can't reproduce. From a clone, `make test` prints QML errors straight to
the terminal; if you installed from the KDE Store or a `.plasmoid`, use
`journalctl --user -b -t plasmashell` instead.

## License

Contributions are licensed under GPL-3.0-or-later, matching [the project](LICENSE). There's no CLA
to sign.
