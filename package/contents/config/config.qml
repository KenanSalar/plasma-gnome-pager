/*
 * Plasma Gnome Pager — config.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar <kenansalar@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The settings dialog's category list. Each ConfigCategory.source is resolved relative to
 * contents/ui/ — so the pages live in contents/ui/config/ while this file and the KConfigXT
 * schema (main.xml) live in contents/config/ (mixing this up yields an empty dialog; see
 * plasmoid.md). Plasma adds the "Configure…" entry and the page chrome automatically.
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
