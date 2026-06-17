# GNOME Workspace Switcher (Plasma 6)

A GNOME-style virtual-desktop switcher for KDE Plasma 6 panels: small circles with a
sliding **pill** highlighting the current workspace.

> **Status: scaffold.** The project structure is fully wired up but the behavior is not
> implemented yet. Files marked `TODO(impl)` are the next step.

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
├── LICENSE
├── .gitignore
└── package/                 # the KPackage (this is what gets installed)
    ├── metadata.json
    └── contents/
        └── ui/
            ├── main.qml             # PlasmoidItem root, data sources, DBus helpers
            ├── WorkspaceIndicator.qml  # row/column of dots + sliding pill
            └── WorkspaceDot.qml        # one dot
```

> The config subsystem (`contents/config/` schema + settings pages) is deferred to
> Milestone 5; it will be added when settings actually drive the widget.

## Development

```bash
make dev        # symlink package/ into ~/.local/share/plasma/plasmoids for live editing
make test       # run the widget standalone in a window (shows QML errors in the terminal)
make restart    # reload plasmashell to pick up changes in the panel
make dev-undev  # remove the dev symlink
```

## Install / uninstall (packaged)

```bash
make install    # kpackagetool6 --install package
make update     # kpackagetool6 --upgrade package
make uninstall  # kpackagetool6 --remove <id>
```

Widget id: `com.github.kenansalar.plasma-gnome-pager`

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
