# Tests

Headless QML unit tests for the pager, run with [`qmltestrunner-qt6`] and the `QtTest`
QML module (both shipped with Qt 6). These live **outside** `package/` on purpose — only
`package/contents/` is shipped in the KPackage, so nothing here ends up in the installed widget.

## Running

```bash
make check          # from the repo root — runs every tests/tst_*.qml headless
```

`make check` sets `QT_QPA_PLATFORM=offscreen` so Kirigami initialises without a display
(`qmltestrunner` runs a `QGuiApplication`; without the offscreen platform it aborts trying to
connect to a display). To run a single file directly:

```bash
QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input tests/tst_workspaceindicator.qml
```

## What can and cannot be tested

- **Testable:** the Kirigami-only visual components (`WorkspaceIndicator`, `WorkspaceDot`).
  They read desktop state through a duck-typed `virtualDesktopInfo` property, so a plain
  `QtObject` mock substitutes for `TaskManager.VirtualDesktopInfo` with zero Plasma deps.
- **Not testable here:** `main.qml` / `PlasmoidItem`. It needs plasmashell, KWin and a session
  bus (`VirtualDesktopInfo`, KWin `DBus.asyncCall`) and is meaningless headless. It stays on the
  manual loop (`make dev` → `make test` → `make restart`, then switch desktops by keyboard).

## Adding a test

Create `tests/tst_<thing>.qml` (the `tst_` prefix is required — `qmltestrunner` only discovers
that pattern):

```qml
import QtQuick
import QtTest
import "../package/contents/ui" as Pager   // for component tests

TestCase {
    name: "MyThing"
    when: windowShown

    // Mock VirtualDesktopInfo for component tests:
    QtObject {
        id: vdiMock
        property var desktopIds: ["uuid-a", "uuid-b"]
        property string currentDesktop: "uuid-b"
    }

    function test_something() {
        compare(actual, expected);   // also: verify(cond), fuzzyCompare, tryCompare
    }
}
```

Conventions:
- **Component tests** directory-import `../package/contents/ui` and instantiate via a
  `Component` + `createTemporaryObject` (auto cleanup). Mock `virtualDesktopInfo` with a
  `QtObject`. Use `SignalSpy` to assert emitted signals; you can emit a signal directly
  (`dot.activated()`) instead of simulating a headless mouse click.
- **Assert against theme/units tokens, never literals** — compare colors to `Kirigami.Theme.*`
  and sizes to `Kirigami.Units.*`, so tests stay theme-, HiDPI- and offscreen-independent.

## Roadmap note

A zero-dependency **pure-JS logic tier** arrives at **Milestone 3**: the first real branching
logic (scroll `step()` with index clamp/wrap, "never remove the last desktop") will be extracted
into `package/contents/ui/logic.js` (`.pragma library`) and unit-tested by a `tst_logic.qml`
that imports the `.js` directly — no Plasma/Kirigami needed, so it can run on any bare
`qt6` + `qttest` environment (and in CI). CI (qmllint + tests on push) is planned for
Milestone 7.

[`qmltestrunner-qt6`]: https://doc.qt.io/qt-6/qtquicktest-index.html
