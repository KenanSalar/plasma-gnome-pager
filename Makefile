# SPDX-FileCopyrightText: 2026 Kenan Salar
# SPDX-License-Identifier: GPL-3.0-or-later

PLASMOID_ID := com.github.kenansalar.plasma-gnome-pager
PKG_DIR     := package
# metadata.json is the version's only home, so the publish workflow's tag and the .plasmoid's name
# agree. "Version" alone doesn't match X-Plasma-API-Minimum-Version.
VERSION     := $(shell sed -n 's/.*"Version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $(PKG_DIR)/metadata.json | head -n1)
PLASMOIDS_DIR := $(HOME)/.local/share/plasma/plasmoids
PLASMOID_DIR := $(PLASMOIDS_DIR)/$(PLASMOID_ID)
KPACKAGE    := kpackagetool6 --type Plasma/Applet
TESTS_DIR   := $(CURDIR)/tests
# Offscreen lets Kirigami start without a display. The logging rule hides ToolTipArea's harmless
# KWindowShadow warning, there being no compositor, and the file-read switch lets tst_logic.qml read
# main.xml, which Qt blocks by default.
QMLTEST     := QT_QPA_PLATFORM=offscreen QT_LOGGING_RULES="kf.plasma.quick.warning=false" QML_XHR_ALLOW_FILE_READ=1 qmltestrunner-qt6 -input

# Plasma binds the QML's i18n() calls to the plasma_applet_<Id> catalogs under contents/locale/.
# The .po files are the source; the .pot and the .mo are generated and ignored. Only .qml is
# scanned, since logic.mjs has no i18n.
DOMAIN      := plasma_applet_$(PLASMOID_ID)
PO_DIR      := po
POT         := $(PO_DIR)/$(DOMAIN).pot
PO_FILES    := $(wildcard $(PO_DIR)/*.po)
LOCALE_DIR  := $(PKG_DIR)/contents/locale
# ki18n's keywords, so contexts and plural forms extract.
XGETTEXT    := xgettext --from-code=UTF-8 -C --kde \
	-ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3 \
	--package-name="Plasma Gnome Pager" --package-version="$(VERSION)" \
	--copyright-holder="Kenan Salar" \
	--msgid-bugs-address="https://github.com/KenanSalar/plasma-gnome-pager/issues" \
	--width=200

DIST_DIR      := dist
PLASMOID_FILE := $(DIST_DIR)/$(PLASMOID_ID)-$(VERSION).plasmoid

.PHONY: help install update uninstall package clean dev dev-undev test restart check check-unit check-integration lint lint-js format format-check verify messages i18n _no-dev-symlink _node-modules

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
	@echo "  make lint-js    oxlint the JS modules (logic.mjs, coordinator.mjs, tests/shared/*.mjs); run 'npm ci' first"
	@echo "  make format     oxfmt the JS, JSON and YAML in place"
	@echo "  make format-check  Fail on any file oxfmt would change"
	@echo "  make verify     Run all static + headless gates: lint + lint-js + format-check + check"
	@echo "  make messages   Extract translatable strings into po/ (.pot template) and merge .po files"
	@echo "  make i18n       Compile po/*.po into the package (contents/locale/.../*.mo)"
	@echo "  make install    Install the package with kpackagetool6"
	@echo "  make update     Upgrade the installed package"
	@echo "  make uninstall  Remove the installed package"
	@echo "  make package    Build a distributable .plasmoid into dist/"
	@echo "  make clean      Remove build artifacts (dist/)"

# kpackagetool6 removes the old install before writing the new one, and through `make dev`'s symlink
# that deletes the source tree.
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

# Zipped from inside package/, with metadata.json at the archive's root as kpackagetool6 and the KDE
# Store expect. kpackagetool6 compiles nothing, so the .mo catalogs go in first; -X drops extra file
# attributes, and the -x globs leave bytecode caches and folder metadata out.
package: i18n
	mkdir -p $(DIST_DIR)
	rm -f $(PLASMOID_FILE)
	cd $(PKG_DIR) && zip -r -X "$(CURDIR)/$(PLASMOID_FILE)" metadata.json contents \
		-x '*.qmlc' -x '*.jsc' -x '*.mjsc' -x '.directory'
	@echo "Built $(PLASMOID_FILE)"

clean:
	rm -rf $(DIST_DIR)
	@echo "Removed $(DIST_DIR)/"

# Without the compiled catalogs the live widget would show only the English strings.
dev: i18n
	mkdir -p $(PLASMOIDS_DIR)
	ln -sfn "$(CURDIR)/$(PKG_DIR)" "$(PLASMOID_DIR)"
	@echo "Symlinked $(PLASMOID_DIR) -> $(CURDIR)/$(PKG_DIR)"

dev-undev:
	@if [ -L "$(PLASMOID_DIR)" ]; then rm "$(PLASMOID_DIR)"; echo "Removed symlink $(PLASMOID_DIR)"; \
	else echo "No symlink at $(PLASMOID_DIR)"; fi

test:
	plasmawindowed $(PLASMOID_ID)

# Through the systemd user service where the session uses one. Otherwise setsid, not kstart, whose
# xdg-portal registration prints a harmless QDBusError; QML errors are in the journal either way.
restart:
	@if systemctl --user --quiet is-active plasma-plasmashell.service; then \
		echo "Restarting plasmashell (systemd user service)…"; \
		systemctl --user restart plasma-plasmashell.service; \
	else \
		echo "Restarting plasmashell…"; \
		kquitapp6 plasmashell 2>/dev/null || true; \
		setsid -f plasmashell >/dev/null 2>&1; \
	fi

check: check-unit check-integration

check-unit:
	$(QMLTEST) $(TESTS_DIR)/unit

check-integration:
	$(QMLTEST) $(TESTS_DIR)/integration

# .contextProperties.ini declares the i18n* and Plasmoid globals. Some qmllint versions print an
# unresolved-type note for the DBus.* constructors, which the plugin only provides at runtime.
lint:
	qmllint-qt6 $(PKG_DIR)/contents/ui/*.qml $(PKG_DIR)/contents/ui/config/*.qml $(PKG_DIR)/contents/config/config.qml \
		$(TESTS_DIR)/unit/*.qml $(TESTS_DIR)/integration/*.qml $(TESTS_DIR)/shared/*.qml

_node-modules:
	@[ -d node_modules ] || { echo "==> node_modules/ missing: run 'npm ci' first"; exit 1; }

lint-js: _node-modules
	npm run --silent lint

format: _node-modules
	npm run --silent format

format-check: _node-modules
	npm run --silent format:check

verify: lint lint-js format-check check

messages:
	$(XGETTEXT) -o $(POT) $$(find $(PKG_DIR)/contents -name '*.qml' | sort)
	@for po in $(PO_FILES); do \
		echo "  msgmerge $$po"; \
		msgmerge --update --backup=none --width=200 "$$po" $(POT) || exit 1; \
	done
	@echo "Extracted to $(POT) and merged $(words $(PO_FILES)) translation(s)."

i18n:
	@for po in $(PO_FILES); do \
		lang=$$(basename "$$po" .po); \
		dest="$(LOCALE_DIR)/$$lang/LC_MESSAGES"; \
		mkdir -p "$$dest"; \
		echo "  msgfmt $$po -> $$dest/$(DOMAIN).mo"; \
		msgfmt --check -o "$$dest/$(DOMAIN).mo" "$$po" || exit 1; \
	done
