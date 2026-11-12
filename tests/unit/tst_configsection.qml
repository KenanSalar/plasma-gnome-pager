/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ConfigSection, built on its own: the attached properties FormLayout reads, where a mistake leaves
 * every heading a plain gap without a warning. The rendered heading is FormLayout's, checked in the shell.
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

    function test_declaresItselfASection() {
        const section = makeSection({ title: "Layout" });
        compare(section.Kirigami.FormData.isSection, true, "FormLayout renders it as a heading, not a row");
    }

    function test_titleReachesTheAttachedLabel() {
        const section = makeSection({ title: "Occupied desktops" });
        compare(section.Kirigami.FormData.label, "Occupied desktops", "the caller's title is what FormLayout draws");
    }

    function test_untitledIsAPlainGap() {
        const section = makeSection({});
        compare(section.title, "", "no title by default");
        compare(section.Kirigami.FormData.label, "", "so FormLayout falls through to its bare-spacing path");
        compare(section.Kirigami.FormData.isSection, true, "still a section — it is the gap that is wanted");
    }
}
