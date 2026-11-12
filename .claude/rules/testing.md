---
paths:
  - tests/**
---

# Testing Best Practices

Siblings own the slices this file does not: `code-style.md` binds a test's comments like any
other, `tests/README.md` maps the tiers and how to run one file, and `ci-packaging.md` the gate.
Which change earns a test at all is the `/add-tests` skill's call.

## Principles

The seven ISTQB principles, as they bear on writing a test:

- **Testing shows the presence of defects, not their absence.** A green suite is evidence,
  never proof. Report "no failures found", not "it works".
- **Exhaustive testing is impossible.** The input space always exceeds the budget, so
  choose by risk rather than by what is easy to reach.
- **Test early.** A defect costs more the later it is found. Write the test with the code.
- **Defects cluster.** A minority of modules holds the majority of defects. Put new effort
  where failures have already happened.
- **Tests wear out.** Run unchanged, a test finds less and less that is new. Revise and
  extend the suite as the code moves; repetition still earns its keep as regression protection.
- **Testing is context dependent.** Rigour follows risk: a path that destroys user data and
  one that misaligns a label do not earn the same coverage.
- **Absence of defects is a fallacy.** Code that passes every test can still be the wrong
  thing to have built.

## What a good test looks like

- **FIRST**: Fast, Independent, Repeatable, Self-validating, Timely.
- **One reason to fail.** A test that can fail for three reasons reports none of them
  clearly. Split it; a second act-and-assert round inside one function is a second test.
- **Arrange, act, assert**, in that order and separated by blank lines. Keep the act to one
  call. The layout already shows the phases, so `// Arrange` labels only narrate it.
- **Test the contract, not the implementation.** Assert on what a caller can observe: a
  property, an emitted signal and its arguments, a spec's value, the geometry a dot ends up with.
  A test that breaks on every refactor is testing the wrong surface.
- **No logic in tests.** No conditionals, loops or arithmetic around the assertion; a bug in
  the test is invisible. Table-drive with a `test_<name>_data()` function instead, each row
  carrying a `tag` and its expected value written out: each row fails under its own tag.
- **Independent and order-free.** No shared mutable state, no reliance on another test
  having run: run alone (`qmltestrunner-qt6 -input <file> Logic::test_wrappedStep`), a test gives
  the file's verdict.
- **Deterministic.** A test that fails once in fifty is worse than no test: it trains the
  team to re-run rather than to read.

## Designing the cases

- **Equivalence partitioning.** Split the input into classes handled the same way and take
  one value from each. Cover invalid partitions too, not just valid ones.
- **Boundary value analysis.** Defects concentrate at edges. For each boundary test the
  value on it and the step either side. Work the real constants, not round numbers.
- **Decision tables** where several conditions combine into one outcome. The interesting
  rows are the corners, where flags that are not each other's guard disagree: `dotStyle` ×
  `occupancyStyle` × `active` × `occupied` is the one this tree has most of.
- **State transition testing.** For a state machine the invalid transitions are the half
  worth writing: assert what it refuses as much as what it does.
- **Pairwise** when the full matrix explodes. Most combinatorial defects need only two
  factors to interact.
- **Error guessing** supplements the techniques above, never substitutes for them.
- **Negative and error paths deserve cases.** Empty, zero, one, maximum, absent, malformed,
  duplicated, out of order. Here that means a `null` source, an empty `desktopIds`, a current
  desktop not in the list, and arrays one entry shorter than the ids.
- **A test that pins only the value from the bug report pins the bug report.** Generalise to
  the partition the bug was one sample of.

## Test levels

- **Unit** for logic in isolation, **integration** for the seams between components,
  **system** for the assembled thing, **acceptance** for whether it is the right thing.
- **Pyramid, not ice cream cone.** Many fast unit tests, fewer integration, fewest
  end-to-end. Higher levels are slower, flakier and worse at localising a defect.
- **Push each question to the lowest level that can answer it.** A rule a pure function can
  decide belongs in `logic.js` with its case in `tst_logic.qml`, not behind a built indicator.
- **A level that cannot answer a question honestly should not fake it.** The integration tier
  runs against `VdiMock`: it pins how the components wire together, not what Plasma does with
  the result. The panel's allocation, the real KWin writes, tooltip placement, the AT-SPI tree,
  `coordinator.js` shared across real panels and the settings pages answer only in-shell.

## QtTest: organizing tests

- **A `tst_<thing>.qml` per component or JS module, one `TestCase` with a `name`, a `test_`
  function per case.** qmltestrunner runs only functions with that prefix; `init()` and
  `cleanup()` run around each one.
- **The indicator suites derive from `tests/shared/IndicatorTestCase.qml`**, which owns the
  factory, the doubles, the spies, the fixtures and the locators. A new indicator test goes into
  the `tst_indicator_*` file for its concern and uses those; it doesn't build its own.
- **`tests/shared/VdiMock.qml` is the one `VirtualDesktopInfo` double**, duck-typed to exactly
  the members the code reads. A new member the code reads goes there, with a default that keeps
  every existing test's meaning.
- **Find an item by what it carries, never by child order** (`tests/shared/elements.js`): the
  dots sit inside tooltips and nested positioners whose shape changes with the layout.
- **Build what a test owns with `createTemporaryObject`**, which destroys it after that test, and
  copy a shared fixture array before handing it over (`VdiMock.reorder` re-sorts in place).

## Walks over a collection

`test_mainXmlDefaultsMatchLogicDefaults` walks `main.xml` and holds `Logic.DEFAULTS` to it, and
a walk rots in silence: one that matches nothing passes, taking every pin standing on it along.
Each walk owes five things, none of which a passing run can show:

- **A vacuity floor**, the fewest entries the walk must find; a loop over nothing passes.
- **An equality, not a floor, wherever a vanishing member is the failure.** The `DEFAULTS` key
  set and the count of schema entries checked are compared exactly, so one key going is seen.
- **Unreadable input fails the test, never skips the entry.** A file that won't read is
  indistinguishable from one holding nothing, which is why the read is asserted non-empty first.
- **Commented-out text can't answer for the real thing.** A pattern over source text strips
  `<!-- -->` and `//` first, or a disabled entry passes for a live one.
- **An exemption held to an exact count**, each entry asserted to still be exempt:
  `wheelNotchDelta` is the one `DEFAULTS` key with no schema entry, pinned by the `- 1`.

## QtTest: timing and events

- **Wait for a state with `tryCompare` or `tryVerify`**, never a fixed `wait(ms)`: anything
  behind `Qt.callLater`, a `Behavior` or a `Timer` settles on its own schedule, and `tryCompare`
  has a timeout where a sleep has a guess.
- **A fixed `wait` is only for proving something doesn't happen**, long enough for every
  `Qt.callLater` in the path to run (the dynamic-workspaces tests wait 100 ms, then assert the
  spy stayed at its count). `wait(0)` yields one event-loop turn.
- **A glitch that heals is seen only by a synchronous assertion.** The hover background's
  dot-to-dot walk checks with `fuzzyCompare` straight after each `mouseMove`; a `tryCompare`
  there waits for the dip to heal and passes.
- **Drive input with real events**: `mouseClick`, `mouseMove` and `mouseWheel` on the item, not
  a call to its handler. Which item an event reaches is the part that breaks in a panel, and a
  handler-only test passes while the widget is dead in-shell.
- **A test that needs an animation running skips itself when `Kirigami.Units.longDuration` is
  0**, with `skip()` and the reason, since the environment may have animations off.

## QtTest: assertions

- **Every `compare` and `verify` takes the message**, naming the subject and the expectation.
  QtTest prints it on failure; a bare `verify(x)` reports only "returned FALSE".
- **Reals compare with `fuzzyCompare` and a stated delta**, geometry within half a pixel; an int,
  a bool or a string compares exactly with `compare`.
- **A spec or other plain object compares as `JSON.stringify`** of both sides, which pins key
  order too. That order is part of the `*Spec` contract, so `logic.js` builds every spec with its
  keys in one order.
- **`failOnWarning(/.?/)` in `init()` turns any warning into a failure**, as the indicator base
  does: a binding error during a re-layout, or a `Connections` handler a source has no signal
  for, otherwise only reaches the log. `ignoreWarning` takes the exact text of one expected
  warning, never a pattern broad enough to swallow others.
- **A signal is asserted through a `SignalSpy`**, its `count` and `signalArguments`, re-targeted
  and cleared per test.

## QtTest: doubles and seams

- **Prefer the real collaborator.** The indicator suites build real `WorkspaceDot` delegates and
  call the real `logic.js`; the only double is the platform, which needs a Plasma session.
- **Inject the seam as a property.** `virtualDesktopInfo`, `screenName`, `screenRect` and
  `desktopOccupancy` are plain inputs, and `DynamicWorkspacesController` hands its side effects
  out as signals, so a test sets values and spies signals with no module mock. New code takes
  that shape.
- **A double for an older Plasma omits what that Plasma lacks**: the legacy double in
  `IndicatorTestCase` has no `currentDesktopByScreenName` and no `desktopPositionsChanged`, so the
  `typeof` guard and `ignoreUnknownSignals` are the path under test.
- **A `.pragma library`'s state outlives the test that set it.** `coordinator.js` is shared by
  every test in the engine, so `tst_coordinator.qml` runs one ordered scenario and `leave()`s
  every token it joined.
- **Reach the code through its inputs and outputs, not its internals.** If a value cannot be
  observed, either the design hides too much or the assertion belongs elsewhere. Do not add
  production API whose only caller is a test.

## Isolation and determinism

- **Tests run offscreen** (`QT_QPA_PLATFORM=offscreen`), where Kirigami resolves
  `Theme.smallFont` to the default font and nothing has a compositor: assert relations between
  sizes, never a pixel value a font or a theme picked.
- **Order is a subject or it isn't compared.** Sort first or compare as sets; the dots come back
  from the tree walk in tree order, so `dotsByIndex` sorts them by `globalIndex`.
- **No wall clock, locale or timezone.** Pass the instant or the string in rather than reading
  "now" in the code under test.
- **A test file reads only inside the repo**, through a path relative to itself. The Makefile
  sets `QML_XHR_ALLOW_FILE_READ` for the one test that reads `main.xml`.

## Coverage, and what it is worth

- **Coverage measures what executed, not what was verified.** A line covered by a test with
  no assertion on it is not tested. Nothing here measures QML coverage, so this is judgement.
- **The check that a pin works is breaking the code deliberately** and watching that test,
  and only that test, fail. A pin that cannot fail is worse than no pin, because it reads as
  coverage. A walk over a file is checked the same way, on a scratch copy of the tree.
- **Prefer an equality to a lower bound** wherever the thing under test can shrink; a floor
  keeps passing while its subject disappears.

## Anti-patterns

- **Flaky tests.** Fix or delete; never paper over with a longer `wait`.
- **Assertion roulette.** A long run of assertions where the failure does not say which fired.
- **Interdependent tests** that pass only in order, or that share a fixture they mutate.
- **Testing private implementation detail**, which turns every refactor into a test rewrite.
- **Over-mocking**, until the test asserts the code calls the functions it calls.
- **A `skip()` with no reason, or one that no longer applies**: it is a deleted test that still
  reads as coverage.
- **A stray `console.log`** left in a passing test.
- **Tests treated as second-class code.** Name, refactor and delete them like production
  code; a suite nobody maintains is one nobody trusts.

## Naming and documenting

- **Name a test as the property it holds**, camel-cased after `test_`:
  `test_scrollNeverEmitsActiveClicked`, `test_inactiveDotCentredAgainstThickPillVertical`. The name
  should say what broke without opening the file. A data row's `tag` names its partition in
  kebab case (`wrap-backward-over-start`).
- **A `//` above a non-obvious test gives the why**, usually the defect that motivated it. It is
  bound by `code-style.md` like any other comment: argue the reason, do not narrate the body.
- **A test file's header names what is under test and through which seam** (the real
  `logic.js`, `VdiMock`, a built indicator), not "This file contains tests for…".
- **Name a prohibition test as the prohibition**, so a failure reads as the rule it enforces.

## The toolbox

Know what exists before hand-rolling, and adopt deliberately: QtTest's `grabImage` for pixel
checks, `mouseDrag` and `keyClick`, `TestCase.expectFail`, a C++ `QQuickTest` harness, and a
real-session runner driving plasmashell.

- **Adopting one is a decision for the whole tree**, not for one file. A framework used in a
  single suite is drift, and the next reader cannot tell which convention is current.
- **Weigh it against what it replaces.** A dependency that saves fewer lines than its own
  matching DSL costs to learn is not a saving.
- **A C++ harness is out**: the widget is pure QML, and so is everything that tests it.
