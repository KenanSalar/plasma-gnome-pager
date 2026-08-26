/*
 * Plasma Gnome Pager — tst_configsection.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for ConfigSection — the heading that groups a run of settings rows. Like the other shared
 * controls (and unlike the config PAGES, which are e2e-only), it is pure QtQuick/Kirigami, so it loads
 * headless. What it pins is the FormLayout contract the ten call sites depend on and cannot see: the
 * carrier declares itself a section, and the caller's `title` reaches the attached label FormLayout
 * actually reads. Get either wrong and the heading silently renders as a plain gap.
 *
 * Layout is FormLayout's job, not this component's, so the rendered heading (centred, Heading level 3,
 * largeSpacing above) stays an in-shell check with the pages themselves.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen.
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami   // without it, `section.Kirigami.FormData.*` reads back undefined from test JS
import "../../package/contents/ui/config" as Config

TestCase {
    id: testCase
    name: "ConfigSection"
    when: windowShown
    visible: true
    width: 400
    height: 200

    Component {
        id: sectionComponent
        Config.ConfigSection {}
    }

    function makeSection(props) {
        return createTemporaryObject(sectionComponent, testCase, props || {});
    }

    // The whole point: FormLayout promotes a child to a section header only via this attached flag.
    function test_declaresItselfASection() {
        const section = makeSection({ title: "Layout" });
        compare(section.Kirigami.FormData.isSection, true, "FormLayout renders it as a heading, not a row");
    }

    // The caller sets `title`; FormLayout reads Kirigami.FormData.label. The alias between them is the
    // component's only real job — a typo there degrades every heading to a blank gap, silently.
    function test_titleReachesTheAttachedLabel() {
        const section = makeSection({ title: "Occupied desktops" });
        compare(section.Kirigami.FormData.label, "Occupied desktops", "the caller's title is what FormLayout draws");
    }

    // A title-less instance must stay usable as the plain gap between groups (what the page used before
    // any headings existed), so Kirigami's empty-label path keeps working.
    function test_untitledIsAPlainGap() {
        const section = makeSection({});
        compare(section.title, "", "no title by default");
        compare(section.Kirigami.FormData.label, "", "so FormLayout falls through to its bare-spacing path");
        compare(section.Kirigami.FormData.isSection, true, "still a section — it is the gap that is wanted");
    }
}
