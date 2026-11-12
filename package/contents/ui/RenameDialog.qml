/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The rename prompt, a top-level PlasmaCore.Dialog. Kirigami.PromptDialog would parent itself to
 * applicationWindow().overlay, which a plasmoid lacks, and clip to the panel. The parent places it and
 * makes the write.
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import "logic.js" as Logic

PlasmaCore.Dialog {
    id: renameDialog

    property string targetUuid: ""
    signal accepted(string uuid, string name)

    visible: false
    hideOnWindowDeactivate: true            // clicking away cancels

    function openFor(uuid, currentName) {
        renameDialog.targetUuid = uuid;
        renameField.text = currentName;
        renameDialog.visible = true;
        renameField.selectAll();
        renameField.forceActiveFocus();
    }

    // A blank name keeps the prompt open.
    function commit() {
        const clean = Logic.sanitizeDesktopName(renameField.text);
        if (clean === "") {
            return;
        }
        renameDialog.accepted(renameDialog.targetUuid, clean);
        renameDialog.visible = false;
    }

    mainItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            text: i18n("Rename desktop:")
        }
        PlasmaComponents3.TextField {
            id: renameField
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 12
            onAccepted: renameDialog.commit()
            Keys.onEscapePressed: renameDialog.visible = false
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Button {
                text: i18n("Cancel")
                icon.name: "dialog-cancel"
                onClicked: renameDialog.visible = false
            }
            PlasmaComponents3.Button {
                text: i18n("Rename")
                icon.name: "edit-rename"
                enabled: renameField.text.trim().length > 0
                onClicked: renameDialog.commit()
            }
        }
    }
}
