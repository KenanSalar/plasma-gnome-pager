---
paths:
  - package/contents/ui/main.qml
  - package/contents/ui/WorkspaceIndicator.qml
  - package/contents/ui/ScreenCurrentDesktop.qml
  - package/contents/ui/WindowAggregator.qml
  - package/contents/ui/logic.js
  - tests/shared/VdiMock.qml
---

# Virtual desktops and KWin

`CLAUDE.md` holds the read/write split and the gaps in Plasma's API; this file holds the members
and the call shapes.

## Reading: `TaskManager.VirtualDesktopInfo`

| member | kind | since |
|--------|------|-------|
| `desktopIds`, `desktopNames` | UUID list, index-aligned name list | 6.0 |
| `currentDesktop` | UUID of the active output's current desktop | 6.0 |
| `numberOfDesktops`, `desktopLayoutRows` | ints | 6.0 |
| `currentDesktopByScreenName(name)` | method: UUID current on that output | 6.7 |
| `currentDesktopForScreenChanged(name)` | signal | 6.7 |
| `desktopPositionsChanged()` | signal, the only one a reorder emits | 6.5 |

- **The desktop set is global; only which desktop is current differs per output**, and only while
  KWin switches desktops per screen (kwinrc `[Windows] PerOutputVirtualDesktops=true`).
- **The output name comes from `Screen.name` on the indicator**, the placed item. On Wayland it
  is KWin's connector name (`DP-1`), the string `currentDesktopByScreenName` takes.
  `ScreenCurrentDesktop.qml` resolves it and `Logic.resolveCurrentDesktop` decides.
- **The indicator's `desktopIds` and `desktopNames` read `positionsRevision` and return an
  `Array.from` copy**, so a reorder re-notifies them; a `var` notifies only on a new reference.
  They stay on the indicator: read through a child, the indicator first sees the child's empty
  default, the dots subscribe to `perLine` in a different order, and on a later re-layout a
  dying dot evaluates `globalIndex` after its line is gone (`TypeError` on `index` of null).
- **`WindowAggregator` rebuilds synchronously on a reorder**, because the indicator re-reads the
  order in the same emission and a deferred rebuild leaves a frame of misaligned occupancy.
- **A function that runs on demand reads the getter fresh** (`main.qml`'s rename and remove-last,
  the dynamic controller's evaluation) and needs none of this.

## Writing: the specs

Each write is a pure builder in `logic.js` returning `{ service, path, iface, member, args }`,
with each argument a `{ t, v }` whose `t` is a DBus signature letter. `main.qml`'s `toDBusArg`
maps `s`, `u`, `i` and `v` to `new DBus.string`, `uint32`, `int32` and `variant`; there is no
`DBus.QDBusVariant`, which evaluates to `undefined` and throws at the call.

| builder | call |
|---------|------|
| `switchSpec(uuid)` | `org.freedesktop.DBus.Properties.Set(ssv)` on `/VirtualDesktopManager`: `"org.kde.KWin.VirtualDesktopManager"`, `"current"`, the UUID |
| `addSpec(position, name)` | `createDesktop(us)` |
| `removeSpec(uuid, count)` | `removeDesktop(s)`, `null` at the last desktop |
| `renameSpec(uuid, name)` | `setDesktopName(ss)`, `null` for a blank name |
| `invokeShortcutSpec(name)` | `org.kde.kglobalaccel.Component.invokeShortcut(s)` on `/component/kwin` |

- **`pillClickSpec` toggles a KWin shortcut by its unique name**: `"Show Desktop"`, `"Overview"`
  and `"Grid View"` (the combo says "Grid"). They are DBus identifiers, so they live in the
  i18n-free `logic.js`.
- **`removeDesktop` moves the removed desktop's windows itself**; nothing here shifts them.
- **Check a shape outside the widget** before blaming the QML:
  `busctl --user call org.kde.KWin /VirtualDesktopManager org.freedesktop.DBus.Properties Set ssv "org.kde.KWin.VirtualDesktopManager" "current" s "<uuid>"`,
  and `busctl --user introspect org.kde.KWin /VirtualDesktopManager` for the whole interface.
  This system has `qdbus-qt6`, not `qdbus6`.
- **If the property write ever breaks**, `org.kde.KWin` `/KWin` `setCurrentDesktop(i)` takes a
  1-based index and is the proven fallback.
