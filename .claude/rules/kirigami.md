# Kirigami (Units, Theme, Components) Best Practices

In Plasma 6, sizing, theming, and several stock items moved from `PlasmaCore` to **Kirigami**.
Using the old `PlasmaCore.*` equivalents breaks on Plasma 6 (see `robustness.md`).

```qml
import org.kde.kirigami as Kirigami
```

## Units (HiDPI — never hardcode pixels)

- `Kirigami.Units.gridUnit` — base metric (~ one line of text). Size things in multiples of it.
- `Kirigami.Units.smallSpacing` / `largeSpacing` — standard gaps (use for dot spacing/margins).
- `Kirigami.Units.iconSizes.{small,smallMedium,medium,large,...}` — themed icon dimensions.
- `Kirigami.Units.{shortDuration,longDuration}` — standard animation durations; bind animation
  times to these so motion matches the rest of Plasma. Respect the user's "reduce animations"
  setting via `Kirigami.Units.longDuration === 0` (it goes to 0 when animations are off — guard
  divisions).
- These already account for the device pixel ratio — do **not** multiply by a DPR yourself.
  Replaces Plasma 5's `PlasmaCore.Units` and manual `devicePixelRatio` math.

## Theme (colors)

- `Kirigami.Theme.textColor`, `highlightColor`, `backgroundColor`, `disabledTextColor`,
  `highlightedTextColor`, `positiveTextColor`, etc. Replaces `PlasmaCore.Theme` /
  `PlasmaCore.ColorScope`.
- For the GNOME look: inactive dots = `Kirigami.Theme.textColor` at reduced opacity; the active
  pill = `Kirigami.Theme.highlightColor`. Binding to the theme means the widget follows the
  user's color scheme automatically.
- **Color set**: choose the palette context with
  `Kirigami.Theme.colorSet = Kirigami.Theme.{View,Window,Button,Complementary,Header}` and
  `Kirigami.Theme.inherit = false` to pin it. Panel widgets typically want the default; only
  override if colors look wrong against the panel.
- When "follow theme" is off in config, fall back to the user's `activeColor`/`inactiveColor`
  config entries instead of the theme bindings.

## Icons

- `Kirigami.Icon { source: "user-desktop" }` — themed icon by name; replaces
  `PlasmaCore.IconItem`. Size with `Kirigami.Units.iconSizes.*`. Source can be an icon name,
  a file path, or a URL.

## Config forms

- Build settings pages with `Kirigami.FormLayout` + `QtQuick.Controls as QQC2` controls
  (CheckBox, SpinBox, ComboBox, etc.). Label rows with
  `Kirigami.FormData.label: i18n("…:")`. Do **not** use `PlasmaComponents` controls on config
  pages. Full pattern in `plasmoid.md`.
- For a color picker on a config page, use a `QQC2`/Kirigami color control bound to a
  `cfg_<key>` of `type="Color"`.

## Headings & text

- `Kirigami.Heading { level: 1..5 }` replaces `PlasmaExtras.Heading`. For body text inside the
  applet prefer `PlasmaComponents3.Label` (panel-themed); on config pages use `QQC2.Label`.

## Pitfalls

- **Hardcoded pixel sizes** don't scale on HiDPI/fractional-scaling and look wrong next to
  native widgets — always go through `Kirigami.Units`.
- **Hardcoded colors** ignore the color scheme — bind to `Kirigami.Theme` unless the user
  explicitly opted into custom colors.
- **Dividing by a duration** that can be 0 (animations disabled) — guard
  `Kirigami.Units.longDuration` before using it as a divisor or rate.
