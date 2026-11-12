---
paths:
  - "**/*.qml"
---

# Kirigami

Plasma 6 moved units and theme from `PlasmaCore` to Kirigami (`import org.kde.kirigami as Kirigami`).

- **Sizes come from `Kirigami.Units`**: `gridUnit` for layout, `smallSpacing` and `largeSpacing`
  for gaps, `iconSizes.small` for the default dot (half of it) and the legibility floor (a
  quarter). They already include the device pixel ratio, so never multiply by it.
- **Durations come from `Kirigami.Units.longDuration`**, which is `0` while the user has
  animations reduced; `CLAUDE.md` says how a duration is resolved.
- **Colours come from `Kirigami.Theme`**: `highlightColor` for the pill and the occupied marker,
  `textColor` for the dots and the hover background. A custom colour applies only with
  `followThemeColors` off, and the binding keeps reading `Kirigami.Theme` either way so a scheme
  change re-evaluates it.
- **Settings pages are `Kirigami.FormLayout` with `QQC2` controls**, each row labelled through
  `Kirigami.FormData.label`; `PlasmaComponents3` is for inside the applet.
- **`Kirigami.Dialog` and its subclasses need `applicationWindow()`**, which a plasmoid lacks;
  `CLAUDE.md` names the replacement.
- **Offscreen, `Kirigami.Theme.smallFont` resolves to the default font**, so a test can't tell the
  two apart.
