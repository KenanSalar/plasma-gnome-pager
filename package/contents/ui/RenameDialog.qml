/*
 * Plasma Gnome Pager — RenameDialog.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Rename prompt — a panel-native PlasmaCore.Dialog (top-level Window), declared directly (visible:false
 * keeps it cheap). NOT Kirigami.PromptDialog, whose base parents to applicationWindow().overlay —
 * undefined in a plasmoid, so it would clip to the thin panel (robustness.md). View only: the parent
 * sets visualParent/location and owns the DBus write via the accepted() signal (the e2e boundary).
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
    hideOnWindowDeactivate: true            // click-away cancels

    // Prefill with the current name, select-all and focus for immediate typing.
    function openFor(uuid, currentName) {
        renameDialog.targetUuid = uuid;
        renameField.text = currentName;
        renameDialog.visible = true;
        renameField.selectAll();
        renameField.forceActiveFocus();
    }

    // Sanitize then emit. An empty/whitespace name (sanitize → "") keeps the prompt open rather than
    // silently doing nothing; the parent re-sanitizes, so the write stays guarded.
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
