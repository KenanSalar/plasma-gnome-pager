/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ConfigHint, built on its own. Offscreen, Kirigami.Theme.smallFont resolves to the font a plain Label
 * gets anyway, so the font check only bites where a theme sets the two apart.
 */
import QtQuick
import QtTest
import QtQuick.Controls as QQC2
import QtQuick.Layouts          // without it, `hint.Layout.*` reads back undefined from test JS
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/config" as Config
import "../../package/contents/ui/logic.mjs" as Logic

TestCase {
    id: testCase
    name: "ConfigHint"
    when: windowShown
    visible: true
    width: 400
    height: 200

    // The reference, since Kirigami.Theme read off the TestCase itself reports different values.
    QQC2.Label {
        id: smallFontReference
        font: Kirigami.Theme.smallFont
        visible: false
    }

    Component {
        id: hintComponent
        Config.ConfigHint {}
    }

    function makeHint(props) {
        return createTemporaryObject(hintComponent, testCase, props || {});
    }

    function test_textPassesThrough() {
        const hint = makeHint({ text: "Clicking any other desktop switches to it." });
        compare(hint.text, "Clicking any other desktop switches to it.", "the hint renders the caller's text");
    }

    function test_wrapsAndPinsToTheSharedFieldWidth() {
        const hint = makeHint({ text: "A hint long enough that it would run well past the field column if it were not wrapped." });
        compare(hint.wrapMode, Text.WordWrap, "wraps rather than widening the row");
        compare(hint.Layout.preferredWidth, Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS,
                "wrap width is the SHARED field-column metric (same one ConfigSlider's track uses)");
        compare(hint.Layout.fillWidth, true, "and absorbs a wider column rather than leaving a gap");
    }

    function test_rendersAsSecondaryText() {
        const hint = makeHint({ text: "secondary" });
        fuzzyCompare(hint.opacity, 0.7, 0.001, "dimmed relative to the control above it");
        compare(hint.font.pointSize, smallFontReference.font.pointSize, "and styled like the theme's small font");
        compare(hint.font.family, smallFontReference.font.family, "same family");
        compare(hint.font.bold, false, "never bold — a hint is secondary to the control it explains");
    }
}
