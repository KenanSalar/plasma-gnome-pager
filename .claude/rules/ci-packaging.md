---
paths:
  - .github/**
  - Makefile
  - package/metadata.json
  - package.json
  - eslint.config.mjs
  - tools/**
---

# CI and packaging

Each workflow and Makefile target argues its own steps; this file holds what reaches across them.

- **`pr-validation.yml` runs two jobs.** "Lint & headless tests" runs `make lint` and
  `make check` in a `fedora:latest` container, the tests under `dbus-run-session` because
  `ToolTipArea`'s plugin wants a session bus. "ESLint (strict, JS tier)" runs `make lint-js` on
  Node 22. A QML module a tested component starts importing needs its Fedora package added to the
  container's `dnf install`.
- **The version lives only in `metadata.json`'s `KPlugin.Version`.** The Makefile reads it for the
  `.plasmoid` name and the `.pot` header, and `publish.yml` refuses a tag that doesn't equal
  `v<Version>`.
- **`publish.yml` builds with `make package` on Ubuntu, needing only gettext**, then creates a
  draft release, refreshes a draft's `.plasmoid` without touching its notes, or skips a published
  one. The draft is edited and published by hand, and the KDE Store upload is manual too.
- **The `.plasmoid` is `metadata.json` and `contents/` zipped from inside `package/`**, with
  `.qmlc`, `.jsc` and `.directory` left out. kpackagetool6 compiles nothing, so `package`,
  `install`, `update` and `dev` all run `i18n` first to put the `.mo` catalogs inside.
- **`node_modules`, `package.json` and the ESLint config are dev tooling** and never ship.
- **ESLint reads the `.pragma library` modules through `tools/eslint-qml-js-parser.mjs`**, a custom
  parser rather than a flat-config processor: a processor's virtual filename matches none of the
  `files` globs, so its rules would never run. Stylistic rules stay off for the house style of
  `var` and braceless `if`s.
