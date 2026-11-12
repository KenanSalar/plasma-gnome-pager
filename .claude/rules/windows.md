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

## One model, three outputs

`WindowAggregator.qml` holds the one `TasksModel`, unfiltered by desktop and activity, behind a
`Loader` in `main.qml` that is active while any of its three consumers is on. One snapshot goes
through `Logic.reduceWindowSnapshot`:

| output | windows counted | consumer |
|--------|-----------------|----------|
| `desktopTooltips` | every screen, current activity | the dot tooltips |
| `screenOccupancy` | this pager's screen, current activity | the occupied-dot markers |
| `desktopOccupancy` | every screen, every activity | `DynamicWorkspacesController` |

- **Each consumer reaches the aggregator as its own bool** (`windowListActive`, `occupancyActive`,
  `dynamicActive`). Both the roles that wake a rebuild and the reductions it computes follow them,
  so a feature that's off costs nothing and its output stays `[]`.
- **`main.qml` gates `desktopTooltips` on `showTooltips && showWindowList` itself**: the `Loader`
  can be live for occupancy alone, and the window list mustn't come back with it.
- **Each output is reassigned only when `Logic.arraysShallowEqual` says it changed.** A `var`
  notifies on every new reference, and the controller and every dot re-evaluate on it.
- **A window's screen is matched by the origin of its `ScreenGeometry` against the pager's
  `Screen.virtualX`/`virtualY`**: there is no screen-name role, and width and height differ
  between the two under per-output scaling. That both share one coordinate space is verified only
  on a real multi-monitor rig; a mismatch would mark nothing occupied.

## Dynamic workspaces

- **`Logic.dynamicWorkspacePlan` returns one action per evaluation**: add when no desktop at the
  end is empty, remove the last when two or more are, else nothing. Each landed write re-triggers
  the evaluation, so it converges on one empty trailing desktop. Empty desktops in the middle are
  left alone.
- **The controller holds a busy lock from its write until `desktopIdsChanged`**, with a timer as
  the fallback, so it can't fire again before its own change shows.
- **`coordinator.js` is one instance per plasmashell engine, shared by every pager.** It elects
  the lowest present token as the only instance that writes, so two panels don't both add a
  desktop when the last one fills. It also holds `dynamicWorkspaces` and `dynamicNamePrefix` as
  one global value: each controller re-emits a published change as `syncConfigRequested`, and
  `main.qml` writes it into its own `Plasmoid.configuration`.
- **Nothing reaches the coordinator before `join()`**: config `onChanged` handlers run before
  `Component.onCompleted`, and a write with token `0` registers a phantom instance that wins the
  election. `join()` never returns `0`.
- **The sync can't loop**: `main.qml` writes only a value that differs, and the controller
  republishes only one that differs from the coordinator's.
- **Dynamic workspaces and the menu's Add/Remove exclude each other**: `main.qml` hides the
  entries on every panel while the global setting is on, and `ConfigGeneral` greys the checkbox
  without changing it.
- **The live model and the sharing across real panels are e2e-only**; `tst_coordinator.qml` and
  `tst_dynamicworkspacescontroller.qml` hold the election and the state machine.
