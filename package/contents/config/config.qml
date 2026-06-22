/*
 * Plasma Gnome Pager — config.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The settings dialog's category list. ConfigCategory.source resolves relative to contents/ui/, so the
 * pages live in contents/ui/config/ while this file + main.xml live in contents/config/ (plasmoid.md).
 */
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Behavior")
        icon: "preferences-system-windows-actions"
        source: "config/ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-color"
        source: "config/ConfigAppearance.qml"
    }
}
