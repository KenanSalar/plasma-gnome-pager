/*
 * GNOME Workspace Switcher — tst_workspacedot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for WorkspaceDot in isolation — a single first-party component driven only by
 * plain properties (dotSize / pillWidthFactor / inactiveOpacity / hoverOpacity / active /
 * animate), with no data source to mock. It guards the dot's own contract: inactive it is a
 * dim themed circle; active it MORPHS into a wider highlighted capsule (the pill — there is
 * no overlay); hover brightens inactive dots only; and its whole footprint is the click target.
 * Tests use the default `animate: false`, so morphs are instant and assertions can be synchronous.
 *
 * Composition of dots into the strip (Repeater, reflow, reactivity) is the INTEGRATION tier —
 * see tests/integration/tst_workspaceindicator.qml. See tests/README.md for the taxonomy.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen so
 * Kirigami initialises without a display.
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager
import "../shared/treewalk.js" as TreeWalk

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

    // The circle and the tooltip are nested inside the per-dot ToolTipArea, so a flat
    // children scan would miss them — TreeWalk.collect walks the whole subtree (shared with
    // the integration tier; see tests/shared/treewalk.js).

    // The dim circle is a Rectangle — uniquely identified by having both `radius` and
    // `color` (the MouseArea/ToolTipArea have neither). Avoids relying on child order/depth.
    function circleOf(dot) {
        const found = TreeWalk.collect(dot, c => c.radius !== undefined && c.color !== undefined);
        return found.length ? found[0] : null;
    }

    // The per-dot tooltip — identified by exposing `mainText` (the ToolTipArea).
    function tooltipOf(dot) {
        const found = TreeWalk.collect(dot, c => c.mainText !== undefined);
        return found.length ? found[0] : null;
    }

    // An inactive dot advertises a dot-sized footprint and renders exactly one element.
    function test_rendersOneCapsule() {
        const dot = makeDot({});   // inactive by default
        verify(dot, "dot created");
        compare(dot.implicitWidth, dot.dotSize, "inactive footprint is a dot wide");
        compare(dot.implicitHeight, dot.dotSize, "implicitHeight advertises the dot size");

        const rects = TreeWalk.collect(dot, c => c.radius !== undefined && c.color !== undefined);
        compare(rects.length, 1, "renders exactly one dot/capsule rectangle");
    }

    // The inactive circle follows the colour scheme (theme text colour, dimmed) — asserted
    // against theme/units tokens, never literals, so it holds across themes and HiDPI.
    function test_inactiveCircleFollowsTheme() {
        const dot = makeDot({ inactiveOpacity: 0.45 });
        const circle = circleOf(dot);
        verify(circle, "found the circle");
        compare(circle.color, Kirigami.Theme.textColor, "dim circle uses the theme text colour");
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "circle is dimmed to inactiveOpacity");
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "inactive is a dot-sized circle");
    }

    // Reflow model: `active` DOES morph the element — into a wider, full-strength, highlight-
    // coloured capsule. (Inverts the old M2 invariant. animate defaults false → instant.)
    function test_activeChangesAppearance() {
        const dot = makeDot({ active: false, inactiveOpacity: 0.45 });
        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.textColor, "inactive uses the theme text colour");
        fuzzyCompare(circle.opacity, 0.45, 0.001, "inactive is dimmed");
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "inactive is a dot");

        dot.active = true;

        compare(circle.color, Kirigami.Theme.highlightColor, "active → theme highlight colour");
        fuzzyCompare(circle.opacity, 1.0, 0.001, "active → full strength");
        fuzzyCompare(circle.width, dot.pillWidth, 0.5, "active → capsule width");
    }

    // Clicking the dot emits activated() (the indicator turns this into a switch request).
    function test_clickEmitsActivated() {
        const dot = makeDot({});
        activatedSpy.target = dot;
        activatedSpy.clear();

        mouseClick(dot, dot.width / 2, dot.height / 2);
        compare(activatedSpy.count, 1, "clicking the dot emits activated");
    }

    // The whole element is the click target — including the wide active capsule. A click near
    // the capsule's left edge still activates (the hit area is the full capsule, not a dot).
    function test_hitAreaCoversCapsule() {
        const dot = makeDot({ active: true });   // active → width is pillWidth (wider than a dot)
        activatedSpy.target = dot;
        activatedSpy.clear();

        mouseClick(dot, 2, dot.height / 2);   // near the left edge of the capsule
        compare(activatedSpy.count, 1, "the whole capsule is the click target");
    }

    // --- Milestone 4: vertical form factor -----------------------------------------
    // On a vertical panel the dot morphs along the OTHER axis: the capsule grows TALL
    // (height → pillWidth) while the width stays a dot. `vertical` defaults false, so every
    // test above exercises the horizontal axis; these cover the vertical one.

    // Active + vertical: the capsule grows along height; width stays a dot. The footprint
    // (implicitWidth/Height) tracks both axes so the column reflows.
    function test_verticalActiveGrowsTall() {
        const dot = makeDot({ vertical: true, active: true });
        const circle = circleOf(dot);
        fuzzyCompare(circle.height, dot.pillWidth, 0.5, "active vertical capsule grows tall (height → pillWidth)");
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "width stays a dot thick");
        fuzzyCompare(dot.implicitHeight, dot.pillWidth, 0.5, "implicitHeight tracks the capsule length");
        fuzzyCompare(dot.implicitWidth, dot.dotSize, 0.5, "implicitWidth stays a dot thick");
    }

    // Inactive + vertical: a plain dot — square footprint, both axes dotSize.
    function test_verticalInactiveIsDot() {
        const dot = makeDot({ vertical: true, active: false });
        const circle = circleOf(dot);
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "inactive width is a dot");
        fuzzyCompare(circle.height, dot.dotSize, 0.5, "inactive height is a dot");
        fuzzyCompare(dot.implicitWidth, dot.dotSize, 0.5, "implicitWidth is a dot");
        fuzzyCompare(dot.implicitHeight, dot.dotSize, 0.5, "implicitHeight is a dot");
    }

    // Regression guard for the radius fix: radius is pinned to the constant cross-axis
    // half-thickness (dotSize/2), NOT height/2 — otherwise a tall vertical capsule would round
    // into a lozenge (radius pillWidth/2) instead of a stadium with circular ends.
    function test_verticalRadiusStaysStadium() {
        const dot = makeDot({ vertical: true, active: true });
        const circle = circleOf(dot);
        fuzzyCompare(circle.radius, dot.dotSize / 2, 0.5, "vertical capsule keeps stadium ends (radius == dotSize/2)");
    }

    // The same radius invariant holds horizontally — the radius refactor (height/2 → dotSize/2)
    // must not change horizontal rounding.
    function test_horizontalRadiusUnchanged() {
        const dot = makeDot({ active: true });   // default horizontal
        const circle = circleOf(dot);
        fuzzyCompare(circle.radius, dot.dotSize / 2, 0.5, "horizontal capsule radius is dotSize/2");
    }

    // --- Milestone 3: hover --------------------------------------------------------

    // A fresh dot is not hovered and exposes a numeric hoverOpacity (the brighten target).
    function test_hoverDefaults() {
        const dot = makeDot({});
        compare(dot.hovered, false, "a fresh dot is not hovered");
        compare(typeof dot.hoverOpacity, "number", "hoverOpacity is a number");
    }

    // Hovering an INACTIVE dot brightens the circle to hoverOpacity; leaving restores the
    // dim inactiveOpacity. (The brighten/suppress branches are covered exhaustively and
    // deterministically by tst_logic::test_dotOpacity; this proves the dot wires the
    // pointer through to that binding.)
    function test_hoverBrightensInactiveDot() {
        const dot = makeDot({ active: false, inactiveOpacity: 0.45, hoverOpacity: 0.8 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "starts dim");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        tryCompare(circle, "opacity", dot.hoverOpacity, 2000, "brightens to hoverOpacity on hover");

        mouseMove(dot, -5, -5);   // move the pointer off the element
        tryCompare(circle, "opacity", dot.inactiveOpacity, 2000, "returns to inactiveOpacity when not hovered");
    }

    // The ACTIVE capsule is already full strength (1.0); hovering it changes nothing — hover
    // affects inactive dots only.
    function test_activeCapsuleFullStrengthHoverNoEffect() {
        const dot = makeDot({ active: true, inactiveOpacity: 0.45, hoverOpacity: 0.8 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, 1.0, 0.001, "active capsule is full strength at rest");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        // Give any (incorrect) change time to run, then assert it never happened.
        wait(Math.max(50, Kirigami.Units.longDuration * 2));
        fuzzyCompare(circle.opacity, 1.0, 0.001, "hover does not change the active capsule");
    }

    // --- Milestone 3: tooltip ------------------------------------------------------

    // The dot carries a tooltip whose text is the desktop name it was given.
    function test_tooltipShowsDesktopName() {
        const dot = makeDot({ desktopName: "Web" });
        const tip = tooltipOf(dot);
        verify(tip, "the dot has a tooltip area");
        compare(tip.mainText, "Web", "tooltip text is the desktop name");
    }

    // showTooltips gates the tooltip; an empty name never shows one (transient names lag ids).
    function test_tooltipGatedByShowTooltips() {
        const dot = makeDot({ desktopName: "Web", showTooltips: true });
        const tip = tooltipOf(dot);
        verify(tip.active, "tooltip is active when enabled and named");

        dot.showTooltips = false;
        verify(!tip.active, "tooltip is inactive when showTooltips is off");

        dot.showTooltips = true;
        dot.desktopName = "";
        verify(!tip.active, "tooltip is inactive for an empty name");
    }

    // --- Milestone 5: configurable colours -----------------------------------------
    // With followThemeColors false the dot uses the configured activeColor/inactiveColor instead
    // of the colour scheme. (The 2×2 branch is covered exhaustively by tst_logic::test_dotColor;
    // this proves the dot wires its colour props through to the binding.)
    function test_customColorsWhenNotFollowingTheme() {
        const dot = makeDot({ followThemeColors: false, activeColor: "#ff0000", inactiveColor: "#00ff00", active: false });
        const circle = circleOf(dot);
        compare(circle.color, dot.inactiveColor, "inactive uses the custom inactive colour");

        dot.active = true;
        compare(circle.color, dot.activeColor, "active uses the custom active colour");
    }

    // followThemeColors true (the default) keeps the colour-scheme binding — a regression guard
    // that the M5 colour props did not break theme-following. Asserted against theme tokens.
    function test_followThemeColorsUsesTheme() {
        const dot = makeDot({ followThemeColors: true, active: false });
        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.textColor, "inactive follows the theme text colour");

        dot.active = true;
        compare(circle.color, Kirigami.Theme.highlightColor, "active follows the theme highlight colour");
    }

    // --- Milestone 5: configurable animation duration ------------------------------
    // animationDuration 0 = auto (the themed longDuration); a positive value overrides it. The
    // reduce-animations branch (longDuration 0 → instant) cannot be toggled headlessly and is
    // covered by tst_logic::test_effectiveDuration; here we prove the dot resolves the sentinel.
    function test_effectiveDurationSentinelAndOverride() {
        const auto = makeDot({ animationDuration: 0 });
        compare(auto.effectiveDuration, Kirigami.Units.longDuration, "0 resolves to the themed default");

        const overridden = makeDot({ animationDuration: 250 });
        compare(overridden.effectiveDuration, 250, "a positive value overrides the themed default");
    }

    // --- morph gating: the FIRST placement is instant, later switches animate -------
    // morphEnabled (= animate && effectiveDuration > 0) is the single gate on the four morph
    // Behaviors. Every other dot test runs with animate:false (the instant first-placement
    // path, also the gate-off path), so these are the only cases that assert the gate value
    // and the only ones that actually fire a Behavior.

    // The gate combines the animate latch with the resolved duration: off until BOTH hold.
    function test_morphGateReflectsAnimateAndDuration() {
        const notLatched = makeDot({ animate: false, animationDuration: 200 });
        compare(notLatched.morphEnabled, false, "gate is off before the animate latch (instant first placement)");

        const latched = makeDot({ animate: true, animationDuration: 200 });
        compare(latched.morphEnabled, true, "gate is on once latched with a positive duration");
    }

    // With the latch on, toggling `active` MORPHS the width over effectiveDuration rather than
    // jumping — i.e. a Behavior fires. Contrast test_activeChangesAppearance (animate:false),
    // where the same toggle changes width instantly. Guarded against a reduce-animations headless
    // theme (longDuration == 0 → effectiveDuration 0 → morphEnabled false → no Behavior to observe).
    function test_morphAnimatesWhenLatched() {
        const dot = makeDot({ active: false, animate: true, animationDuration: 200 });
        if (!dot.morphEnabled)
            skip("animations disabled in this environment (reduce-animations / longDuration == 0)");

        const circle = circleOf(dot);
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "starts as a dot");

        dot.active = true;   // morph dot → capsule
        // Mid-morph on this tick: the Behavior eases from dotSize, so width has NOT jumped to pillWidth.
        verify(circle.width < dot.pillWidth - 0.5, "width animates toward the capsule (no instant jump)");
        tryCompare(circle, "width", dot.pillWidth, 2000, "the morph settles at the capsule width");
    }
}
