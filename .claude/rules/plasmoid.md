---
paths:
  - package/metadata.json
  - package/contents/ui/main.qml
  - package/contents/ui/RenameDialog.qml
  - package/contents/ui/WorkspaceIndicator.qml
  - package/contents/config/config.qml
---

# The plasmoid shell

How Plasma loads, sizes and decorates the applet. `/usr/share/plasma/plasmoids/org.kde.plasma.pager/`
is the reference for canonical patterns, minus its `org.kde.plasma.private.pager` import.

## Representations

- **A `fullRepresentation` is mandatory.** An applet with only a `compactRepresentation`
  instantiates neither, renders nothing and logs nothing. `main.qml` makes `WorkspaceIndicator`
  the full representation and forces it inline with `preferredRepresentation`.
- **The representation root advertises its extent through `Layout.*` on both axes.** With only
  an implicit size the panel hands it a square cell about the panel's thickness: the dots draw
  over the neighbouring widgets and only that cell takes input. Wrapping the root in an item that
  doesn't forward the hints, a `ToolTipArea` included, brings the square cell back.
- **A representation's properties are never `required`**: Plasma's loader fails to create it
  without a word. Default to `null` and guard.
- **`Screen.*` is valid only on the placed representation**, so `main.qml` reads `screenRect` off
  `fullRepresentationItem`, and it is a zero rect until the panel places it.
- **`plasmawindowed` renders the full representation**, which makes `make test` a fair smoke test
  of the dots; a panel is still the only test of placement and sizing.
- **"Applet didn't load" and "representation didn't render" look the same.** A `console.warn` in
  the root's `Component.onCompleted` against one in the representation's tells them apart.

## Decoration

- **`Plasmoid.status` is `PassiveStatus` and `backgroundHints` is `NoBackground`**: the dots sit
  on the panel without a frame.
- **Context-menu entries are `PlasmaCore.Action`s in `Plasmoid.contextualActions`.** Plasma adds
  "Configure Workspaces…" for this widget's own settings; "Configure Virtual Desktops…" is ours
  and opens the system page through `KCM.KCMLauncher.openSystemSettings`, whose module name
  differs between Wayland and X11.
- **A popup is a `PlasmaCore.Dialog` declared directly with `visible: false`**, not inside a
  `Loader`: it is a top-level window that realises no surface until shown. The parent sets
  `visualParent` and `location`, and `hideOnWindowDeactivate` makes clicking away cancel.

## metadata.json

- **`KPlugin.Id` is the install folder name and names the catalog domain**,
  `plasma_applet_<Id>`, which Plasma binds to the bare `i18n()` calls with no wiring in QML.
- **`X-Plasma-Provides: org.kde.plasma.virtualdesktops`** offers the widget as a pager
  alternative, and **`X-Plasma-API-Minimum-Version: 6.0`** makes an older shell refuse it rather
  than half-load it.
- **`KPlugin.Version` is the release version**; `ci-packaging.md` says what reads it.
