---
paths:
  - package/contents/ui/main.qml
  - package/contents/ui/WindowAggregator.qml
  - package/contents/ui/DynamicWorkspacesController.qml
  - package/contents/ui/coordinator.js
  - package/contents/ui/logic.js
  - tests/unit/tst_coordinator.qml
  - tests/integration/tst_dynamicworkspacescontroller.qml
---

# Windows, occupancy and dynamic workspaces

## The window model

**The widget holds one `TasksModel`, in `WindowAggregator.qml`, filtered by neither desktop nor
activity**, behind a `Loader` in `main.qml` that runs while any consumer is on.
`Logic.reduceWindowSnapshot` turns each snapshot into three outputs:

| output | windows counted | read by |
|--------|-----------------|---------|
| `desktopTooltips` | every screen, current activity | the dot tooltips |
| `screenOccupancy` | this pager's screen, current activity | the occupied-dot markers |
| `desktopOccupancy` | every screen, every activity | `DynamicWorkspacesController` |

- **A feature that needs windows reads one of these outputs or adds a fourth, never a second
  model.**
- **Each consumer has its own switch on the aggregator** (`windowListActive`, `occupancyActive`,
  `dynamicActive`), and both `relevantRoles` and the reductions follow it. A new consumer adds its
  switch and its roles, or it costs work while off and misses changes while on.
- **`main.qml` gates `desktopTooltips` on `showTooltips && showWindowList` itself**: the loader
  also runs for occupancy alone.
- **An output is reassigned only when `Logic.arraysShallowEqual` says it changed**; a `var`
  notifies on every new reference, waking the controller and every dot.
- **A window's screen is matched by the origin of its `ScreenGeometry` against
  `Screen.virtualX`/`virtualY`**, as there is no screen-name role and the sizes differ under
  per-output scaling. Nothing headless checks that the two share a coordinate space, so a change
  here is tried on a real multi-monitor setup, where a mismatch marks nothing occupied.

## Dynamic workspaces

- **`Logic.dynamicWorkspacePlan` returns at most one action and is re-run as each write lands**,
  so it always acts on the set KWin reports. It leaves empty desktops in the middle alone.
- **The controller sends nothing while its busy lock holds**, from its write until
  `desktopIdsChanged`, with `busyFallbackMs` for a write that never lands.
- **Only the elected writer adds or removes desktops** (`Coordinator.isWriter`): every panel sees
  the last desktop fill, and two writers would both add one.
- **`dynamicWorkspaces` and `dynamicNamePrefix` are one value across panels.** A change goes
  through `Coordinator.publish`, each controller re-emits it as `syncConfigRequested`, and
  `main.qml` writes it into its own `Plasmoid.configuration`. Both sides write only a value that
  differs, which keeps the sync from looping.
- **Nothing reaches the coordinator before `join()`**: config `onChanged` handlers run before
  `Component.onCompleted`, and a write with token `0` registers a phantom instance that wins the
  election.
- **Dynamic workspaces and the menu's Add/Remove exclude each other**: `main.qml` hides the
  entries while the global setting is on, and `ConfigGeneral` greys the checkbox without
  changing it.
- **The live model and the sharing between real panels are checked only in the shell**;
  `tst_coordinator.qml` and `tst_dynamicworkspacescontroller.qml` hold the election and the state
  machine.
