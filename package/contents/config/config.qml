/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The settings dialog's pages. ConfigCategory.source resolves against contents/ui/, which is why the
 * pages live in contents/ui/config/ and not beside this file.
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
