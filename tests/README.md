# Tests

Headless QML tests for the pager, run with [`qmltestrunner-qt6`] and the `QtTest`
QML module (both shipped with Qt 6). These live **outside** `package/` on purpose — only
`package/contents/` is shipped in the KPackage, so nothing here ends up in the installed widget.

## Test tiers (architecture)

The suite is split by **what is real vs mocked**. Headless `qmltestrunner` can never touch
real plasmashell/KWin/DBus, so that boundary defines the tiers:

| Tier | What it covers | Real | Mocked | Folder |
|------|----------------|------|--------|--------|
| **unit** | One first-party component in isolation | the component (`WorkspaceDot`) | everything it depends on (plain props) | `tests/unit/` |
| **integration** | Several first-party components composed + reactive wiring | `WorkspaceIndicator` + its real `WorkspaceDot` delegates + pill + `Repeater` | the platform — a duck-typed `QtObject` stands in for `TaskManager.VirtualDesktopInfo` | `tests/integration/` |
| **e2e / system** | The real plasmoid switching real desktops | plasmashell + KWin + session-bus DBus | nothing | *not automated* |

- **unit** (`tests/unit/`) — `tst_workspacedot.qml`. A single component driven only by
  properties; no data source to mock. Also the home of the future pure-JS `logic.js` tests
  (see the roadmap note below).
- **integration** (`tests/integration/`) — `tst_workspaceindicator.qml`. The indicator
  instantiates real `WorkspaceDot` delegates through a `Repeater`, overlays the pill, and
  flows reactivity through the binding chain (`vdi → desktopIds/currentDesktop → activeIndex
  → pillX → dot.active`). That cross-component wiring is the integration; the only thing
  mocked is the external platform, because the real `VirtualDesktopInfo` needs a Plasma
  session — which is the e2e tier.
- **e2e / system** — running the real widget against live KWin + DBus and switching desktops.
  This is **not** automated (and likely never needs to be for a pager): it stays the manual
  loop `make dev` → `make test` → `make restart`, then switch desktops by keyboard and watch
  `journalctl --user -f -t plasmashell`. If it ever *were* scripted it would live in a
  `tests/e2e/` folder, but that folder is deliberately not created until there's something to
  put in it.

`main.qml` / `PlasmoidItem` is therefore **not** unit/integration testable: it needs
plasmashell, KWin and a session bus and is meaningless headless. It is covered only by the
e2e (manual) loop.

## Running

```bash
make check              # all tiers headless (unit + integration)
make check-unit         # only tests/unit
make check-integration  # only tests/integration
```

`make check*` sets `QT_QPA_PLATFORM=offscreen` so Kirigami initialises without a display
(`qmltestrunner` runs a `QGuiApplication`; without the offscreen platform it aborts trying to
connect to a display). To run a single file directly:

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input tests/unit/tst_workspacedot.qml
```

## Adding a test

Put it in the right tier folder and name it `tst_<thing>.qml` (the `tst_` prefix is required —
`qmltestrunner` only discovers that pattern):

- a single component in isolation → `tests/unit/`
- components wired together / reactivity → `tests/integration/`

**Import depth:** test files are now two levels under the repo root, so the component import is
`import "../../package/contents/ui" as Pager` (note the `../../`).

```qml
import QtQuick
import QtTest
import "../../package/contents/ui" as Pager   // for component tests

TestCase {
    name: "MyThing"
    when: windowShown

    // Mock VirtualDesktopInfo for integration tests (duck-typed; the indicator only reads
    // .desktopIds and .currentDesktop):
    QtObject {
        id: vdiMock
        property var desktopIds: ["uuid-a", "uuid-b"]
        property string currentDesktop: "uuid-b"
    }

    function test_something() {
        compare(actual, expected);   // also: verify(cond), fuzzyCompare, tryCompare, tryVerify
    }
}
```

Conventions:
- **Component tests** directory-import `../../package/contents/ui` and instantiate via a
  `Component` + `createTemporaryObject` (auto cleanup). Mock `virtualDesktopInfo` with a
  `QtObject`. Use `SignalSpy` to assert emitted signals; you can emit a signal directly
  (`dot.activated()`) instead of simulating a headless mouse click — except when the click
  path itself is what you're testing (e.g. hit areas / click-through), where `mouseClick()`
  is the point.
- **Reactivity** is tested by mutating the mock (`vdi.currentDesktop = …`,
  `vdi.desktopIds = […]`) and letting the bindings update; use `tryCompare`/`tryVerify` to
  tolerate animation duration and sub-pixel rounding.
- **Assert against theme/units tokens, never literals** — compare colors to `Kirigami.Theme.*`
  and sizes to `Kirigami.Units.*` (or to other derived geometry via `mapToItem`), so tests
  stay theme-, HiDPI- and offscreen-independent.

## Roadmap note

A zero-dependency **pure-JS logic tier** arrives at **Milestone 3**: the first real branching
logic (scroll `step()` with index clamp/wrap, "never remove the last desktop") will be extracted
into `package/contents/ui/logic.js` (`.pragma library`) and unit-tested by
`tests/unit/tst_logic.qml`, which imports the `.js` directly — no Plasma/Kirigami needed, so it
runs on any bare `qt6` + `qttest` environment (and in CI). CI (qmllint + tests on push) is
planned for Milestone 7.

[`qmltestrunner-qt6`]: https://doc.qt.io/qt-6/qtquicktest-index.html
