/*
 * Plasma Gnome Pager — ConfigSection.qml (reusable config-page control)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A titled heading between groups of form rows. Kirigami renders the label as a centred Heading spanning
 * both columns with generous space above it; leave the title empty for a plain gap. The carrier must stay
 * a bare Item — isSection is documented as unreliable on arbitrary controls, and a Kirigami.Separator
 * would draw a rule under every title.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string title: ""   // empty = an unlabelled gap between two groups

    Kirigami.FormData.label: root.title
    Kirigami.FormData.isSection: true
}
