# QML / Qt Quick 6 Best Practices

Language-level conventions for the QML in this widget. Plasma-specific structure is in
`plasmoid.md`; theming/units in `kirigami.md`; rendering cost in `qml-performance.md`.

## Imports

- **Un-versioned imports** in Qt 6 / Plasma 6: `import QtQuick`, not `import QtQuick 2.15`.
- Alias multi-symbol modules (`import org.kde.kirigami as Kirigami`) and always qualify
  (`Kirigami.Units.smallSpacing`) — unqualified access is slower and `qmllint`-hostile.
- Keep imports to the public surface in `robustness.md`.

## File & component structure

- **One component per file**, PascalCase filename = component name. Files in the same directory
  are importable by filename with no explicit import (`WorkspaceDot {}` from
  `WorkspaceDot.qml`).
- Start reusable components with `pragma ComponentBehavior: Bound` — it scopes delegate/
  Repeater `required property` bindings correctly and lets the engine optimize. Use
  `required property` for inputs a parent must supply.
- Give every non-trivial element an `id`. The root `id` is conventionally `root`.

## Properties & bindings

- **Declare a typed property over juggling state imperatively**: `property int activeIndex: ...`.
  Prefer `readonly property` for derived values.
- **Prefer declarative bindings to imperative assignment.** `color: active ? a : b` — not
  setting `color` inside `Component.onCompleted` or a signal handler. Imperative assignment
  *breaks* the binding and desyncs on the next dependency change.
- Don't fight bindings: to combine a binding with occasional manual writes, model the source of
  truth as one property and bind everything else off it.
- Expose child internals with `property alias` (used heavily for `cfg_<key>` config aliases).
- Use `Behavior on <prop> { NumberAnimation { duration: ... } }` for smooth transitions
  (the pill slide) instead of hand-driven animations.

## Signals & handlers

- Declare custom signals (`signal activated()`); handle with `onActivated:`. Connect across
  objects with `Connections { target: x; function onFoo() { ... } }` (Qt 6 function-style
  handlers, not the old `onFoo:` string form).
- Keep handlers thin — call a named function for anything non-trivial so it's testable and
  re-usable.

## Layout & positioning

- **Anchors** for relative positioning (`anchors.centerIn: parent`); **`Row`/`Column`/`Grid`**
  (positioners) for evenly-laid sequences like the dot strip; **`RowLayout`/`ColumnLayout`/
  `GridLayout`** only when you need stretch/fill/alignment distribution.
- Reserve absolute `x`/`y` for overlays and computed positions (e.g. the sliding pill bound to
  the active dot's geometry).
- Never set `width: parent.width` *and* anchor the same axis — pick one.

## Repeater vs ListView

- **`Repeater`** instantiates every delegate eagerly — correct for a small, fixed count like a
  handful of virtual-desktop dots. Drive it with `model: vdi.desktopIds` or `model:
  vdi.numberOfDesktops`.
- **`ListView`/`GridView`** virtualize (recycle delegates) — use only for long/unbounded lists.
  Overkill (and adds a flickable) for a pager.

## Visibility & loading

- `visible: false` stops rendering/hit-testing but the item still occupies layout space; for a
  positioner/layout child use `if (cond) Item {}` (or a `Loader`) to truly drop it.
- `Loader { active: cond; sourceComponent: ... }` defers building rarely-shown subtrees
  (e.g. a popup `fullRepresentation`).

## i18n

- Wrap all user-visible strings: `i18n("text")`, `i18nc("context", "text")`,
  `i18np("%1 desktop", "%1 desktops", n)`. These are globally available in plasmoids.
- Don't translate icon names, theme tokens, DBus identifiers, or proper nouns
  ("KDE", "GNOME").

## Tooling

- Run **`qmllint`** on every file (catches removed Plasma 6 symbols, unqualified lookups,
  binding loops) and **`qmlformat`** to normalize style. Treat `qmllint` warnings as errors.

## Common pitfalls

- **Imperative assignment silently kills a binding** — the property stops updating with no
  error. If a value "won't update," check whether something assigned it imperatively.
- **Binding loops** (`A.width` depends on `B.width` depends on `A.width`) — `qmllint`/console
  warns; break by anchoring or introducing an independent source property.
- **`var` for numbers/strings** — prefer typed `int`/`real`/`string`/`bool`/`color` properties;
  `var` defeats engine optimizations.
- **Reading `parent` in a component's root binding** is fragile — pass host metrics in as
  explicit `required property`s.
- **JS array identity**: `vdi.desktopIds` returns a fresh array; comparing it by reference
  across changes won't work — compare by length/contents or bind to specific elements.
