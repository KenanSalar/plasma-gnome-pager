# QML / Qt Quick Performance Best Practices

A panel widget is **always instantiated and always on screen**, so its cost is paid for the
whole session. Keep the compact representation cheap. General QML perf, tuned for a pager.

## Bindings

- **Declarative bindings beat imperative assignment** — they're optimized, evaluated lazily,
  and avoid the desync bugs of `Component.onCompleted: x = ...`.
- **Keep binding expressions trivial.** A binding re-runs whenever any dependency changes; heavy
  JavaScript inside one is re-executed each time. Precompute into a plain property and bind to
  that. Avoid allocating arrays/objects inside a hot binding.
- **Avoid binding loops** — they thrash the evaluator every frame until they settle (or never).
  `qmllint` and the console flag them.

## Positioning & layout

- **Anchors over binding-based positioning.** Binding `x`/`y` to expressions is dynamic but
  costs more than anchors, which the scene graph handles natively.
- **In delegates (Repeater/ListView), prefer plain `x`/`y`/`width`/`height` bindings over
  Layouts/anchors.** `RowLayout`/`GridLayout` and anchors cost more memory and instantiation
  time per item — measurable when a delegate is repeated. For the small dot strip a simple
  `Row` positioner is ideal.

## Item count & instantiation

- A pager has a handful of dots → **`Repeater`** is correct (eager, no flickable overhead).
  Don't reach for `ListView` virtualization here; it adds a flickable and recycling machinery
  you don't need.
- Reserve `ListView`/`GridView` (delegate recycling) for genuinely long/unbounded lists.
- Defer rarely-shown subtrees with `Loader { active: ... }` (e.g. a popup), and consider
  `asynchronous: true` on a Loader for heavy content so it doesn't block the first frame.

## Rendering cost

- **Avoid `Canvas`/`onPaint`** — it renders on a separate surface and is slow. Draw circles
  with `Rectangle { radius: width/2 }`, vectors with `QtQuick.Shapes`, icons with
  `Kirigami.Icon`.
- **`clip: true` and `layer.enabled: true` each allocate an offscreen buffer (FBO)** and add a
  render pass — use only when truly needed. Don't clip the dot strip if nothing overflows.
- **`visible: false` removes an item from rendering and hit-testing**; `opacity: 0` keeps it
  rendered and hit-testable. Prefer `visible`/`if`/`Loader` to actually drop work.
- **Minimize overdraw** — avoid stacks of large opaque/translucent rectangles; let the panel
  background show through (`NoBackground`) rather than painting your own opaque fill.
- **Images**: set `sourceSize` so they decode at display size, not native; prefer SVG via
  `Kirigami.Icon`. Same `source` is cached.

## Animation

- `Behavior on x/width { NumberAnimation }` (the pill slide) is cheap and GPU-friendly.
- But **every concurrently-running `animate`/animation is re-evaluated each frame** — don't run
  many at once. For periodic/derived motion, prefer a single shared `Timer` + math over N
  independent animations.
- Tie durations to `Kirigami.Units.{short,long}Duration` and **guard against 0** (animations
  disabled) before using a duration as a divisor.

## Build-time / tooling

- Run **`qmllint`** (correctness + perf smells) and consider the **QML type compiler** path
  (`pragma ComponentBehavior: Bound`, fully-typed properties) so more is resolved ahead of time
  instead of at runtime.
- Type everything: typed `int`/`real`/`color` properties optimize better than `var`.

## Pitfalls

- **Heavy work in a frequently-re-evaluated binding** — the usual cause of a janky panel widget.
  Move it out, cache the result.
- **Unnecessary `layer.enabled`/`clip`** on a container with children — silent offscreen FBO +
  extra pass, and on some renderers blurs/upscales the subtree on HiDPI.
- **Leaving a popup/full representation eagerly built** — wrap it in a `Loader` so it costs
  nothing until opened.
