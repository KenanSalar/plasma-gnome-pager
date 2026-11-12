---
paths:
  - package/**
---

# Surviving Plasma upgrades

`CLAUDE.md` holds the two rules this widget exists for (public imports only, no C++ plugin) and
the transient-state guard. This file holds the detail behind them.

## The import surface

| import | for |
|--------|-----|
| `QtQuick`, `QtQml`, `QtQuick.Layouts` | items, `Instantiator`, `Layout.*` |
| `org.kde.plasma.plasmoid` | `PlasmoidItem` and the `Plasmoid` attached property, in `main.qml` only |
| `org.kde.plasma.core as PlasmaCore` | `Types`, `Action`, `ToolTipArea`, `Dialog` |
| `org.kde.plasma.components as PlasmaComponents3` | the rename dialog's controls |
| `org.kde.kirigami as Kirigami` | `Units`, `Theme`; `FormLayout` and `ScrollablePage` on the settings pages |
| `org.kde.taskmanager as TaskManager` | `VirtualDesktopInfo`, `TasksModel`, `ActivityInfo` |
| `org.kde.plasma.workspace.dbus as DBus` | the KWin and kglobalaccel writes |
| `org.kde.kcmutils as KCM` | `KCMLauncher`, opening the Virtual Desktops settings page |
| `QtQuick.Controls as QQC2`, `org.kde.plasma.configuration`, `org.kde.kquickcontrols` | `config.qml` and the settings pages only |

- **An import off this table is a decision before it is code**: confirm it's public, documented,
  and shipped by every Plasma from the `X-Plasma-API-Minimum-Version` up. A `private` segment is
  never public.
- **Imports are versionless**: `import QtQuick`, not `import QtQuick 2.15`.
- **`WorkspaceIndicator.qml` and `IndicatorMetrics.qml` import nothing from `org.kde.plasma`**, and
  `WorkspaceDot.qml` only `PlasmaCore` for `ToolTipArea`, which loads offscreen. That is what keeps
  them headless-testable.

## What KF6 removed

| Plasma 5 | Plasma 6 |
|----------|----------|
| root `Item` | `PlasmoidItem` |
| `PlasmaCore.Units` | `Kirigami.Units` |
| `PlasmaCore.Theme`, `PlasmaCore.ColorScope` | `Kirigami.Theme` |
| `PlasmaCore.IconItem` | `Kirigami.Icon` |
| `PlasmaExtras.Heading` | `Kirigami.Heading` |
| `PlasmaCore.DataSource`, data engines | a real model or a DBus call |
| `metadata.desktop` | `metadata.json` |

`make lint` flags the renamed symbols. It can't flag a root `Item`, which is still a valid type:
the applet loads, renders nothing and logs nothing.

## Newer APIs

- **An API newer than Plasma 6.0 is detected, never assumed.** A method is guarded with
  `typeof vdi.currentDesktopByScreenName === "function"` (6.7). A signal goes in a `Connections`
  of its own with `ignoreUnknownSignals: true` (`desktopPositionsChanged` 6.5,
  `currentDesktopForScreenChanged` 6.7), leaving the always-present handlers in a block without
  it so a typo there still warns.
- **Missing information degrades to the global answer, never to nothing.** An unknown screen
  name gives the global current desktop, an unknown screen rect or a window without one counts
  on every screen, and an unknown activity filters nothing.

## DBus

- **Only documented interfaces**: `org.kde.KWin.VirtualDesktopManager` on `/VirtualDesktopManager`
  and kglobalaccel's `org.kde.kglobalaccel.Component` on `/component/kwin`. A KWin effect's own
  path carries a version suffix (`/org/kde/KWin/Effect/Overview/<ver>`) that moves between KWin
  releases.
- **Every call is `asyncCall`**; the reply is read only to log a failure, and the new state comes
  back through `VirtualDesktopInfo`.

## After a Plasma, Qt or KF6 upgrade

`make verify`, then `make dev && make test` and `make restart`, watching
`journalctl --user -f -t plasmashell`. Some failures show only in a real panel.
