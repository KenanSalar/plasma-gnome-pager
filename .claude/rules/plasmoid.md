# Plasma 6 Plasmoid Best Practices

How a Plasma 6 applet is structured, loaded, configured, packaged, and debugged. Pair with
`qml.md` (language), `kirigami.md` (units/theme), `virtual-desktops.md` (our domain), and
`robustness.md` (don't-break rules).

## Package layout

```
package/
├── metadata.json                 # KPackage manifest (root level)
└── contents/
    ├── ui/
    │   ├── main.qml              # PlasmoidItem root (required)
    │   ├── *.qml                 # sibling components, auto-importable by filename
    │   └── config/*.qml          # config PAGES live here (see below)
    └── config/
        ├── config.qml           # ConfigModel: the settings categories
        └── main.xml             # KConfigXT schema
```

- **`ConfigCategory.source` is resolved relative to `contents/ui/`** — that's why config pages
  go in `contents/ui/config/` while `config.qml`/`main.xml` go in `contents/config/`. Mixing
  this up gives an empty settings dialog.

## metadata.json

```json
{
  "KPackageStructure": "Plasma/Applet",
  "X-Plasma-API-Minimum-Version": "6.0",
  "X-Plasma-Provides": ["org.kde.plasma.virtualdesktops"],
  "KPlugin": {
    "Id": "com.github.<user>.<project>",
    "Name": "Display Name",
    "Description": "One line.",
    "Category": "Windows and Tasks",
    "Icon": "user-desktop",
    "Version": "0.1.0",
    "License": "GPL-3.0-or-later",
    "Authors": [{ "Name": "...", "Email": "..." }]
  }
}
```

- `Id` is the **unique** identifier *and* the install folder name; reverse-DNS, hyphens allowed.
- `Name`/`Description`/`Icon` are what users see in "Add Widgets" and the Store — the `Id` is
  never shown.
- `X-Plasma-Provides: org.kde.plasma.virtualdesktops` registers it as a pager alternative.

## The root: PlasmoidItem

```qml
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root

    toolTipMainText: i18n("Workspaces")     // direct property of the root now
    Plasmoid.icon: "user-desktop"           // Plasmoid attached prop for title/icon/etc

    preferredRepresentation: compactRepresentation
    compactRepresentation: WorkspaceIndicator {}
    // fullRepresentation: ...              // optional; only if a popup is wanted
}
```

- **Root must be `PlasmoidItem`** (or `ContainmentItem`). Plain `Item` is the Plasma 5 form.
- **Representations are direct properties** of the root: `compactRepresentation`,
  `fullRepresentation`, `preferredRepresentation`. If neither is set, the root *is* the full
  representation. A panel pager renders inline, so make the indicator the
  `compactRepresentation` and set `preferredRepresentation: compactRepresentation`.
- `toolTipMainText` / `toolTipSubText` are properties of the root `PlasmoidItem`.
- The `Plasmoid` **attached property** still carries `Plasmoid.title`, `Plasmoid.icon`,
  `Plasmoid.formFactor`, `Plasmoid.location`, `Plasmoid.configuration`,
  `Plasmoid.contextualActions`, `Plasmoid.status`, `Plasmoid.backgroundHints`.

## Form factor & location (panel awareness)

```qml
readonly property bool isHorizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
readonly property bool isVertical:   Plasmoid.formFactor === PlasmaCore.Types.Vertical
```

- `Plasmoid.formFactor`: `Planar` (desktop), `Horizontal` (top/bottom panel),
  `Vertical` (side panel). Switch `Row` ↔ `Column` on it.
- `Plasmoid.location`: `TopEdge` / `BottomEdge` / `LeftEdge` / `RightEdge` / `Floating` /
  `Desktop` — use for edge-aware tooltip/popup placement.
- `switchWidth` / `switchHeight`: when the applet's available size drops below these, Plasma
  shows the `compactRepresentation`. Set them if you provide a full representation.

## Sizing in a panel

- The compact representation must advertise its size with `implicitWidth`/`implicitHeight` (or
  `Layout.preferredWidth`/`Layout.preferredHeight`), computed from content (dot count × size +
  spacing). The panel allocates space from these — without them the widget collapses to 0 or
  fights the layout.
- Use `Kirigami.Units` for all sizes (HiDPI). See `kirigami.md`.

## Status (let the panel hide/show it)

- `Plasmoid.status = PlasmaCore.Types.PassiveStatus | ActiveStatus | NeedsAttentionStatus |
  HiddenStatus`. Affects auto-hide and system-tray promotion. A pager is normally
  `PassiveStatus`.

## Background

- `Plasmoid.backgroundHints = PlasmaCore.Types.DefaultBackground | NoBackground |
  ConfigurableBackground`. Pagers usually want `NoBackground` (dots float on the panel) or
  `ConfigurableBackground` to let the user choose.

## Contextual actions (right-click menu)

```qml
Plasmoid.contextualActions: [
    PlasmaCore.Action {
        text: i18n("Add Desktop")
        icon.name: "list-add"
        priority: Plasmoid.LowPriorityAction
        onTriggered: root.addDesktop()
    }
]
```

- Declarative list of `PlasmaCore.Action`. The "Configure…" entry is added automatically when
  a config schema exists — don't add it yourself.

## Configuration

- **Schema**: `contents/config/main.xml` (KConfigXT). Every `<entry>` becomes
  `plasmoid.configuration.<name>`, read live and reactive.
- **Categories**: `contents/config/config.qml` is a `ConfigModel` of `ConfigCategory` items;
  `source` points (relative to `contents/ui/`) at each page.
- **Pages**: use `Kirigami.FormLayout` + `QtQuick.Controls as QQC2` controls — **not**
  `PlasmaComponents` — and two-way bind with `property alias cfg_<key>: control.value`:

```qml
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
Kirigami.FormLayout {
    property alias cfg_enableScroll: enableScroll.checked
    QQC2.CheckBox { id: enableScroll; text: i18n("Scroll to switch desktops") }
}
```

- The `cfg_<key>` alias name must match the `main.xml` entry exactly; the dialog wires
  save/load/defaults automatically. A `cfg_<key>Default` alias is auto-provided for reset.

## Packaging, install, dev loop

```bash
kpackagetool6 --type Plasma/Applet --install  package   # install
kpackagetool6 --type Plasma/Applet --upgrade  package   # update in place
kpackagetool6 --type Plasma/Applet --remove   <id>      # uninstall

# Live dev: symlink the package, then reload the shell after edits.
ln -sfn "$PWD/package" ~/.local/share/plasma/plasmoids/<id>
plasmawindowed <id>                       # run standalone; QML errors print to terminal
kquitapp6 plasmashell && kstart plasmashell   # reload in the real panel
```

- User widgets live in `~/.local/share/plasma/plasmoids/<id>/`; system ones in
  `/usr/share/plasma/plasmoids/`.
- `plasmawindowed` reloads fresh each launch — fastest feedback. In-panel changes need a
  shell reload.

## Debugging

- `console.log/​warn/​error(...)` surface in the `plasmawindowed` terminal or via
  `journalctl --user -f -t plasmashell`.
- Read the reference pager at `/usr/share/plasma/plasmoids/org.kde.plasma.pager/` for canonical
  patterns — but **do not** copy its `org.kde.plasma.private.pager` import (see `robustness.md`).
