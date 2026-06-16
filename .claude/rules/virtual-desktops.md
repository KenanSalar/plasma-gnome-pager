# Virtual Desktops & KWin DBus Best Practices

The core domain of this widget. **Read state** with `VirtualDesktopInfo` (reactive, public);
**change state** (switch / add / remove) with KWin DBus. This split is deliberate —
`VirtualDesktopInfo` is read-only and does not switch desktops.

## Reading state — VirtualDesktopInfo

```qml
import org.kde.taskmanager as TaskManager

TaskManager.VirtualDesktopInfo {
    id: vdi
}
```

Exposes (all reactive — bind to them, never cache):

| Property            | Type            | Meaning                                            |
|---------------------|-----------------|----------------------------------------------------|
| `currentDesktop`    | string (UUID)   | UUID of the active desktop                          |
| `desktopIds`        | list of strings | UUIDs of all desktops, in order                     |
| `desktopNames`      | list of strings | display names, index-aligned with `desktopIds`      |
| `numberOfDesktops`  | int             | count                                               |
| `desktopLayoutRows` | int             | rows in the KWin desktop grid                        |

- **Desktops are identified by UUID strings**, not indices. Map a UI dot to a desktop via
  `vdi.desktopIds[i]`; find the active index with `vdi.desktopIds.indexOf(vdi.currentDesktop)`.
- It updates automatically when desktops change by **any** means (keyboard shortcut, another
  pager, KWin settings) — so a UI bound to it always reflects reality.
- It is part of `org.kde.taskmanager` (a public, compiled QML plugin shipped with
  plasma-workspace) — stable, this is what the stock pager reads too.

## Window occupancy (optional) — TasksModel

```qml
TaskManager.TasksModel {
    id: tasks
    groupMode: TaskManager.TasksModel.GroupDisabled
    // filterByVirtualDesktop: true; virtualDesktop: <uuid>   // to test a single desktop
}
```

- Only needed if you indicate occupied desktops or show name/count tooltips. For a pure
  dots+pill look it can be omitted entirely.

## Changing state — KWin DBus

Use `org.kde.plasma.workspace.dbus`. All calls are **asynchronous, fire-and-forget** — issue
the call and let `VirtualDesktopInfo` report the new state; do not expect a return value.

```qml
import org.kde.plasma.workspace.dbus as DBus
```

### Switch to a desktop (preferred: UUID via VirtualDesktopManager)

Set the read/write `current` property on `org.kde.KWin.VirtualDesktopManager`. UUID-based, so
it matches `vdi.desktopIds` directly and avoids 1-based index bugs:

```qml
function switchTo(uuid) {
    if (!uuid) return;
    DBus.SessionBus.asyncCall({
        "service": "org.kde.KWin",
        "path": "/VirtualDesktopManager",
        "iface": "org.freedesktop.DBus.Properties",
        "member": "Set",
        "arguments": [
            new DBus.string("org.kde.KWin.VirtualDesktopManager"),
            new DBus.string("current"),
            new DBus.QDBusVariant(new DBus.string(uuid))
        ],
    });
}
```

**Proven fallback** (legacy, 1-based index) if the property-set path is ever problematic:

```qml
// org.kde.KWin /KWin setCurrentDesktop(int32)  — index is 1-based
DBus.SessionBus.asyncCall({
    "service": "org.kde.KWin", "path": "/KWin", "iface": "org.kde.KWin",
    "member": "setCurrentDesktop", "arguments": [ new DBus.int32(uiIndex + 1) ],
});
```

### Add a desktop

```qml
function addDesktop() {
    DBus.SessionBus.asyncCall({
        "service": "org.kde.KWin",
        "path": "/VirtualDesktopManager",
        "iface": "org.kde.KWin.VirtualDesktopManager",
        "member": "createDesktop",
        "arguments": [
            new DBus.uint32(vdi.numberOfDesktops),     // position = append at end
            new DBus.string(i18n("New Desktop"))
        ],
    });
}
```

### Remove a desktop (by UUID)

```qml
function removeDesktop(uuid) {
    if (!uuid || vdi.numberOfDesktops <= 1) return;     // never remove the last one
    DBus.SessionBus.asyncCall({
        "service": "org.kde.KWin",
        "path": "/VirtualDesktopManager",
        "iface": "org.kde.KWin.VirtualDesktopManager",
        "member": "removeDesktop",
        "arguments": [ new DBus.string(uuid) ],
    });
}
```

## DBus typed-argument helpers

- `new DBus.int32(n)`, `new DBus.uint32(n)`, `new DBus.string(s)`,
  `new DBus.QDBusVariant(value)` — KWin signatures are strict, so wrap each argument in the
  exact type. Passing a bare JS number/string where `uint32`/variant is expected silently
  fails (the call is dropped, no error in QML).

## Scroll-to-switch (with optional wrap)

```qml
function step(delta) {                       // delta = +1 / -1
    const ids = vdi.desktopIds;
    if (!ids.length) return;
    let i = ids.indexOf(vdi.currentDesktop) + delta;
    if (plasmoid.configuration.scrollWrap) i = (i + ids.length) % ids.length;
    else i = Math.max(0, Math.min(ids.length - 1, i));
    switchTo(ids[i]);
}
```

## Robustness notes (see robustness.md)

- `desktopIds` / `currentDesktop` can be momentarily empty/stale during a desktop add/remove
  or shell reload — **guard every index and UUID** before use.
- Do **not** reach for `org.kde.plasma.private.pager`'s `PagerModel.changePage()` — it's a
  private import and the reason other GNOME-style pagers break. The DBus calls above are the
  public, stable equivalent.
- Inspect the live interface while developing:
  `qdbus6 org.kde.KWin /VirtualDesktopManager` and
  `qdbus6 org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.current`.
