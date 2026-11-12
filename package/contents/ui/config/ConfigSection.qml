/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A heading over a group of form rows, or a plain gap without a title. It stays a bare Item: isSection
 * is documented as unreliable on other controls, and a Kirigami.Separator would rule a line under every
 * title.
 */
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    property string title: ""

    Kirigami.FormData.label: root.title
    Kirigami.FormData.isSection: true
}
