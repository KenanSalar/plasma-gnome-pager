# Plasma Widget Robustness Best Practices

> This widget exists *because* GNOME-style pagers keep breaking across Plasma point
> releases (6.5 → 6.6). Everything here is about surviving Plasma/Qt/KF6 upgrades. This is
> the highest-priority ruleset — read it first.

## The two rules that matter most

- **Public QML imports ONLY. Never `org.kde.plasma.private.*`.** Private modules carry no
  API/ABI stability guarantee and are rebuilt in lockstep with plasmashell — importing
  `org.kde.plasma.private.pager` (or any `private.*`) is the **#1 cause** of widgets breaking
  on a Plasma update. If a feature seems to need a private import, find the public equivalent
  (`org.kde.taskmanager`, `org.kde.plasma.workspace.dbus`) or a documented DBus call instead.
- **Pure QML. No compiled C++ plugin.** A C++ plugin links against Qt/KF6 ABIs and stops
  loading the moment those are upgraded (and must ship per-arch binaries). plasmashell loads
  QML directly, so a QML-only plasmoid keeps working across Qt/KF6 bumps with zero rebuild.

## Allowed import surface (stable, public)

```qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2            // config pages only
import org.kde.plasma.plasmoid             // PlasmoidItem, Plasmoid attached prop
import org.kde.plasma.core as PlasmaCore   // PlasmaCore.Types, PlasmaCore.Action
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami        // Units, Theme, Icon, FormLayout
import org.kde.taskmanager as TaskManager  // VirtualDesktopInfo, TasksModel
import org.kde.plasma.workspace.dbus as DBus  // KWin DBus (switch/add/remove desktops)
import org.kde.plasma.configuration        // ConfigModel / ConfigCategory
```

Anything **not** on this list — especially a `private` segment — is a red flag. Confirm it's
public and documented before adding it.

## Versionless imports

- Plasma 6 / Qt 6 use **un-versioned** imports (`import org.kde.plasma.core`, not
  `org.kde.plasma.core 2.0`). Versioned imports are a Plasma 5 habit; drop the version number.

## Don't use what KF6 removed

These were valid in Plasma 5 and are **gone** in Plasma 6 — using them breaks immediately
(see `plasmoid.md` / `kirigami.md` for the replacements):

- root `Item` → **`PlasmoidItem`**
- `PlasmaCore.Units` → `Kirigami.Units`
- `PlasmaCore.Theme` / `PlasmaCore.ColorScope` → `Kirigami.Theme`
- `PlasmaCore.IconItem` → `Kirigami.Icon`
- `PlasmaExtras.Heading` → `Kirigami.Heading`
- `PlasmaCore.DataSource` / DataEngines → use real models or DBus
- `metadata.desktop` → `metadata.json`

## Defensive QML against transient state

- **Reactive sources go briefly empty/null** during reconfigure (desktop add/remove, shell
  reload). `VirtualDesktopInfo.desktopIds` can be `[]` for a frame. Always length/null-check
  before indexing: `const id = vdi.desktopIds[i]; if (!id) return;`.
- **Clamp** any computed index into `[0, numberOfDesktops - 1]` before acting on it.
- Bind, don't cache: read live from the source so external changes (keyboard switch, another
  pager) keep the UI correct. A cached `currentIndex` drifts out of sync.

## DBus discipline

- Prefer **documented** KWin interfaces (`org.kde.KWin.VirtualDesktopManager`) over
  undocumented/internal members. Internal members get renamed without notice.
- All KWin calls are **async fire-and-forget** via `DBus.SessionBus.asyncCall` — never assume
  a synchronous return; let `VirtualDesktopInfo` report the resulting state. See
  `virtual-desktops.md`.

## Metadata contract

- `"X-Plasma-API-Minimum-Version": "6.0"` so plasmashell loads it under the correct API and
  refuses to load it on an incompatible shell instead of half-working.

## Catch breakage early

- Run **`qmllint`** on every `.qml` before installing — it flags removed/renamed symbols and
  unqualified accesses that would otherwise fail silently at runtime on a new Plasma version.
- Smoke-test with `plasmawindowed <id>` (errors print to the terminal) **and** after a real
  `kquitapp6 plasmashell && kstart plasmashell`, since some failures only show in-shell.
- After any Plasma upgrade, re-run both before assuming the widget still works.
