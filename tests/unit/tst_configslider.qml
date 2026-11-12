/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ConfigSlider, built on its own: the aliases the dialog binds, the format, and the read-out width
 * reserved so the row doesn't reflow mid-drag.
 */
import QtQuick
import QtTest
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/config" as Config
import "../../package/contents/ui/logic.js" as Logic

TestCase {
    id: testCase
    name: "ConfigSlider"
    when: windowShown
    visible: true
    width: 400
    height: 80

    Component {
        id: sliderComponent
        Config.ConfigSlider {}
    }

    // To measure the expected width apart from the component.
    TextMetrics { id: metricsFrom }
    TextMetrics { id: metricsTo }

    function makeSlider(props) {
        return createTemporaryObject(sliderComponent, testCase, props || {});
    }

    // Found by what each part carries, not by declaration order.
    function partsOf(cs) {
        var parts = { slider: null, valueLabel: null };
        for (var i = 0; i < cs.children.length; i++) {
            var c = cs.children[i];
            if (c.snapMode !== undefined && c.from !== undefined && c.stepSize !== undefined)
                parts.slider = c;
            else if (c.text !== undefined && c.horizontalAlignment !== undefined)
                parts.valueLabel = c;
        }
        return parts;
    }

    function test_defaultSnapModeIsSnapAlways() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1 });
        const slider = partsOf(cs).slider;
        verify(slider, "found the inner slider");
        compare(slider.snapMode, QQC2.Slider.SnapAlways, "snapMode defaults to SnapAlways");
    }

    // The dialog binds each cfg_<key> through these aliases.
    function test_aliasesRoundTrip() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 10, snapMode: QQC2.Slider.NoSnap });
        const slider = partsOf(cs).slider;
        verify(slider, "found the inner slider");
        compare(slider.from, 0, "from alias reaches the slider");
        compare(slider.to, 100, "to alias reaches the slider");
        compare(slider.stepSize, 10, "stepSize alias reaches the slider");
        compare(slider.snapMode, QQC2.Slider.NoSnap, "snapMode alias overrides the default");

        cs.value = 30;   // on the grid, so no snap could move it
        compare(slider.value, 30, "value alias writes through to the slider");
        compare(cs.value, 30, "value alias reads back from the slider");
    }

    function test_defaultFormatRendersValueAsString() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1 });
        const valueLabel = partsOf(cs).valueLabel;
        verify(valueLabel, "found the value label");
        cs.value = 42;
        compare(valueLabel.text, "42", "default format renders String(value)");
    }

    function test_formatDrivesReadout() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 5, format: (v) => v + "%" });
        const valueLabel = partsOf(cs).valueLabel;
        verify(valueLabel, "found the value label");
        cs.value = 20;
        compare(valueLabel.text, "20%", "read-out applies the format closure");
        cs.value = 80;
        compare(valueLabel.text, "80%", "read-out re-applies the format when value changes");
    }

    // At its implicit size the label's width is the reserved one; the Layout hints can't be read from here.
    function test_reservedWidthMatchesWidestExtreme() {
        // "Default" at from is wider than "64 px" at to, so the max has to pick from.
        const fmt = (v) => v === 0 ? "Default" : v + " px";
        const cs = makeSlider({ from: 0, to: 64, stepSize: 1, format: fmt });
        const valueLabel = partsOf(cs).valueLabel;
        verify(valueLabel, "found the value label");

        metricsFrom.font = valueLabel.font;
        metricsTo.font = valueLabel.font;
        metricsFrom.text = fmt(cs.from);
        metricsTo.text = fmt(cs.to);
        const expected = Math.max(metricsFrom.advanceWidth, metricsTo.advanceWidth) + Kirigami.Units.smallSpacing;

        tryVerify(() => Math.abs(valueLabel.width - expected) <= 1.0, 1000,
            "read-out width is reserved for the widest of format(from)/format(to) + smallSpacing");
    }

    function test_reservedWidthStableAcrossValue() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1, format: (v) => Math.round(v) + "%" });
        const valueLabel = partsOf(cs).valueLabel;
        verify(valueLabel, "found the value label");

        cs.value = 0;
        var atMin = -1;
        tryVerify(() => { atMin = valueLabel.width; return atMin > 0; }, 1000, "read-out laid out at value=from");
        cs.value = 100;
        tryVerify(() => Math.abs(valueLabel.width - atMin) <= 0.5, 1000,
            "reserved read-out width is unchanged as the value sweeps from..to (no mid-drag jitter)");
    }

    function test_trackWidthIsFixedGridMetric() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1 });
        const slider = partsOf(cs).slider;
        verify(slider, "found the inner slider");
        compare(cs.trackWidth, Kirigami.Units.gridUnit * Logic.CONFIG_FIELD_WIDTH_UNITS,
                "trackWidth is the SHARED field-column metric (same one ConfigHint's wrap width uses)");
        tryVerify(() => Math.abs(slider.width - cs.trackWidth) <= 0.5, 1000,
            "slider renders at the fixed track width (not fill-width)");
    }

    function test_labelPropertyRoundTrips() {
        const cs = makeSlider({ label: "Dot size:" });
        compare(cs.label, "Dot size:", "label property holds the supplied string");
    }
}
