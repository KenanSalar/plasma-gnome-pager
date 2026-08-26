<!--
Base branch should be `dev`, not `main`. GitHub defaults a fork's PR to `main`;
if that happened, click Edit next to the title and change the base — nothing is lost.
See CONTRIBUTING.md.
-->

## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] Targets `dev`
- [ ] `make verify` passes locally (qmllint + ESLint + headless tests)
- [ ] New behaviour has a test, or it's something that can't be tested headlessly
- [ ] New user-visible strings are `i18n()`-wrapped and `make messages` has been run
- [ ] Screenshot attached, if it changes how the widget looks
