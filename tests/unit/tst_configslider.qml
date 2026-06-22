/*
 * Plasma Gnome Pager — tst_configslider.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for ConfigSlider — the reusable config-page control (Slider + a right-hand value read-out).
 * Unlike the config PAGES (e2e-only — they need i18n/ColorButton), ConfigSlider is pure QtQuick/QQC2/
 * Kirigami, so it loads headless. Guards its contract: the alias bind-points, SnapAlways default, the
 * `format` closure, and — its reason to exist — the RESERVED read-out width (widest of format(from)/(to))
 * so the track never jitters mid-drag. Run with `make check-unit` (offscreen).
 */
import QtQuick
import QtTest
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/config" as Config

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

    // TextMetrics to independently reproduce the reserved-width formula (same font + format text).
    TextMetrics { id: metricsFrom }
    TextMetrics { id: metricsTo }

    // The single point that instantiates the component under test (auto-cleaned).
    function makeSlider(props) {
        return createTemporaryObject(sliderComponent, testCase, props || {});
    }

    // ConfigSlider is a RowLayout whose two visual children are the inner Slider and the value Label.
    // Duck-type them off `children` rather than relying on declaration order.
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

    // SnapAlways is the component default (overridable via the alias).
    function test_defaultSnapModeIsSnapAlways() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1 });
        const slider = partsOf(cs).slider;
        verify(slider, "found the inner slider");
        compare(slider.snapMode, QQC2.Slider.SnapAlways, "snapMode defaults to SnapAlways");
    }

    // The dialog two-way binds via `property alias cfg_<key>: <id>.value` (+ from/to/stepSize/snapMode),
    // so each alias must reach the inner Slider. On-grid values so SnapAlways is a no-op.
    function test_aliasesRoundTrip() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 10, snapMode: QQC2.Slider.NoSnap });
        const slider = partsOf(cs).slider;
        verify(slider, "found the inner slider");
        compare(slider.from, 0, "from alias reaches the slider");
        compare(slider.to, 100, "to alias reaches the slider");
        compare(slider.stepSize, 10, "stepSize alias reaches the slider");
        compare(slider.snapMode, QQC2.Slider.NoSnap, "snapMode alias overrides the default");

        cs.value = 30;   // on-grid
        compare(slider.value, 30, "value alias writes through to the slider");
        compare(cs.value, 30, "value alias reads back from the slider");
    }

    // The default format is identity-to-string; the read-out shows the (stringified) value.
    function test_defaultFormatRendersValueAsString() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1 });
        const valueLabel = partsOf(cs).valueLabel;
        verify(valueLabel, "found the value label");
        cs.value = 42;
        compare(valueLabel.text, "42", "default format renders String(value)");
    }

    // One `format` closure drives the live read-out; it updates as the value changes.
    function test_formatDrivesReadout() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 5, format: (v) => v + "%" });
        const valueLabel = partsOf(cs).valueLabel;
        verify(valueLabel, "found the value label");
        cs.value = 20;
        compare(valueLabel.text, "20%", "read-out applies the format closure");
        cs.value = 80;
        compare(valueLabel.text, "80%", "read-out re-applies the format when value changes");
    }

    // The reason to exist: the read-out width is RESERVED for the widest of format(from)/format(to) +
    // smallSpacing, so the row never reflows while dragging. At the implicit size its rendered width IS the
    // reserved width, so reproduce the formula independently and compare (the Layout.* hints aren't readable).
    function test_reservedWidthMatchesWidestExtreme() {
        // "Default" (at from=0) is wider than "64 px" (at to), exercising the max() over the extremes.
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

    // The reserved width depends only on from/to, so it stays constant as the value sweeps the range (the
    // anti-jitter invariant) even though the displayed strings differ in width ("0%" vs "100%").
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

    // The fixed track length (NOT fillWidth) so sliders match across both pages: it renders at trackWidth
    // (the shared gridUnit*18 metric).
    function test_trackWidthIsFixedGridMetric() {
        const cs = makeSlider({ from: 0, to: 100, stepSize: 1 });
        const slider = partsOf(cs).slider;
        verify(slider, "found the inner slider");
        compare(cs.trackWidth, Kirigami.Units.gridUnit * 18, "trackWidth is the shared gridUnit*18 metric");
        tryVerify(() => Math.abs(slider.width - cs.trackWidth) <= 0.5, 1000,
            "slider renders at the fixed track width (not fill-width)");
    }

    // The `label` property is the row's FormData label; it round-trips on the public surface.
    function test_labelPropertyRoundTrips() {
        const cs = makeSlider({ label: "Dot size:" });
        compare(cs.label, "Dot size:", "label property holds the supplied string");
    }
}
