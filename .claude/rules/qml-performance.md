---
paths:
  - package/contents/ui/*.qml
---

# Keeping the widget cheap

A panel widget is built at login and drawn for the whole session, so its cost never goes away.
The settings pages are exempt: the dialog builds them on demand.

- **Measure before optimising.** A guess about cost is not a reason to complicate a binding.
- **Keep binding expressions trivial.** A binding re-runs on every dependency change; a heavy one
  goes into a `readonly property` the others read, or into `logic.mjs`. The `Array.from` copies of
  `desktopIds` and `desktopNames` are the deliberate exception, a handful of strings per change.
- **Filter the window model's churn at the source**: a `dataChanged` that touches only roles no
  consumer reads (window focus fires constantly) doesn't rebuild, a burst of changes coalesces
  into one deferred rebuild, and an output that didn't change isn't reassigned.
- **Draw with `Rectangle` and its `radius`**, never `Canvas`. `clip` and `layer.enabled` each add
  an offscreen buffer and a render pass, and nothing here overflows.
- **Drop what isn't shown**: the hover background is `visible: opacity > 0`, and the occupancy
  overlay and the window model are behind `Loader`s, so a dot without a marker builds no overlay
  and a configuration with every window consumer off builds no model.
- **Animate with `Behavior`**, gated off before the first placement and when the duration is 0.
  A switch runs two dots' animations at once; anything that would run one per dot continuously
  belongs on one shared `Timer` instead.
