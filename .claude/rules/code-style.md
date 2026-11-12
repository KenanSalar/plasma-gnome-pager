---
paths:
  - "**/*.qml"
  - "**/*.js"
  - "**/*.mjs"
  - package/contents/config/main.xml
  - Makefile
  - .github/workflows/*.yml
---

# Code style and comments

## Writing Code Like a Senior Engineer

Write every change as an experienced human engineer would — code a senior colleague
would approve without rewriting, indistinguishable from thoughtful hand-crafted work.
Optimize for the next person who reads it (usually your future self), not for looking
clever or finishing fast.

- **Clarity over cleverness** - clear beats clever every time. Expand a clever one-liner
  into a few obvious lines when it reads better. Readable code scales; clever code ages badly.
- **Write for the reader** - code is read far more than written. Make intent obvious on the
  page; don't make the reader hold state in their head or decode `u`, `s`, `tmp`.
- **Name things precisely** - intention-revealing names (`calculateTotalPrice`,
  `isSubscriptionActive`), never `d`, `x`, `foo`, or a bare `data`. A good name removes the
  need for a comment.
- **Small, single-purpose functions** - one job, one level of abstraction. If you're
  narrating "step 1… step 2…", split it into functions a reader can hold in their head.
- **Guard clauses over nesting** - return early and flatten arrow-shaped `if/else` pyramids;
  handle the edge/error case first, then the happy path.
- **No magic values** - lift magic numbers/strings into named constants or config; the name
  documents the intent.
- **Minimize side effects** - prefer functions that take input and return output; centralize
  state mutation and I/O rather than scattering it.
- **Reduce, don't just add** - seniors delete. Remove dead code, collapse duplication, prefer
  the smaller solution, and leave each file a little cleaner than you found it (boy-scout rule).
- **Match the surrounding code** - mirror the existing naming, structure, error-handling, and
  style of the file. Consistency beats personal preference.
- **Handle errors and edges deliberately** - no silent catches or ignored failures; make
  failure modes explicit and intentional.
- **Be pragmatic, not dogmatic** - these are defaults, not laws; knowing when to bend one for
  clarity or simplicity is what separates senior from junior. (Complements **Principles** and
  **Antipatterns to Avoid** in the global `CLAUDE.md` — don't duplicate them.)

Avoid the tells of machine-generated code: comments that restate the code, defensive
boilerplate nobody asked for, needless abstraction, over-verbose names, and style that drifts
within a file. The result should look like a thoughtful human wrote it.

## Clean code

The list above is the half of clean code that gets quoted: names, small functions, guard
clauses, no magic values, no duplication. What follows is the rest of it, and it is the half
that bites in review. The frame underneath both is that code is finished when it passes its
tests, holds no duplication, says what it means, and has no more parts than that.

**Signatures**

- **Few parameters** - none, one or two read at a glance; three is worth a second look and
  four wants an options object, as `Logic.reduceWindowSnapshot` takes its feature switches in
  `opts`. A list long enough to count is usually two functions, or one shape that hasn't been
  named yet; `Logic.dotOpacity`'s seven positional arguments are that debt.
- **No flag parameters** - a `bool` argument splits the body before the reader reaches it, and
  `f(path, true)` says nothing at the call site. Ship the two functions the branches already
  are; where it genuinely is one operation, name the choice with a frozen table such as
  `Logic.OCCUPANCY`.
- **Meaning belongs in the type or the name, not the primitive** - a QML property is typed
  `int`, `real`, `bool`, `color` or `string`, and `var` is kept for arrays and objects. JavaScript
  has no types, so a unit goes in the name (`busyFallbackMs`, `wheelNotchDelta`), and a stored
  index maps through its frozen table (`Logic.PILL_CLICK_ACTION.None`), never a bare `0`.
- **Parse at the boundary, once** - a value from outside the widget becomes plain data in one
  place: `WindowAggregator.rebuild` turns `TasksModel` rows into `{ title, desktops, screen, … }`
  with the UUID wrappers stringified and the `QRect` flattened, and `main.qml` resolves each
  setting with `??` once. Past that point code trusts the shape.
- **Take the value, not its holder** - a component takes the plain values it reads, never
  `Plasmoid.configuration` or the representation they came from: `WindowAggregator` takes
  `screenRect`, not the `WorkspaceIndicator` that measured it.
- **Command or query, never both** - a function either changes state or answers a question.
  One that does both leaves every call site working out whether calling it twice is safe.
- **Don't reach through** - `a.b().c().d()` couples the caller to the shape of everything in
  the middle, and `a?.b?.c?.d` is the same coupling with `?.` between the links. Ask the
  neighbour for the answer instead of walking its internals.
- **A function that reads no component state goes in `logic.js`**, where `tst_logic.qml` can
  call it without building a component.

**Reading order**

- **Newspaper order** - a component opens with its inputs, then what it derives from them, its
  signals and functions, and its child items last. A `.js` module puts what the QML calls above
  the helpers those call; related functions sit together.
- **Declare close to first use** - a binding introduced far above the line that reads it is
  state the reader has to carry until then.
- **Name the sub-expression** - lift a dense condition or a nested call into a `const` or a
  `readonly property` whose name is the explanation. That is the comment you never have to keep
  true.
- **Say it positively** - `if (!notReady)` costs a mental flip at every read. Name the positive
  condition and negate at the one site that needs it.

**Vocabulary and shape**

- **One word per concept** - *desktop* is a KWin virtual desktop; *workspace* survives only in
  the component names and GNOME's "dynamic workspaces". The current desktop's element is the
  *pill* (`capsule` is just the id of the Rectangle that draws it). Reads come from `vdi`, writes
  are a `*Spec` handed to `dispatch`. Rename a stray synonym; never add one.
- **A distinction that isn't in the name isn't a distinction** - `data`, `info`, `manager`,
  `helper` and a trailing `2` name nothing. If two things need telling apart, the names do it,
  as `desktopOccupancy` and `screenOccupancy` do.
- **One home per boundary condition** - the cap, the clamp, the off-by-one. A named place that
  owns it beats the literal repeated at each call: `Logic.canRemoveDesktop`,
  `Logic.CONFIG_FIELD_WIDTH_UNITS`, `ringThickness`'s factor.
- **A dispatch repeated is a table missing** - the same `switch` spelled in two files wants one
  function or one frozen table. `main.qml`'s `toDBusArg` is the one switch on a spec argument's
  type letter, and `Logic.pillClickSpec` the one on the click action.

Test practice, including what all of this means for a test, is `.claude/rules/testing.md`.

## Comments

Comments are a liability, not an asset — each one is prose you must keep true. Write few, make
each earn its place, and re-read every comment before moving on.

- **Explain *why*, not *what*** - the code already shows what it does; a comment justifies a
  non-obvious choice, trade-off, or gotcha. If you're narrating the code, delete it.
- **`/** */` for whoever calls it, `//` for whoever edits it** - in the JavaScript, the contract
  goes in JSDoc on the function or constant, and a note on how the body works is a `//` beside
  the line it explains. QML has no doc form here (see the table).
- **Prefer self-documenting code** - clear names and small functions beat comments. If a comment
  has to explain "step 1… step 2…", the function is too big — split it instead.
- **No redundant comments** - never restate a name, type, or the obvious:
  `// Inputs (bound by WorkspaceIndicator).`, `property string desktopName: "" // tooltip
  mainText`, `// Reset cfg_<name> to its injected schema default.` above `resetField`.
- **Be terse** - one line where one line works; no decorative banners, ASCII art, or boilerplate.
- **No capitals for emphasis** - `NOT`, `ONE`, `NEVER`, `PER-SCREEN` shout without adding
  meaning. The sentence carries the stress, or the name does.
- **Sound like a senior engineer, not a generator** - write comments in plain, natural prose,
  the way a human colleague jots a note: terse, direct, peer-to-peer. Avoid the machine tells —
  restating the signature, "This function…", robotic step-by-step narration, hedging, and
  decorative filler. Assume the reader knows the language.
- **Double-check every comment** - confirm it is accurate and *still* true. When you touch code,
  update or delete the comments around it; a stale or wrong comment is worse than none.
- **Comment the genuinely non-obvious** - a Plasma, KWin or Qt behaviour the code works around
  (link the issue: `#35`), an empty `catch`, a magic constant, a non-trivial regex, and ordering
  assumptions such as a `Qt.callLater` deferral, a synchronous rebuild, or config `onChanged`
  firing before `Component.onCompleted`.
- **No commented-out code** - delete it; version control remembers.
- **Match the file** - follow the surrounding code's existing comment *style*. Not its density:
  a dense neighbour is not a budget, and the rules above outrank it.
- **Document the exported surface** - each `logic.js` and `coordinator.js` function or constant
  the QML calls gets a one-sentence JSDoc that says what its name can't. A QML input property
  gets a `//` only for what its name and type leave out: a unit, a sentinel such as `0 = auto`,
  or which side sets it. One its name already explains gets none, rather than a rephrasing.
- **No changelog** - no "used to", "no longer", "previously", "now", "exactly as before" or
  "byte-for-byte unchanged", no bug story, and no refactor story ("extracted from", "split
  into", "replaced an earlier"). Nothing about what shipped before; git holds the history.
- **No second copy** - an argument lives at its anchor, the comment on what it constrains, and a
  setting's meaning in its `main.xml` entry. `Logic.DEFAULTS`, `main.qml` and the component
  property it feeds name the key without explaining it again.
- **A file header is the SPDX lines and the module's contract with its one non-obvious why** -
  not its history, not a tour of the functions below it, not "This file…", and not a title line
  restating the filename.
- **One or two sentences carry a rationale** - a paragraph means a name, a type or a split should
  be saying it.
- **Don't overstate** - no "never", "always" or "forever" without the mechanism that makes it so;
  no benchmark figures, which go stale with the next change; a tunable's doc says what it does,
  not the value or rank it has today.
- **Some comments are kept whole** - the SPDX lines, and a comment a rule or test points at,
  condensed with the pointer kept true. An `i18nc` context is catalog input, not a comment.

**The budget is about 0.25 comment lines per line of code**, production code only, the QML and
the JavaScript each measured as its own corpus:

```bash
# cloc reports the QML and JavaScript rows separately
cloc package/contents/ui
```

It holds across the corpus, not per file: a module of tuned constants can sit above it while a
plain one sits well below. It shows drift and is never an allowance; a comment the rules above
don't justify goes whatever the count says. `main.xml` is outside it, its per-entry comment
being the setting's one documented meaning.

**Auditing a change.** After `make lint` and `make lint-js` pass, and before the work is reported
done (neither linter reads a comment):

```bash
# every comment line the change adds; `main...` in place of `HEAD` for a whole branch
git diff -U0 HEAD -- '*.qml' '*.js' '*.mjs' '*.xml' Makefile '*.yml' |
  rg '^\+\s*(//|/\*|\*|<!--|#)'
# each file the change created, against the budget
cloc --by-file <new files>
```

- Each listed line passes the rules above or goes. A reworded or moved comment counts as new, so
  a rename that pushes a comment onto a second line gets rewritten back to one.
- The corpus command above confirms the tree-wide figure hasn't drifted.

**Doc comments in this tree:**

| Language | Doc syntax | Notes |
|----------|-----------|-------|
| JavaScript (`.js`, `.mjs`) | `/** */` (JSDoc) | Read in an editor's hover; nothing generates docs and ESLint runs no JSDoc plugin. One-sentence summary first; `@param name - text`, with the hyphen and no `{type}`, only for a parameter its name leaves unexplained; `@returns` only when the summary doesn't say it. A module opens with the same `/* */` SPDX header as a QML file |
| QML | `//` | Nothing runs qdoc here, so the global `/*! */` QDoc convention doesn't apply: a `//` above a property, signal or function says what its name and type can't. Each file opens with a `/* */` header holding the SPDX lines and the component's contract |
| XML (`main.xml`) | `<!-- -->` | One per `<entry>`: what the setting does and what its sentinel or index means |
| Makefile, YAML | `#` | Why a target or step is shaped the way it is; `make help` already says what each target does |
