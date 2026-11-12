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

- **Keep a `fullRepresentation`.** An applet with only a `compactRepresentation` builds neither,
  renders nothing and logs nothing; `preferredRepresentation` keeps the strip inline.
- **The representation root advertises its extent through `Layout.*` on both axes, and nothing
  wraps it**, a `ToolTipArea` included. With only an implicit size the panel hands it a square
  cell about the panel's thickness: the dots draw over the neighbouring widgets and only that cell
  takes input.
- **A representation's properties are never `required`**: Plasma's loader fails to create it
  without a word. Default to `null` and guard.
- **Read `Screen.*` on the placed representation**, never on the root. `main.qml` takes
  `screenRect` from `fullRepresentationItem`, a zero rect until the panel places it.
- **`make test` checks the dots, a real panel checks placement and sizing**: `plasmawindowed`
  renders the full representation in a window of its own.
- **Tell "applet didn't load" from "representation didn't render"** with a `console.warn` in each
  one's `Component.onCompleted`; both otherwise show an empty panel.

## Decoration

- **The applet draws no frame of its own** (`NoBackground`) and stays `PassiveStatus`.
- **A context-menu entry is a `PlasmaCore.Action` in `Plasmoid.contextualActions`.** Plasma adds
  "Configure Workspaces…" itself, so it never goes in the list. The system's Virtual Desktops page
  opens through `KCM.KCMLauncher.openSystemSettings`, whose module name differs between Wayland
  and X11.
- **A popup is a `PlasmaCore.Dialog` declared directly with `visible: false`**, not inside a
  `Loader`: a top-level window realises no surface until shown. The parent sets `visualParent` and
  `location`, and `hideOnWindowDeactivate` makes clicking away cancel.

## metadata.json

- **`KPlugin.Id` is the install folder and the catalog domain `plasma_applet_<Id>`**, which Plasma
  binds to the bare `i18n()` calls with no wiring in QML.
- **`X-Plasma-Provides: org.kde.plasma.virtualdesktops` stays**, offering the widget as a pager
  alternative, and **`X-Plasma-API-Minimum-Version` stays at the oldest Plasma the imports
  support**, so an older shell refuses the widget rather than half-loading it.
