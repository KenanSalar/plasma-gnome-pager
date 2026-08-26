# Contributing

I maintain this in my spare time, and bug reports, translations, and patches are all welcome. This
file covers what isn't obvious from the README, which already has the [development
loop](README.md#development) and the [translation recipe](README.md#translations).

If you'd like to help but don't write QML: translate the widget into a language it doesn't ship
yet, send a screenshot for the README, or reproduce someone else's bug report. Multi-monitor,
vertical panels, and fractional scaling are where this widget breaks — someone running `dev` on
hardware I can't test is worth more to me than most patches.

## Before you build something

Open an issue before writing a feature. I review everything here myself and my time is limited, so
a short conversation up front beats a weekend of work I end up declining. Typos, doc fixes,
translations, and small bug fixes don't need this — just send them.

What I'm likely to decline is anything that widens the widget past being a pager: it shows virtual
desktops and switches between them, and window management or system monitoring belongs elsewhere.

## Where pull requests go

**Open your PR against `dev`, not `main`.** `main` is the release branch — a push to it cuts a
draft release — so CI fails any PR into it that doesn't come from `dev` or a `hotfix/*` branch.
GitHub defaults a fork's PR to `main`, so this is easy to get wrong; if it happens, click **Edit**
next to the PR title and change the base. Nothing is lost.

Branch names follow the type of the work — `feat/`, `fix/`, `refactor/`, `perf/`, `docs/` — with
the issue number in front of the slug where there is one, like
`feat/23-match-desktop-grid-orientation`.

## Getting set up

There's no build step. plasmashell interprets the QML directly, so "building" means symlinking the
package and reloading the shell:

```bash
make dev      # symlink package/ into ~/.local/share/plasma/plasmoids
make test     # run it standalone; QML errors print to the terminal
make restart  # reload the panel — plasmashell caches QML, so editing alone isn't enough
```

The rest of the targets are in the [README](README.md#development). One thing that isn't obvious:
`make lint-js` and `make verify` need `npm ci` once first, for the ESLint dev dependency.

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

## Commit messages

Conventional Commits, with an optional scope:

```
feat: add "Filled & ring" pager style
fix: pin the dot strip so multi-row morphs don't drift the dots
fix(i18n): correct punctuation and spacing in the Polish catalog
```

Nothing enforces this — it's the house style, and it keeps the generated release notes readable.
If you've contributed to KDE upstream: this repo doesn't use the `BUG:` footer convention from
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

If it misbehaves rather than just looking wrong, run `make test` and paste any QML errors from the
terminal. That step is usually the difference between a report I can fix and one I can't reproduce.

## License

Contributions are licensed under GPL-3.0-or-later, matching [the project](LICENSE). There's no CLA
to sign.
