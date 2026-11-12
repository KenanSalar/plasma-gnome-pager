---
paths:
  - package/contents/config/**
  - package/contents/ui/config/**
  - tests/unit/tst_config*.qml
---

# Settings

`CLAUDE.md` lists the five edits a new setting takes; this file holds how the two pages are built.

- **A page subclasses `ConfigPageBase` and lists every key in `configKeys`**, each `{ n, t }` with
  `t` one of `bool`, `int`, `real`, `string` or `color`. A key missing from the list is neither
  compared for the Defaults action nor reset by it; the dialog's footer has no Defaults button.
- **Each key needs a `cfg_<key>` alias and a `cfg_<key>Default` property with no initializer**,
  both named exactly as the `main.xml` entry. The dialog injects the default from the schema, and
  a misspelled name loads and saves nothing without an error.
- **A combo's `currentIndex` is the stored value**: its item order, the frozen table in `logic.mjs`
  (`PILL_CLICK_ACTION`, `DOT_STYLE`, `OCCUPANCY`) and the `main.xml` comment change together, and
  the page compares the index through that table.
- **A numeric row is a `ConfigSlider`, an opacity row a `ConfigPercentSlider`**, and a sentinel's
  text goes at `from`: `format` at `from` and `to` sizes the read-out.
- **A field's width comes from `Logic.CONFIG_FIELD_WIDTH_UNITS`**: a slider's track, a combo or text
  field through `ConfigPageBase.fieldWidth`, and a `ConfigHint`'s wrap width. The slider's value
  label takes the slack, which keeps the two pages' sliders the same length.
- **Rows are grouped under `ConfigSection` headings, and a group's first control carries no
  `Kirigami.FormData.label`**, since the heading names it. Kirigami centres a section heading over
  both columns by design.
- **A dependent control greys out with `enabled:` and keeps its value**, so turning its parent back
  on restores it.
- **A setting the page greys out is gated the same way at runtime**, as
  `Logic.pillClickAnywhereActive` is for the whole-widget click target and
  `Logic.effectiveOccupancyStyle` for "Hollow ring" in "Filled & ring", whose combo shows the
  resolved style through `displayText`.
- **The pages are checked only in the shell**, the dialog needing `org.kde.plasma.configuration`;
  the four shared controls are Kirigami-only and unit-tested by `tests/unit/tst_config*.qml`.
