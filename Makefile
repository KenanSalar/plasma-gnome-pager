# Plasma Gnome Pager — developer helpers
# SPDX-License-Identifier: GPL-3.0-or-later

PLASMOID_ID := com.github.kenansalar.plasma-gnome-pager
PKG_DIR     := package
PLASMOID_DIR := $(HOME)/.local/share/plasma/plasmoids/$(PLASMOID_ID)
TESTS_DIR   := $(CURDIR)/tests
# Headless QML test runner: offscreen QPA lets Kirigami initialise without a display; -input
# scans the given dir for every tst_*.qml. Shared by the per-tier check targets below.
QMLTEST     := QT_QPA_PLATFORM=offscreen qmltestrunner-qt6 -input

.PHONY: help install update uninstall dev dev-undev test restart check check-unit check-integration lint _no-dev-symlink

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

install: _no-dev-symlink
	kpackagetool6 --type Plasma/Applet --install $(PKG_DIR)

update: _no-dev-symlink
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
# (contents/config/config.qml), and the test QML (tests/{unit,integration}/*.qml). Expected
# non-defects: i18n/i18np flagged unqualified (a plasmoid global) and any DBus.* ctor flagged
# unresolved-type — see CLAUDE.md "Verifying a change".
lint:
	qmllint-qt6 $(PKG_DIR)/contents/ui/*.qml $(PKG_DIR)/contents/ui/config/*.qml $(PKG_DIR)/contents/config/config.qml \
		$(TESTS_DIR)/unit/*.qml $(TESTS_DIR)/integration/*.qml
