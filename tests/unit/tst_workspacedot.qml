/*
 * GNOME Workspace Switcher — tst_workspacedot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for WorkspaceDot in isolation — a single first-party component driven only by
 * plain properties (dotSize / slotWidth / inactiveOpacity / active), with no data source to
 * mock. It guards the dot's own contract: it renders one dim themed circle, its `active`
 * flag does NOT change its appearance in M2 (the pill overlay owns the active look — see
 * WorkspaceIndicator.qml), and its whole slot is the click target.
 *
 * Composition of dots into the strip (Repeater, pill, reactivity) is the INTEGRATION tier —
 * see tests/integration/tst_workspaceindicator.qml. See tests/README.md for the taxonomy.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen so
 * Kirigami initialises without a display.
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager

TestCase {
    id: testCase
    name: "WorkspaceDot"
    when: windowShown
    visible: true   // so the dot reports effective `visible` and receives synthesized clicks
    width: 200
    height: 50

    Component {
        id: dotComponent
        Pager.WorkspaceDot {}
    }

    SignalSpy {
        id: activatedSpy
        signalName: "activated"
    }

    // The single point that instantiates the component under test (auto-cleaned).
    function makeDot(props) {
        return createTemporaryObject(dotComponent, testCase, props || {});
    }

    // The dim circle is a Rectangle child — uniquely identified by having both `radius`
    // and `color` (the sibling MouseArea has neither). Avoids relying on child order.
    function circleOf(dot) {
        const kids = dot.children;
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            if (c.radius !== undefined && c.color !== undefined)
                return c;
        }
        return null;
    }

    // The dot advertises its footprint and renders exactly one circle.
    function test_rendersOneCircle() {
        const dot = makeDot({});
        verify(dot, "dot created");
        compare(dot.implicitWidth, dot.slotWidth, "implicitWidth advertises the slot width");
        compare(dot.implicitHeight, dot.dotSize, "implicitHeight advertises the dot size");

        let circles = 0;
        const kids = dot.children;
        for (let i = 0; i < kids.length; i++)
            if (kids[i].radius !== undefined && kids[i].color !== undefined)
                circles++;
        compare(circles, 1, "renders exactly one circle");
    }

    // The circle follows the colour scheme (theme text colour, dimmed) — asserted against
    // theme/units tokens, never literals, so it holds across themes and HiDPI.
    function test_circleFollowsTheme() {
        const dot = makeDot({ inactiveOpacity: 0.45 });
        const circle = circleOf(dot);
        verify(circle, "found the circle");
        compare(circle.color, Kirigami.Theme.textColor, "dim circle uses the theme text colour");
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "circle is dimmed to inactiveOpacity");
    }

    // M2 invariant: `active` is set by the indicator but must NOT change the dot's look —
    // the sliding pill owns the active appearance. Guards against a regression that
    // re-introduces per-dot active recolouring (which would double-up with the pill).
    function test_activeDoesNotChangeAppearance() {
        const dot = makeDot({ active: false });
        const circle = circleOf(dot);
        const inactiveColor = circle.color;
        const inactiveOpacity = circle.opacity;

        dot.active = true;

        compare(circle.color, inactiveColor, "active does not change the circle colour in M2");
        fuzzyCompare(circle.opacity, inactiveOpacity, 0.001, "active does not change the circle opacity in M2");
    }

    // Clicking the dot emits activated() (the indicator turns this into a switch request).
    function test_clickEmitsActivated() {
        const dot = makeDot({});
        activatedSpy.target = dot;
        activatedSpy.clear();

        mouseClick(dot, dot.width / 2, dot.height / 2);
        compare(activatedSpy.count, 1, "clicking the dot emits activated");
    }

    // The whole slot is the click target (GNOME-style enlarged hit area), not just the
    // centred circle — a click near the slot edge, off the circle, still activates.
    function test_hitAreaCoversWholeSlot() {
        const dot = makeDot({ slotWidth: 40 });   // slot wider than the circle so the edge is clearly off it
        activatedSpy.target = dot;
        activatedSpy.clear();

        mouseClick(dot, 2, dot.height / 2);   // near the left edge, outside the centred circle
        compare(activatedSpy.count, 1, "the whole slot is the click target, not just the circle");
    }
}
