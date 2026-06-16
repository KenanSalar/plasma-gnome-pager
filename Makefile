# GNOME Workspace Switcher — developer helpers
# SPDX-License-Identifier: GPL-3.0-or-later

PLASMOID_ID := com.github.kenansalar.plasma-gnome-pager
PKG_DIR     := package
PLASMOID_DIR := $(HOME)/.local/share/plasma/plasmoids/$(PLASMOID_ID)

.PHONY: help install update uninstall dev dev-undev test restart

help:
	@echo "Targets:"
	@echo "  make dev        Symlink package/ into ~/.local/share/plasma/plasmoids (live editing)"
	@echo "  make dev-undev  Remove the dev symlink"
	@echo "  make test       Run the widget standalone (plasmawindowed); shows QML errors"
	@echo "  make restart    Reload plasmashell to pick up changes in the panel"
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
