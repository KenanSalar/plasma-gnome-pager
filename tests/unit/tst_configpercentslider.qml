/*
 * Plasma Gnome Pager — tst_configpercentslider.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for ConfigPercentSlider — the ConfigSlider preset behind the four 0..1 opacity keys. It adds
 * no logic of its own, so this pins exactly what the four call sites stopped repeating: the range, the
 * 1% step, and the percentage read-out. Pure QtQuick/QQC2/Kirigami, so it loads headless like its base.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen.
 */
import QtQuick
import QtTest
import "../../package/contents/ui/config" as Config

TestCase {
    id: testCase
    name: "ConfigPercentSlider"
    when: windowShown
    visible: true
    width: 400
    height: 80

    Component {
        id: percentComponent
        Config.ConfigPercentSlider {}
    }

    function makePercentSlider(props) {
        return createTemporaryObject(percentComponent, testCase, props || {});
    }

    // The full opacity range at 1% granularity — the four opacity rows now share ONE definition of it.
    function test_rangeAndStepArePreset() {
        const cps = makePercentSlider({ label: "Inactive opacity:" });
        compare(cps.from, 0.0, "starts fully transparent");
        compare(cps.to, 1.0, "ends fully opaque");
        fuzzyCompare(cps.stepSize, 0.01, 0.0001, "1% increments (drag or arrow keys)");
    }

    // The read-out the preset exists for: a 0..1 fraction shown as a whole percentage.
    function test_formatsAsWholePercent() {
        const cps = makePercentSlider({ label: "Hover opacity:" });
        compare(cps.format(0), "0%", "the low end");
        compare(cps.format(0.45), "45%", "the inactive-opacity default");
        compare(cps.format(1), "100%", "the high end");
        compare(cps.format(0.125), "13%", "rounds to a whole percent rather than showing a fraction");
    }

    // The read-out is live — the inherited ConfigSlider machinery still drives it through the preset.
    function test_valueLabelTracksTheValue() {
        const cps = makePercentSlider({ label: "Occupied opacity:", value: 0.7 });
        var valueLabel = null;
        for (var i = 0; i < cps.children.length; i++) {
            var c = cps.children[i];
            if (c.text !== undefined && c.horizontalAlignment !== undefined)
                valueLabel = c;
        }
        verify(valueLabel, "found the inherited value read-out");
        compare(valueLabel.text, "70%", "which shows the current value as a percentage");
    }
}
