---
paths:
  - .github/**
  - Makefile
  - package/metadata.json
  - package.json
  - .oxlintrc.json
  - .oxfmtrc.json
  - .editorconfig
---

# CI and packaging

Each workflow and Makefile target argues its own steps; this file holds what reaches across them.

- **A QML module a tested component starts importing joins the container's `dnf install` in
  `pr-validation.yml`**, or the headless job can't load it. The tests run under
  `dbus-run-session` because `ToolTipArea`'s plugin wants a session bus.
- **The version lives only in `metadata.json`'s `KPlugin.Version`.** The Makefile reads it for the
  `.plasmoid` name and the `.pot` header, and `publish.yml` refuses a tag other than `v<Version>`.
  A published release is never rebuilt, so releasing again means a new version.
- **The plugin Id is spelled in `metadata.json`, the Makefile's `PLASMOID_ID`, `CLAUDE.md`, the
  README's install steps and CONTRIBUTING's translation steps**, and nothing pins them together.
- **Every target that installs or packs compiles the catalogs first**, as `package`, `install`,
  `update` and `dev` do: kpackagetool6 ships the tree as it is.
- **Only `package/` ships.** The `.plasmoid` is its `metadata.json` and `contents/`, without
  `.qmlc`, `.jsc`, `.mjsc` or `.directory`.
- **oxfmt takes its indentation from `.editorconfig`**, four spaces for the JS and JSON and two
  for the YAML; a `tabWidth` in `.oxfmtrc.json` would override both. Layout is oxfmt's, so
  `.oxlintrc.json` turns on no stylistic rule.
