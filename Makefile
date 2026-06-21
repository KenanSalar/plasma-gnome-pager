# Plasma Gnome Pager — developer helpers
# SPDX-FileCopyrightText: 2026 Kenan Salar
# SPDX-License-Identifier: GPL-3.0-or-later

PLASMOID_ID := com.github.kenansalar.plasma-gnome-pager
PKG_DIR     := package
# Single source of truth for the version: read KPlugin.Version straight from metadata.json so the
# tag the publish workflow cuts (v<Version>) and the .plasmoid filename can never drift apart. The
# literal "Version" matches only the KPlugin.Version line (NOT "X-Plasma-API-Minimum-Version"); no
# jq dependency needed. Override on the command line when required: `make package VERSION=1.2.3`.
VERSION     := $(shell sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(PKG_DIR)/metadata.json | head -n1)
# User plasmoids live under PLASMOIDS_DIR; PLASMOID_DIR is this widget's install path within it.
PLASMOIDS_DIR := $(HOME)/.local/share/plasma/plasmoids
PLASMOID_DIR := $(PLASMOIDS_DIR)/$(PLASMOID_ID)
# kpackagetool6 invocation shared by the install/update/uninstall targets.
KPACKAGE    := kpackagetool6 --type Plasma/Applet
TESTS_DIR   := $(CURDIR)/tests
# Headless QML test runner: offscreen QPA lets Kirigami initialise without a display; -input
# scans the given dir for every tst_*.qml. QT_LOGGING_RULES silences the benign QWARN
# "kf.plasma.quick: Couldn't create KWindowShadow" that org.kde.plasma.core's ToolTipArea emits
# under offscreen/headless (no compositor to host the shadow) — tests pass either way; this just
# keeps `make check` output (and the CI log) clean. QML_XHR_ALLOW_FILE_READ lets the defaults
# cross-check test (tst_logic.qml) read contents/config/main.xml via XMLHttpRequest, which Qt
# disables for local files by default; it affects only this test harness, never the widget.
# Shared by the per-tier check targets below.
QMLTEST     := QT_QPA_PLATFORM=offscreen QT_LOGGING_RULES="kf.plasma.quick.warning=false" QML_XHR_ALLOW_FILE_READ=1 qmltestrunner-qt6 -input

# --- Translations (i18n) -------------------------------------------------------------------------
# The plasmoid runtime auto-binds the QML i18n() calls to the catalog domain plasma_applet_<Id>, so
# catalogs install as compiled .mo under contents/locale/<lang>/LC_MESSAGES/. The .po are the
# committed source of truth; the .pot template AND the .mo are generated (gitignored) — the .pot is
# re-extracted from the QML each `messages` run — and the .mo are compiled by `i18n`, which
# install/update/dev depend on (kpackagetool6 ships the tree verbatim — it does no compilation).
# See CLAUDE.md "Internationalization (i18n)". logic.js is i18n-free by design, so only .qml is scanned.
DOMAIN      := plasma_applet_$(PLASMOID_ID)
PO_DIR      := po
POT         := $(PO_DIR)/$(DOMAIN).pot
PO_FILES    := $(wildcard $(PO_DIR)/*.po)
LOCALE_DIR  := $(PKG_DIR)/contents/locale
# ki18n keyword set so i18nc/i18np/i18ncp contexts + plural forms extract correctly.
XGETTEXT    := xgettext --from-code=UTF-8 -C --kde \
	-ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
	--package-name="Plasma Gnome Pager" --package-version="$(VERSION)" \
	--copyright-holder="Kenan Salar" \
	--msgid-bugs-address="https://github.com/KenanSalar/plasma-gnome-pager/issues" \
	--width=200

DIST_DIR      := dist
PLASMOID_FILE := $(DIST_DIR)/$(PLASMOID_ID)-$(VERSION).plasmoid

.PHONY: help install update uninstall package dev dev-undev test restart check check-unit check-integration lint messages i18n _no-dev-symlink

help:
	@echo "Targets:"
	@echo "  make dev        Symlink package/ into ~/.local/share/plasma/plasmoids (live editing)"
	@echo "  make dev-undev  Remove the dev symlink"
	@echo "  make test       Run the widget standalone (plasmawindowed); shows QML errors"
	@echo "  make restart    Reload plasmashell to pick up changes in the panel"
	@echo "  make check      Run all headless QML tests (unit + integration)"
	@echo "  make check-unit Run only the unit tests (tests/unit)"
	@echo "  make check-integration  Run only the integration tests (tests/integration)"
	@echo "  make lint       qmllint the widget UI (clean — i18n globals resolved via .contextProperties.ini)"
	@echo "  make messages   Extract translatable strings into po/ (.pot template) and merge .po files"
	@echo "  make i18n       Compile po/*.po into the package (contents/locale/.../*.mo)"
	@echo "  make install    Install the package with kpackagetool6"
	@echo "  make update     Upgrade the installed package"
	@echo "  make uninstall  Remove the installed package"
	@echo "  make package    Build a distributable .plasmoid into dist/"

# Guard: kpackagetool6 install/upgrade targets $(PLASMOID_DIR). If `make dev` has symlinked that
# path to ./package, kpackagetool6's remove-then-install step deletes THROUGH the symlink and wipes
# the source tree. Refuse to run while the dev symlink is present. (When dev-symlinked the source is
# already live — just `make restart`; if you really want a real install, `make dev-undev` first.)
_no-dev-symlink:
	@if [ -L "$(PLASMOID_DIR)" ]; then \
		echo "ERROR: dev symlink present at $(PLASMOID_DIR)."; \
		echo "       kpackagetool6 would delete your source $(PKG_DIR)/ through it."; \
		echo "       Run 'make dev-undev' first — or just 'make restart' (the symlink already makes the source live)."; \
		exit 1; \
	fi

install: _no-dev-symlink i18n
	$(KPACKAGE) --install $(PKG_DIR)

update: _no-dev-symlink i18n
	$(KPACKAGE) --upgrade $(PKG_DIR)

uninstall:
	$(KPACKAGE) --remove $(PLASMOID_ID)

# Build a distributable .plasmoid (a zip of the package tree with metadata.json at the ARCHIVE
# ROOT — what kpackagetool6 and the KDE Store expect). Depends on i18n so the compiled .mo
# catalogs are inside the archive (kpackagetool6 ships the tree verbatim — it does no compilation).
# -X drops extra file attributes for a reproducible-ish archive; the -x globs keep QML/JS bytecode
# caches and KDE folder-metadata out. Install/remove the artifact itself to smoke-test it:
#   kpackagetool6 --type Plasma/Applet --install $(PLASMOID_FILE)
package: i18n
	mkdir -p $(DIST_DIR)
	rm -f $(PLASMOID_FILE)
	cd $(PKG_DIR) && zip -r -X "$(CURDIR)/$(PLASMOID_FILE)" metadata.json contents \
		-x '*.qmlc' -x '*.jsc' -x '.directory'
	@echo "Built $(PLASMOID_FILE)"

# Live-development symlink: edit files in ./package and just `make restart`. Depends on i18n so the
# symlinked package carries compiled catalogs (otherwise the live widget shows only source strings).
dev: i18n
	mkdir -p $(PLASMOIDS_DIR)
	ln -sfn "$(CURDIR)/$(PKG_DIR)" "$(PLASMOID_DIR)"
	@echo "Symlinked $(PLASMOID_DIR) -> $(CURDIR)/$(PKG_DIR)"

dev-undev:
	@if [ -L "$(PLASMOID_DIR)" ]; then rm "$(PLASMOID_DIR)"; echo "Removed symlink $(PLASMOID_DIR)"; \
	else echo "No symlink at $(PLASMOID_DIR)"; fi

test:
	plasmawindowed $(PLASMOID_ID)

# Reload the panel to pick up changes. Prefer the systemd user service when the session runs
# plasmashell that way; otherwise quit it and relaunch DETACHED with `setsid -f` (not `kstart`,
# whose xdg-portal app-ID registration prints a benign but noisy QDBusError). Output goes to
# /dev/null — watch `journalctl --user -f -t plasmashell` for QML errors instead.
restart:
	@if systemctl --user --quiet is-active plasma-plasmashell.service; then \
		echo "Restarting plasmashell (systemd user service)…"; \
		systemctl --user restart plasma-plasmashell.service; \
	else \
		echo "Restarting plasmashell…"; \
		kquitapp6 plasmashell 2>/dev/null || true; \
		setsid -f plasmashell >/dev/null 2>&1; \
	fi

# Headless QML tests, split by tier (see $(QMLTEST) above). main.qml/PlasmoidItem is not tested
# here (needs plasmashell + KWin + DBus) — see tests/README.md for the taxonomy.
check: check-unit check-integration

check-unit:
	$(QMLTEST) $(TESTS_DIR)/unit

check-integration:
	$(QMLTEST) $(TESTS_DIR)/integration

# Lints the UI components, the settings pages (contents/ui/config/), the config model
# (contents/config/config.qml), and the test QML (tests/{unit,integration,shared}/*.qml — incl. the
# shared VdiMock). Clean: the i18n*/Plasmoid globals (KLocalizedContext context properties qmllint
# can't statically resolve) are declared in ./.contextProperties.ini, so they no longer warn while
# real unqualified accesses still do. (A DBus.* ctor may print an unresolved-type info on some
# qmllint versions — benign, runtime JS types the plugin provides.) See CLAUDE.md "Verifying a change".
lint:
	qmllint-qt6 $(PKG_DIR)/contents/ui/*.qml $(PKG_DIR)/contents/ui/config/*.qml $(PKG_DIR)/contents/config/config.qml \
		$(TESTS_DIR)/unit/*.qml $(TESTS_DIR)/integration/*.qml $(TESTS_DIR)/shared/*.qml

# Extract translatable strings from the QML into the .pot template, then merge them into every
# existing po/<lang>.po (so translators pick up new/changed strings without losing their work).
# Run after adding or changing any i18n() string. Commit only the updated .po (the .pot is ignored).
messages:
	$(XGETTEXT) -o $(POT) $$(find $(PKG_DIR)/contents -name '*.qml' | sort)
	@for po in $(PO_FILES); do \
		echo "  msgmerge $$po"; \
		msgmerge --update --backup=none --width=200 "$$po" $(POT) || exit 1; \
	done
	@echo "Extracted to $(POT) and merged $(words $(PO_FILES)) translation(s)."

# Compile every po/<lang>.po into the package as contents/locale/<lang>/LC_MESSAGES/<domain>.mo.
# The .mo are generated artifacts (gitignored); install/update/dev depend on this target.
i18n:
	@for po in $(PO_FILES); do \
		lang=$$(basename "$$po" .po); \
		dest="$(LOCALE_DIR)/$$lang/LC_MESSAGES"; \
		mkdir -p "$$dest"; \
		echo "  msgfmt $$po -> $$dest/$(DOMAIN).mo"; \
		msgfmt --check -o "$$dest/$(DOMAIN).mo" "$$po" || exit 1; \
	done
