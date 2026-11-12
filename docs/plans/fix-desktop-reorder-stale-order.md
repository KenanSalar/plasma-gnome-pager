# Fix: pager keeps the old desktop order after KWin reorders desktops

## Context

**Symptom.** You move desktop 1's apps to desktop 3 in the Overview Grid. Afterwards the pager shows the wrong desktop as current ("I'm still on the first"). Scrolling jumps to the wrong desktops ("a fight for the first workspace"). Only removing every desktop but one, then re-adding them, fixes it. Repeating the Grid action breaks it again.

**Root cause (confirmed live and in upstream source).**
1. **The Grid move was a desktop move, not a window move.** Dragging a desktop cell by its background in the Grid drags the whole desktop, apps included (`kwin-desktop` drop key). That calls `Workspace.moveDesktop(…)` (KWin 6.7.5 `src/plugins/overview/qml/Main.qml:601-607`), which reorders the desktops. The live trace confirms it:
   - KWin's order is now `[8260…, aec1…, 737b…]`. `737b…` is your original desktop 1 (the one that survived the "revert"), and it is now last.
   - KWin's current desktop is `737b…`, which is correct.
2. **libtaskmanager re-sorts silently.** `VirtualDesktopInfo` re-sorts its internal list on the protocol's `done` event. It then emits only `desktopPositionsChanged` (added in Plasma 6.5), never `desktopIdsChanged` or `desktopNamesChanged` (plasma-workspace 6.7.5 `libtaskmanager/virtualdesktopinfo.cpp`, `done` handler).
3. **Our bindings never re-read.** `WorkspaceIndicator.qml:26-27` binds `desktopIds`/`desktopNames` to the vdi, and those bindings only re-evaluate on the `*Changed` notifies. So the dots keep the old order:
   - The pill on `737b…` sits on dot 1.
   - `handleWheel` steps through the stale order, and the DBus `Set current` writes target the wrong neighbours. The trace caught the pager alternating `Set current` between `8260…` and `737b…`.
4. **Why removing desktops "fixed" it.** Removing or adding a desktop emits `desktopIdsChanged`, which re-reads the now-correct order.
5. **The stock pager is immune.** Its `PagerModel` connects `desktopPositionsChanged` and refreshes.

**Also stale:**
- `WindowAggregator` only rebuilds on `desktopIdsChanged`. Its occupancy and tooltip arrays, which are index-aligned with `desktopIds`, stay in the old order. That puts occupied markers and window lists on the wrong dots, and feeds the dynamic-workspaces controller misaligned occupancy.
- Function-time reads (`main.qml` remove-last/rename, the controller's `evaluateDynamic`) call the C++ getter fresh, so they are fine.

## Approach

Treat `desktopPositionsChanged` as an order change everywhere the desktop order is bound. Follow the existing `ScreenCurrentDesktop` pattern: a non-visual resolver that recomputes imperatively because the source doesn't notify.

### 1. New `package/contents/ui/DesktopList.qml` (non-visual, mirrors `ScreenCurrentDesktop.qml`)
- Input: `property var virtualDesktopInfo: null`.
- Outputs: `property var desktopIds: []` and `property var desktopNames: []`, in KWin's current order.
- `refreshIds()` / `refreshNames()` copy the source (`Array.from(vdi?.desktopIds ?? [])`). A copy guarantees a fresh reference, and a `var` property only notifies on a new reference.
- A plain `Connections` block for `onDesktopIdsChanged` → ids and `onDesktopNamesChanged` → names.
- A **separate** `Connections { ignoreUnknownSignals: true }` for `onDesktopPositionsChanged` → both. The signal is Plasma 6.5+, so 6.0–6.4 must stay warning-free. This is the same split `ScreenCurrentDesktop` uses for its 6.7-only signal.
- `onVirtualDesktopInfoChanged` and `Component.onCompleted` refresh both.
- Header comment explains the gotcha: libtaskmanager re-sorts in place and signals only positions.

### 2. `package/contents/ui/WorkspaceIndicator.qml`
- Replace the two bindings at lines 26-27 with forwards: `readonly property var desktopIds: desktopList.desktopIds` (same for names).
- Instantiate `DesktopList { id: desktopList; virtualDesktopInfo: indicator.virtualDesktopInfo }` next to `ScreenCurrentDesktop`. As a child it resolves in its own `onCompleted` before the indicator's, so the `animate` latch at lines 243-247 still sees a valid `activeIndex`.
- Update the file header ("delegates … the desktop order to DesktopList").
- Everything downstream needs no other change: `lines`, `activeIndex`, `handleWheel`, the Repeater models, names, and the `onDesktopIdsChanged` hover reset.

### 3. `package/contents/ui/WindowAggregator.qml`
- Add a second `Connections { target: aggregator.virtualDesktopInfo; ignoreUnknownSignals: true }` with `onDesktopPositionsChanged → scheduleRebuild()`. `rebuild()` already reads ids fresh, so its index-aligned outputs come out in the new order.
- Compare-before-assign still suppresses no-op reassigns.
- This also re-aligns `desktopOccupancy` for the dynamic controller, which then re-evaluates via `onDesktopOccupancyChanged`.

### 4. No change needed
- `DynamicWorkspacesController.qml`: reads ids at evaluation time and is triggered by the aggregator's re-aligned occupancy.
- `main.qml`: its reads are function-time, so always fresh.
- `ScreenCurrentDesktop.qml`: works on UUIDs, so order doesn't matter.

### 5. Tests
- `tests/shared/VdiMock.qml`:
  - Add `signal desktopPositionsChanged()`.
  - Add a `reorder(order)` helper that re-sorts `desktopIds` and `desktopNames` **in place** (splice, so no `*Changed` fires) and emits only `desktopPositionsChanged()`. That faithfully models libtaskmanager.
  - Update the header to list the new member.
- New `tests/unit/tst_desktoplist.qml`, mirroring `tst_screencurrentdesktop.qml`. Cases:
  - initial read
  - follows `desktopIdsChanged` and `desktopNamesChanged`
  - `reorder()` re-reads both and fires the list's own `desktopIdsChanged` (SignalSpy)
  - a legacy source without the signal loads and reads
  - a null source gives `[]`, and a late-injected source re-reads
- `tests/integration/tst_indicator_input.qml`: `test_scrollFollowsReorderedDesktops`. Use `["uuid-a","uuid-b","uuid-c"]` with current `uuid-a`, then `vdi.reorder(["uuid-b","uuid-c","uuid-a"])`. Assert `activeIndex === 2`. A real `mouseWheel` up must emit `switchRequested("uuid-c")`, KWin's previous desktop, not `uuid-b`.
- `tests/integration/tst_indicator_content.qml`: `test_dotsFollowReorderedDesktops`. After `reorder`, assert the dot `modelData` order, the capsule on the moved desktop, and that `desktopName` moves with its desktop.
- Mutation check: drop the positions `Connections` and confirm the new tests fail.

### 6. Docs (no new strings, so no `make messages`)
- `CLAUDE.md`, Architecture / read-write split: add a gotcha. **`desktopIds` is not re-notified on a reorder.** libtaskmanager emits only `desktopPositionsChanged` (6.5+). Reorders come from the Overview Grid's desktop drag and the KCM. `DesktopList` and the aggregator listen for it, and function-time reads are fresh. Guarded by the tests above.
- `.claude/rules/virtual-desktops.md`: add `desktopPositionsChanged` beside the reactive-properties table, with the same note.
- Correct the inaccurate claim at `CLAUDE.md:67` and `.claude/rules/virtual-desktops.md:61` ("interacting with a pager makes its output active"):
  - KWin routes the global `current` write to its **active output**: the one the pointer last moved on, or the last-activated window's.
  - Moving to the pager normally makes that its own output.
  - The stock pager targets its own output via `requestActivateOnScreen`, which is C++-only (not `Q_INVOKABLE`, still true on upstream master).

No commits, staging or branching unless you ask.

## Verification
1. `make verify` (lint + lint-js + check): all green, zero qmllint warnings.
2. Ask before running `make restart` to reload the live panel.
3. In-shell repro (both monitors):
   - Open the Grid (Meta+G). Drag desktop 1's cell by its background onto desktop 3.
   - The dots should reorder immediately, and the pill should sit on the moved desktop at position 3.
   - Scrolling should step through KWin's order. Cross-check with `busctl --user get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager desktops current`.
   - Occupied markers and tooltip window lists should follow their desktops.
4. `journalctl --user -t plasmashell` shows no "no signal with that name" or other new QML warnings.
