# GNOME Workspace Switcher — developer helpers
# SPDX-License-Identifier: GPL-3.0-or-later

PLASMOID_ID := com.github.kenansalar.plasma-gnome-pager
PKG_DIR     := package
PLASMOID_DIR := $(HOME)/.local/share/plasma/plasmoids/$(PLASMOID_ID)

.PHONY: help install update uninstall dev dev-undev test restart check check-unit check-integration lint

help:
	@echo "Targets:"
	@echo "  make dev        Symlink package/ into ~/.local/share/plasma/plasmoids (live editing)"
	@echo "  make dev-undev  Remove the dev symlink"
	@echo "  make test       Run the widget standalone (plasmawindowed); shows QML errors"
	@echo "  make restart    Reload plasmashell to pick up changes in the panel"
	@echo "  make check      Run all headless QML tests (unit + integration)"
	@echo "  make check-unit Run only the unit tests (tests/unit)"
	@echo "  make check-integration  Run only the integration tests (tests/integration)"
	@echo "  make lint       qmllint the widget UI (two benign warnings expected; see CLAUDE.md)"
	@echo "  make install    Install the package with kpackagetool6"
	@echo "  make update     Upgrade the installed package"
	@echo "  make uninstall  Remove the installed package"

install:
	kpackagetool6 --type Plasma/Applet --install $(PKG_DIR)

update:
	kpackagetool6 --type Plasma/Applet --upgrade $(PKG_DIR)

uninstall:
	kpackagetool6 --type Plasma/Applet --remove $(PLASMOID_ID)

# Live-development symlink: edit files in ./package and just `make restart`.
dev:
	mkdir -p $(HOME)/.local/share/plasma/plasmoids
	ln -sfn "$(CURDIR)/$(PKG_DIR)" "$(PLASMOID_DIR)"
	@echo "Symlinked $(PLASMOID_DIR) -> $(CURDIR)/$(PKG_DIR)"

dev-undev:
	@if [ -L "$(PLASMOID_DIR)" ]; then rm "$(PLASMOID_DIR)"; echo "Removed symlink $(PLASMOID_DIR)"; \
	else echo "No symlink at $(PLASMOID_DIR)"; fi

test:
	plasmawindowed $(PLASMOID_ID)

restart:
	kquitapp6 plasmashell && (kstart plasmashell &)

# Headless QML tests. offscreen QPA lets Kirigami initialise without a display;
# -input scans the given dir for every tst_*.qml. The suite is split by tier
# (tests/unit, tests/integration); main.qml/PlasmoidItem is not tested here
# (needs plasmashell + KWin + DBus) — see tests/README.md for the taxonomy.
check: check-unit check-integration

check-unit:
	QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input $(CURDIR)/tests/unit

check-integration:
	QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input $(CURDIR)/tests/integration

# Lints the UI components, the settings pages (contents/ui/config/) and the config model
# (contents/config/config.qml). Expected non-defects: i18n/i18np flagged unqualified (a plasmoid
# global) and any DBus.* ctor flagged unresolved-type — see CLAUDE.md "Verifying a change".
lint:
	qmllint-qt6 $(PKG_DIR)/contents/ui/*.qml $(PKG_DIR)/contents/ui/config/*.qml $(PKG_DIR)/contents/config/config.qml
