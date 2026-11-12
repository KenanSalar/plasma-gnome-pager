# Contributing

I maintain this in my spare time, and bug reports, translations and patches are all welcome.

If you'd like to help but don't write QML: translate the widget into a language it doesn't ship
yet, send a screenshot for the README, or reproduce someone else's bug report. Multi-monitor
setups, vertical panels and fractional scaling are where this widget breaks, so someone running
`main` on hardware I can't test is worth more to me than most patches.

## Reporting bugs

Tell me your Plasma version (`plasmashell --version`), your distro, and how you installed the
widget. Panel orientation and monitor layout matter too: several bugs have only ever appeared on
multi-monitor or fractional-scaling setups.

If it misbehaves rather than just looking wrong, the logs are usually the difference between a
report I can fix and one I can't reproduce. From a clone, `make test` prints QML errors straight to
the terminal. If you installed from the KDE Store or a `.plasmoid`, use
`journalctl --user -b -t plasmashell` instead.

## Before you build something

Open an issue before writing a feature. I review everything here myself and my time is limited, so
a short conversation up front beats a weekend of work I end up declining. Typos, doc fixes,
translations and small bug fixes don't need this; just send them.

What I'm likely to decline is anything that widens the widget past being a pager: it shows virtual
desktops and switches between them, and window management or system monitoring belongs elsewhere.

## Getting set up

There's no build step. plasmashell interprets the QML directly, so "building" means symlinking the
package and reloading the shell. You do need three things a KDE install doesn't pull in on its own:

```bash
sudo dnf install qt6-qtdeclarative-devel gettext nodejs npm   # Fedora
npm ci                                                        # once, for oxlint and oxfmt
```

`qt6-qtdeclarative-devel` carries `qmllint-qt6` and `qmltestrunner-qt6`. You need gettext even if
you never touch a `.po`, because `make dev` compiles the catalogs.

The `-qt6` suffix is a Fedora habit, and the Makefile calls the tools by it. Elsewhere they're
unsuffixed and usually live in `/usr/lib/qt6/bin`: Arch ships them in `qt6-declarative`, Debian and
Ubuntu in `qt6-declarative-dev-tools` alongside `qml6-module-qttest`. Link them into your `PATH`
under the names the Makefile wants:

```bash
ln -s /usr/lib/qt6/bin/qmllint       ~/.local/bin/qmllint-qt6
ln -s /usr/lib/qt6/bin/qmltestrunner ~/.local/bin/qmltestrunner-qt6
```

With that in place, the loop is:

```bash
make dev      # symlink package/ into ~/.local/share/plasma/plasmoids
make test     # run it standalone; QML errors print to the terminal
make restart  # reload the panel; plasmashell caches QML, so saving a file isn't enough
```

While that symlink is in place, don't install or update the widget from **Get New Widgets**: it
deletes `package/` through the link, uncommitted work included. Run `make dev-undev` first.

The rest of the targets are in the [README](README.md#development).

## Two rules that aren't negotiable

**Public QML imports only, never `org.kde.plasma.private.*`. And no compiled C++ plugin.**

This widget exists because other GNOME-style pagers keep breaking on Plasma point releases, and
those two things are why. Private modules carry no stability guarantee and are rebuilt in lockstep
with plasmashell. A C++ plugin links against the Qt and KF6 ABIs and stops loading the moment
they're upgraded. This one survived 6.6 → 6.7 untouched, and I'd like to keep it that way. If a
feature looks like it needs a private import, there's almost always a public equivalent in
`org.kde.taskmanager` or on KWin's DBus interface.

The imports already in the tree are the whole surface, and adding one is a conversation to have in
the issue first. The settings pages get a little more latitude, `org.kde.kquickcontrols` for the
colour buttons, because the config dialog loads on demand and a break there can't take the running
panel with it.

If you're adapting code from a Plasma 5 widget or an older tutorial, much of what it reaches for
has moved. Imports are unversioned (`import QtQuick`, not `import QtQuick 2.15`),
`PlasmaCore.Units` and `PlasmaCore.Theme` are now `Kirigami.Units` and `Kirigami.Theme`,
`PlasmaCore.IconItem` is `Kirigami.Icon`, and the root item is a `PlasmoidItem`. `make lint`
catches the renamed types but not the root item: `Item` is still valid QML, so the applet loads,
draws nothing and logs nothing.

## Writing the code

Size and space everything with `Kirigami.Units`, and take colours from `Kirigami.Theme` unless the
user has picked their own. Hardcoded pixels look wrong under fractional scaling.

Put branching logic in `package/contents/ui/logic.mjs` rather than inside a QML binding. It's a
plain JavaScript module with no Plasma dependencies, so it can be unit-tested, and that's where
most of the coverage lives. The QML sees only what it exports, so a new function the QML calls
needs an `export`. Wrap user-visible strings in `i18n()`, run `make messages` afterwards, and
commit the `po/*.po` files it changes.

New behaviour should come with a test named `tst_<thing>.qml`, the only name `qmltestrunner` picks
up. One component in isolation goes in `tests/unit/`, components wired together in
`tests/integration/`, and [tests/README.md](tests/README.md) covers the split and the mocks.
`main.qml`, the settings pages and the rename dialog need a live plasmashell, so changes there are
checked with `make dev`, `make test` and `make restart` instead.

Virtual desktops are read one way and written another. **Read** state from
`TaskManager.VirtualDesktopInfo` and bind to it: it updates however the desktop changed, a keyboard
shortcut or another pager included, so a cached index only drifts out of sync. **Write** through
KWin's DBus interface, fire and forget, and let `VirtualDesktopInfo` report the result back.
Desktops are keyed by UUID, not by position, so map a dot through `desktopIds[i]` rather than
counting. The calls are built in `logic.mjs` (`switchSpec`, `addSpec`, `removeSpec`, `renameSpec`)
and pinned by tests, because KWin silently drops a call whose argument types are wrong.

Both of those sources go briefly empty during a desktop add or remove and during a shell reload,
so `desktopIds` can be `[]` for a frame. Check every index and UUID before using it. A fair number
of the tests exist only to hold that line.

## Pull requests

- **Target `main`**, the only long-lived branch. Merging ships nothing on its own: a release is a
  pushed `v*.*.*` tag.
- **Name the branch for the kind of work**: `feat/`, `fix/`, `refactor/`, `perf/`, `docs/` or
  `chore/`, with the issue number ahead of the slug where there is one, like
  `feat/23-match-desktop-grid-orientation`.
- **Write commit messages and the PR title as
  [Conventional Commits](https://www.conventionalcommits.org/)**, scope optional:
  `fix(occupancy): keep desktops that another activity still uses`. The release notes are
  generated from merged PR titles, so the title is the line that ends up in the changelog. There's
  no `BUG:` footer as on invent.kde.org.
- **Say how you tested it.** For anything `make check` can't load, that means trying it in a real
  panel.

Before you push, run:

```bash
make verify
```

That runs both linters, the format check and the headless tests, which is exactly what CI runs. A
lint warning fails it, so a stray unused property is enough to break the build. If only the format
check fails, `make format` puts the files into the shape it wants. On GitHub the required check is
**Lint & headless tests**, with **Oxlint (JS tier)** and **Oxfmt (format check)** beside it, and
I'll ask you to fix those too.

If your PR shows no checks at all, that isn't your fault: a new contributor's first workflow run
waits for me to approve it.

## Translations

To add a language, say Korean:

```bash
make messages                              # generate po/*.pot from the current strings
msginit --locale=ko -i po/plasma_applet_com.github.kenansalar.plasma-gnome-pager.pot -o po/ko.po
$EDITOR po/ko.po                           # translate each msgstr; Lokalize and Poedit work well
make i18n                                  # compile, then `make restart` to see it in the panel
```

The PR needs only `po/ko.po`. You can also add a `Description[ko]` key to `package/metadata.json`,
which translates the description shown in **Add Widgets**.

Reviewing one, I check that `msgfmt --check` passes, that nothing is fuzzy or untranslated, and
that the plural-form count matches the language. Punctuation and `%1` placeholders have to mirror
the English: a dropped colon or a missing `…` shows up in the settings dialog.

## On AI

Write it by hand or with an assistant, whichever you work best with. Review treats both the same,
which means the bar is the same too: understand what you send well enough to explain and fix it,
and try it in a real panel rather than trusting generated tests.

## License

Contributions are licensed under GPL-3.0-or-later, matching [the project](LICENSE). There's no CLA
to sign.
