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

`CLAUDE.md` holds the read/write split and the gaps in Plasma's API; this file holds the members,
the call shapes and what each asks of a change.

## Reading: `TaskManager.VirtualDesktopInfo`

| member | kind | since |
|--------|------|-------|
| `desktopIds`, `desktopNames` | UUID list, index-aligned name list | 6.0 |
| `currentDesktop` | UUID of the active output's current desktop | 6.0 |
| `numberOfDesktops`, `desktopLayoutRows` | ints | 6.0 |
| `currentDesktopByScreenName(name)` | method: UUID current on that output | 6.7 |
| `currentDesktopForScreenChanged(name)` | signal | 6.7 |
| `desktopPositionsChanged()` | signal, the only one a reorder emits | 6.5 |

- **Only which desktop is current differs per output**, and only while kwinrc has `[Windows]
  PerOutputVirtualDesktops=true`; the set itself is global.
- **The output name is `Screen.name` read on the indicator**, KWin's connector name (`DP-1`) on
  Wayland. A non-visual item has no screen. `Logic.resolveCurrentDesktop` decides between it and
  the global current desktop.
- **A new binding on `desktopIds` or `desktopNames` reads `positionsRevision` and returns a copy**,
  as the indicator's do, or a reorder leaves it on the old order; a `var` notifies only on a new
  reference.
- **The reorder bindings stay on the indicator itself.** Read through a child, they make the dots
  subscribe to `perLine` in another order, and a later re-layout has a dying dot evaluate
  `globalIndex` after its line is gone (`TypeError` on `index` of null).
- **What derives from the order rebuilds synchronously on `desktopPositionsChanged`**, as
  `WindowAggregator` does: the indicator re-reads the order in the same emission, and a deferred
  rebuild leaves a frame misaligned.
- **A function that runs on demand reads the getter fresh** and needs none of this.

## Writing: the specs

| builder | call |
|---------|------|
| `switchSpec(uuid)` | `org.freedesktop.DBus.Properties.Set(ssv)` on `/VirtualDesktopManager`: `"org.kde.KWin.VirtualDesktopManager"`, `"current"`, the UUID |
| `addSpec(position, name)` | `createDesktop(us)` |
| `removeSpec(uuid, count)` | `removeDesktop(s)`, `null` at the last desktop |
| `renameSpec(uuid, name)` | `setDesktopName(ss)`, `null` for a blank name |
| `invokeShortcutSpec(name)` | `org.kde.kglobalaccel.Component.invokeShortcut(s)` on `/component/kwin` |

- **An argument's `t` is one of `s`, `u`, `i` and `v`**, which `toDBusArg` maps to `new
  DBus.string`, `uint32`, `int32` and `variant`. Another type needs a case there first. There is no
  `DBus.QDBusVariant`: it evaluates to `undefined` and throws at the call.
- **Shortcut names are KWin's DBus identifiers and stay untranslated in `logic.js`**: `"Show
  Desktop"`, `"Overview"` and `"Grid View"`, which the combo calls "Grid".
- **Nothing here moves windows off a removed desktop**; `removeDesktop` does that itself.
- **Check a call shape with `busctl` before suspecting the QML**:
  `busctl --user call org.kde.KWin /VirtualDesktopManager org.freedesktop.DBus.Properties Set ssv "org.kde.KWin.VirtualDesktopManager" "current" s "<uuid>"`,
  and `busctl --user introspect org.kde.KWin /VirtualDesktopManager` for the whole interface.
  This system has `qdbus-qt6`, not `qdbus6`.
- **If the property write stops working**, `org.kde.KWin` `/KWin` `setCurrentDesktop(i)` takes a
  1-based index and is the fallback.
