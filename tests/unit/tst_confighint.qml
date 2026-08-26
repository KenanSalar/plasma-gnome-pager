/*
 * Plasma Gnome Pager — tst_confighint.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for ConfigHint — the reusable dimmed explanatory line under a settings row. Unlike the
 * config PAGES (e2e-only — they need i18n/ColorButton), it is pure QtQuick/QQC2/Kirigami, so it loads
 * headless. Guards the styling contract the six call sites used to repeat by hand: it wraps, it is
 * dimmed and small, and it pins its width to the SHARED field-column metric so a long hint can never
 * widen the field column out from under the other rows.
 *
 * The one thing headless CANNOT distinguish is the small font: the offscreen theme resolves
 * Kirigami.Theme.smallFont to the same font a plain Label already gets, so the reference comparison below
 * only bites where a theme separates them. The visual check stays in-shell with the rest of the pages.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen.
 */
import QtQuick
import QtTest
import QtQuick.Controls as QQC2
import QtQuick.Layouts          // without it, `hint.Layout.*` reads back undefined from test JS
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/config" as Config
import "../../package/contents/ui/logic.js" as Logic

TestCase {
    id: testCase
    name: "ConfigHint"
    when: windowShown
    visible: true
    width: 400
    height: 200

    // What a plain Label styled with the theme's small font resolves to in THIS environment — the stable
    // reference, since Kirigami.Theme read off the TestCase's own attachee reports different values.
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

    // The caller supplies only the text; everything else is the component's job.
    function test_textPassesThrough() {
        const hint = makeHint({ text: "Clicking any other desktop switches to it." });
        compare(hint.text, "Clicking any other desktop switches to it.", "the hint renders the caller's text");
    }

    // Its reason to exist: a long hint must wrap inside the field column, not run off the page.
    function test_wrapsAndPinsToTheSharedFieldWidth() {
        const hint = makeHint({ text: "A hint long enough that it would run well past the field column if it were not wrapped." });
        compare(hint.wrapMode, Text.WordWrap, "wraps rather than widening the row");
        compare(hint.Layout.preferredWidth, Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS,
                "wrap width is the SHARED field-column metric (same one ConfigSlider's track uses)");
        compare(hint.Layout.fillWidth, true, "and absorbs a wider column rather than leaving a gap");
    }

    // Dimmed + small: a hint must read as secondary to the control it explains.
    function test_rendersAsSecondaryText() {
        const hint = makeHint({ text: "secondary" });
        fuzzyCompare(hint.opacity, 0.7, 0.001, "dimmed relative to the control above it");
        compare(hint.font.pointSize, smallFontReference.font.pointSize, "and styled like the theme's small font");
        compare(hint.font.family, smallFontReference.font.family, "same family");
        compare(hint.font.bold, false, "never bold — a hint is secondary to the control it explains");
    }
}
