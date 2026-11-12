---
paths:
  - "**/*.qml"
---

# QML

Qt 6 QML as this tree writes it. `kirigami.md` has units and theme, `qml-performance.md` the
cost of the always-on widget, `code-style.md` the comment format.

## Files and imports

- **One component per file**, the filename its type name; siblings in a directory need no import.
  A one-off type used only inside one file is an inline `component` there (`WindowRow`).
- **The widget's components open with `pragma ComponentBehavior: Bound`**, which scopes delegate
  ids and `required property` bindings and lets the engine compile more ahead of time. A settings
  page needs it once a delegate reads an outer id, as `ConfigAppearance`'s combo delegate does.
- **Imports are aliased and every use qualified** (`Kirigami.Units.smallSpacing`); `logic.mjs`
  comes in `as Logic`, one directory up from the settings pages.
- **The JavaScript is ES modules (`.mjs`), never `.pragma library` scripts**: oxlint and oxfmt
  parse only standard JavaScript, which `.pragma` and `.import` aren't. The QML sees only what a
  module `export`s; `coordinator.mjs`'s header says why every pager shares its state.

## Properties and bindings

- **An input is a typed property with a default**, taken from `Logic.DEFAULTS` when it mirrors a
  setting. `required property` is for delegates (`modelData`, `index`), never for anything Plasma
  instantiates.
- **Derived values are `readonly property` bindings.** Imperative assignment breaks a binding
  without a warning; the one source that needs it is a method with a signal
  (`currentDesktopByScreenName`), modelled as one property recomputed in one function.
- **`var` is for arrays and objects.** A `var` notifies on every reassignment, even to an equal
  array, so compare before assigning; a binding that must notify after an in-place change returns
  a fresh copy.
- **A model role that can be `undefined` lands in a `var`**: a typed property such as `rect`
  refuses `undefined`, logs it, and keeps its previous value.
- **A capitalised model role isn't a valid property name**: read it off `model`
  (`model.VirtualDesktops`), and only a lowercase role like `display` can be `required`.
- **Don't name an input after an `Item` property**: `enabled`, `visible` and `state` already
  exist. Name it for what it switches, as `dynamicEnabled` does.
- **A binding loop means a rendered value feeds back into what sizes it**; qmllint and the
  console both report one.

## Signals and connections

- **Custom signals are declared typed** (`signal switchRequested(string uuid)`) and handled with
  arrow functions that name their parameters.
- **`Connections` use function handlers** (`function onDesktopIdsChanged() {}`). A handler for a
  signal the target may lack goes in its own block with `ignoreUnknownSignals: true`.
- **Handlers stay thin**: anything with a branch calls a named function, and a pure branch lives
  in `logic.mjs`.

## Types qmllint can't see

- **`Loader.item` and `Instantiator.objectAt()` are `QObject`**: cast them to the named type
  (`aggregatorLoader.item as WindowAggregator`, `objectAt(i) as WindowRow`) before reading a property,
  or qmllint reports `missing-property`.
- **`.contextProperties.ini` declares the `i18n*` and `Plasmoid` globals**, which Plasma injects at
  runtime. If they start warning as unqualified, qmllint isn't finding that file; it isn't a code
  defect.

## Layout and instantiation

- **Positioners (`Grid`) for the strip, `Layout`s for the settings pages and the dialog.** Don't
  set `width: parent.width` and anchor the same axis.
- **A `Repeater` builds the dots**, a handful of eager delegates; a `ListView` would add a
  flickable and recycling for nothing.
- **`visible: false` keeps an item's cost; a `Loader` drops it.** A subtree most configurations
  never show goes behind one, as the window model and the occupancy overlay do.
- **Work a component behind a `Loader` defers goes on a child `Timer`, never `Qt.callLater`**, as
  `WindowAggregator.scheduleRebuild` does: the timer goes with the component when it unloads.

## Tooling

`make lint` treats a qmllint warning as an error. `qmlformat-qt6` isn't a gate and the tree isn't
formatted with it, so don't run it over a file you're only touching.
