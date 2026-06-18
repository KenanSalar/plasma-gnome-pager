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

### Per-screen current desktop (Plasma 6.7 "switch desktops independently for each screen")

Plasma 6.7 (kwinrc `[Windows] PerOutputVirtualDesktops=true`) lets each **output** show a different
current desktop. The desktop *set* (`desktopIds`/`desktopNames`/`numberOfDesktops`/`desktopLayoutRows`)
is still global — only *which is current* can differ per screen. `VirtualDesktopInfo` exposes this
(public, verified in `taskmanager.qmltypes`):

| Member                                            | Kind            | Meaning                                        |
|---------------------------------------------------|-----------------|------------------------------------------------|
| `currentDesktopByScreenName(screenName) → QVariant` | method        | current-desktop UUID for that output           |
| `currentDesktopByScreenGeometry(rect) → QVariant`   | method        | same, keyed by geometry                        |
| `currentDesktopForScreenChanged(screenName)`        | signal        | one output's current changed                   |

- **Get this widget's output name from the QtQuick `Screen` attached property** (`import QtQuick`;
  `Screen.name`) — on Plasma Wayland it is the KWin connector name (e.g. `DP-1`), the same string the
  per-screen API and `org.kde.KWin.activeOutputName` use. Read it from the on-screen item (the
  representation), not a non-visual root.
- **It is a METHOD + SIGNAL, not a notifying property** — a plain binding evaluates once and never
  refreshes. Recompute imperatively on `currentDesktopForScreenChanged` (filtered to your screen) and
  the global `currentDesktopChanged`/`desktopIdsChanged`; see the gotcha in CLAUDE.md.
- **Degrade gracefully:** prefer the per-screen value, fall back to `currentDesktop` (global) when the
  screen is unknown, the feature is off, or the API is missing (older Plasma — guard
  `typeof vdi.currentDesktopByScreenName === "function"`). This auto-mirrors KWin, so add **no** widget
  setting. The pure decision is `logic.js::resolveCurrentDesktop(perScreen, global)`.
- **Writing is global-only.** There is **no** public DBus member that takes an output/screen argument
  (introspect `org.kde.KWin /VirtualDesktopManager` — `current` is one global string). The switch
  below sets that global `current`; with per-output on, KWin routes it to the **active** output, and
  interacting with a pager makes its output active, so click/scroll switch the monitor you used.

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
            new DBus.variant(uuid)   // variant of a PLAIN string, not a wrapped DBus.string
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

- `new DBus.int32(n)`, `new DBus.uint32(n)`, `new DBus.string(s)`, `new DBus.variant(v)`
  (all lowercase, verified from `dbusplugin.qmltypes`) — KWin signatures are strict, so wrap
  each argument in the exact type. Passing a bare JS number/string where `uint32`/variant is
  expected silently fails (the call is dropped, no error in QML).
- **`new DBus.variant(v)` takes a _plain_ JS value, not another DBus wrapper.** Its constructor
  takes a `QJSValue`, so `new DBus.variant(new DBus.string(uuid))` wraps a gadget object and
  KWin silently rejects it — pass the bare string: `new DBus.variant(uuid)`. There is **no**
  `DBus.QDBusVariant` type; referencing it evaluates to `undefined` and throws `TypeError` at
  call time.

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
- Inspect the live interface while developing (this Fedora KDE system ships `qdbus-qt6`,
  `busctl`, and `gdbus`, **not** `qdbus6`):
  `qdbus-qt6 org.kde.KWin /VirtualDesktopManager` and
  `qdbus-qt6 org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.current`.
  For a full interface dump (properties, methods, signatures, signals):
  `busctl --user introspect org.kde.KWin /VirtualDesktopManager`.
