# Plasma Gnome Pager (Plasma 6)

A GNOME-style virtual-desktop switcher for KDE Plasma 6 panels: small circles with a
sliding **pill** highlighting the current workspace.

> **Status: early, but functional.** The pager renders one dim dot per virtual desktop,
> reflects the active desktop live, switches on click, and slides a highlight **pill** over
> the current workspace (Milestones 1–2 done). Still to come: scroll/hover, add/remove
> desktops, vertical-panel layout, a settings UI, and robustness hardening — see
> [`TODO.txt`](TODO.txt) for the ordered roadmap.

## What works now

- **Live dot strip** — one dim circle per virtual desktop, in order, sized via
  `Kirigami.Units` (HiDPI-correct on fractional scaling).
- **Click to switch** — clicking a dot switches to that desktop via KWin DBus.
- **Sliding pill** — a single highlight overlay sits over the active desktop and slides
  between positions. The first placement is an instant jump (no slide-in from the edge on
  shell reload); later switches animate, and motion respects the "reduce animations" setting.
- **Reactive** — bound to `VirtualDesktopInfo`, so switches made from the keyboard, another
  pager, or KWin settings update the widget immediately (state is never cached).
- **Theme-following** — dim dots use the text color at reduced opacity, the pill uses the
  highlight color, so the widget follows your color scheme automatically.

Currently horizontal panels only. Scroll/hover/tooltips, add/remove desktops (M3),
vertical-panel layout (M4), and the settings UI (M5) are not implemented yet.

## Why this exists

Several third-party GNOME-style pagers break across Plasma point releases (e.g. 6.6) because
they depend on **private** QML imports (`org.kde.plasma.private.*`) or ship a compiled C++
plugin. This widget is deliberately built to be robust:

- **Pure QML** — no compiled plugin, so Qt/KF6 upgrades can't break it.
- **Public, stable imports only** — `org.kde.plasma.plasmoid`, `org.kde.plasma.core`,
  `org.kde.kirigami`, `org.kde.taskmanager` (`VirtualDesktopInfo`), and
  `org.kde.plasma.workspace.dbus` (KWin DBus). No `org.kde.plasma.private.*`.
- **Reactive bindings** to `VirtualDesktopInfo` so the pill always reflects the real state,
  including switches made via keyboard or other widgets.

## Requirements

- KDE Plasma 6.0+ (developed on Plasma 6.6.5 / Qt 6.11, Fedora KDE)
- `kpackagetool6`, `plasmawindowed` (from `plasma-workspace`)

## Project layout

```
plasma-gnome-pager/
├── Makefile                 # dev / install / test helpers
├── README.md
├── TODO.txt                 # ordered implementation roadmap (milestones)
├── LICENSE
├── .gitignore
├── tests/                   # headless QML tests (not shipped in the package)
│   ├── README.md
│   ├── unit/                       # one component in isolation
│   │   └── tst_workspacedot.qml
│   └── integration/                # components composed + reactive wiring
│       └── tst_workspaceindicator.qml
└── package/                 # the KPackage (this is what gets installed)
    ├── metadata.json
    └── contents/
        └── ui/
            ├── main.qml               # PlasmoidItem root, data source, DBus helpers
            ├── WorkspaceIndicator.qml  # row of dots + the sliding pill
            └── WorkspaceDot.qml        # one dot
```

> The config subsystem (`contents/config/` schema + settings pages) is deferred to
> Milestone 5; it will be added when settings actually drive the widget.

## Development

```bash
make dev                # symlink package/ into ~/.local/share/plasma/plasmoids for live editing
make test               # run the widget standalone in a window (shows QML errors in the terminal)
make restart            # reload plasmashell to pick up changes in the panel
make check              # run all headless QML tests — unit + integration (see tests/README.md)
make check-unit         # run only the unit tier (tests/unit)
make check-integration  # run only the integration tier (tests/integration)
make lint               # qmllint the widget UI
make messages           # extract translatable strings into po/ (.pot + merge .po files)
make i18n               # compile po/*.po into the package (contents/locale/.../*.mo)
make dev-undev          # remove the dev symlink
```

The tests cover the Kirigami-only components (`WorkspaceDot`, `WorkspaceIndicator` driven by a
mock `VirtualDesktopInfo`); `main.qml` needs a live plasmashell + KWin session, so it is
verified by the manual `make dev` → `make test` → `make restart` loop.

## Install / uninstall (packaged)

```bash
make install    # kpackagetool6 --install package
make update     # kpackagetool6 --upgrade package
make uninstall  # kpackagetool6 --remove <id>
```

Widget id: `com.github.kenansalar.plasma-gnome-pager`

## Translations

The widget ships **English** (the source language) plus **12 translation catalogs**: Arabic
(`ar`), Simplified Chinese (`zh_CN`), French (`fr`), German (`de`), Greek (`el`), Italian
(`it`), Japanese (`ja`), European Portuguese (`pt`), Brazilian Portuguese (`pt_BR`), Russian
(`ru`), Spanish (`es`), and Turkish (`tr`). All user-visible strings are translated through
`ki18n`; Plasma auto-binds them to the catalog domain
`plasma_applet_com.github.kenansalar.plasma-gnome-pager`. The translation source lives in `po/`
(`*.pot` template + per-language `*.po`); compiled `*.mo` catalogs are generated into
`package/contents/locale/<lang>/LC_MESSAGES/` by `make i18n` (so `make install`/`update`/`dev`
ship them automatically).

**Contributing a translation** — say, Korean:

```bash
make messages                              # refresh po/*.pot from the current strings
msginit --locale=ko -i po/plasma_applet_com.github.kenansalar.plasma-gnome-pager.pot -o po/ko.po
$EDITOR po/ko.po                           # translate each msgstr (Lokalize / Poedit work well)
make i18n                                  # compile, then `make restart` to see it in the panel
```

Open a pull request with the new `po/ko.po` (and, optionally, a `Description[ko]` key in
`package/metadata.json` so the name in **Add Widgets** is localized too). After changing any
in-code string, re-run `make messages` and commit the updated `.pot` + `.po`.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
