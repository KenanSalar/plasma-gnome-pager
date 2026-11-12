---
paths:
  - package/contents/config/**
  - package/contents/ui/config/**
  - tests/unit/tst_config*.qml
---

# Settings

`CLAUDE.md` lists the five edits a new setting takes; this file holds how the two pages are built.

- **A page subclasses `ConfigPageBase` and lists its keys in `configKeys`**, each `{ n, t }` with
  `t` one of `bool`, `int`, `real`, `string` or `color`. The base binds `isModified` and the
  Defaults header action off that list, since the dialog's footer has only Apply, Discard and
  Cancel.
- **Each key needs a `cfg_<key>` alias and a `cfg_<key>Default` property with no initializer**,
  both named exactly as the `main.xml` entry: the dialog injects the default from the schema, and
  a misspelled name loads and saves nothing without an error.
- **A combo's `currentIndex` is the stored value**, so its item order, the frozen table in
  `logic.js` (`PILL_CLICK_ACTION`, `DOT_STYLE`, `OCCUPANCY`) and the `main.xml` comment change
  together or not at all.
- **A numeric row is a `ConfigSlider`, an opacity row a `ConfigPercentSlider`.** Its `format`
  gives both the read-out and the width reserved for it, measured at `from` and `to`, so a
  sentinel's text sits at `from` (`0` reads "Default").
- **Every field column is `Logic.CONFIG_FIELD_WIDTH_UNITS` grid units wide**: a slider's track, a
  combo or text field through `ConfigPageBase.fieldWidth`, and a `ConfigHint`'s wrap width. The
  slider's value label takes the slack, which is what keeps the two pages' sliders the same
  length.
- **Rows are grouped under `ConfigSection` headings**, and a group's first control carries no
  `Kirigami.FormData.label` of its own, since the heading names it. Kirigami centres a section
  heading over both columns by design.
- **A dependent control greys out with `enabled:`, keeping its value**, so turning its parent back
  on restores it. The exceptions are deliberate: picking "Filled & ring" moves a stored "Hollow
  ring" occupancy style to "Filled", and that item is disabled in the combo while the style is on.
- **The runtime applies the same gates as the page**: `Logic.pillClickAnywhereActive` keeps the
  whole-widget click target off while the click action is "Nothing", as the greyed checkbox says.
- **The pages are e2e-only** (the dialog needs `org.kde.plasma.configuration`); the four shared
  controls are Kirigami-only and unit-tested by `tests/unit/tst_config*.qml`.
