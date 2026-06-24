/*
 * Plasma Gnome Pager — tst_workspacedot.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for WorkspaceDot in isolation — driven only by plain properties (no data source). Guards the
 * dot's contract: inactive = dim themed circle; active MORPHS into a wider highlighted capsule (no
 * overlay); hover brightens inactive only; the whole footprint is the click target. Tests default to
 * `animate: false` so morphs are instant. Composition into the strip is the INTEGRATION tier (see
 * tst_indicator_*.qml + tests/README.md). Run with `make check-unit` (offscreen).
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager
import "../../package/contents/ui/logic.js" as Logic
import "../shared/treewalk.js" as TreeWalk
import "../shared/elements.js" as Elements

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

    // The circle/tooltip are nested in the per-dot ToolTipArea; locators are shared with the integration
    // tier (tests/shared/elements.js). Thin local aliases keep the call sites readable.
    function circleOf(dot) {
        return Elements.circleOf(dot);
    }
    function tooltipOf(dot) {
        return Elements.tooltipOf(dot);
    }

    // An inactive dot advertises a dot-sized footprint and renders exactly one element.
    function test_rendersOneCapsule() {
        const dot = makeDot({});   // inactive by default
        verify(dot, "dot created");
        compare(dot.implicitWidth, dot.dotSize, "inactive footprint is a dot wide");
        compare(dot.implicitHeight, dot.dotSize, "implicitHeight advertises the dot size");

        // The optional inner-dot element exists in the tree but is hidden unless the InnerDot occupancy
        // style is active, so count only VISIBLE circles — exactly one (the capsule) in the default state.
        const rects = TreeWalk.collect(dot, Elements.isCircle).filter(r => r.visible);
        compare(rects.length, 1, "renders exactly one visible dot/capsule rectangle");
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

    // Reflow model: `active` morphs the element into a wider, full-strength, highlight capsule.
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

    // Vertical form factor: the dot morphs along the OTHER axis (capsule grows TALL, width stays a dot).

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

    // Regression: radius is min(width,height)/2 (the cross axis), so the ends stay stadium-round and a
    // tall capsule never rounds into a lozenge. With the default pill (== dotSize) that is dotSize/2.
    function test_verticalRadiusStaysStadium() {
        const dot = makeDot({ vertical: true, active: true });
        const circle = circleOf(dot);
        fuzzyCompare(circle.radius, dot.dotSize / 2, 0.5, "vertical capsule keeps stadium ends (radius == dotSize/2)");
    }

    // The same radius invariant holds horizontally — min(width, height) / 2 == dotSize/2 when the pill
    // is no thicker than a dot.
    function test_horizontalRadiusUnchanged() {
        const dot = makeDot({ active: true });   // default horizontal
        const circle = circleOf(dot);
        fuzzyCompare(circle.radius, dot.dotSize / 2, 0.5, "horizontal capsule radius is dotSize/2");
    }

    // Independent pill thickness: an active dot with pillSize > dotSize renders a capsule pillSize across,
    // pillWidth long, stadium ends at pillSize/2; an inactive dot stays a dotSize circle.
    function test_independentPillThickness() {
        const active = makeDot({ active: true, dotSize: 8, pillSize: 24, pillWidthFactor: 3 });
        const circle = circleOf(active);
        fuzzyCompare(active.pillWidth, 72, 0.5, "pillWidth = pillSize * pillWidthFactor");
        fuzzyCompare(circle.height, 24, 0.5, "horizontal active capsule is pill-thick across (height == pillSize)");
        fuzzyCompare(circle.width, 72, 0.5, "horizontal active capsule is pill-long (width == pillWidth)");
        fuzzyCompare(circle.radius, 12, 0.5, "stadium ends at half the pill thickness (pillSize/2)");

        const inactive = makeDot({ active: false, dotSize: 8, pillSize: 24, pillWidthFactor: 3 });
        const inactiveCircle = circleOf(inactive);
        fuzzyCompare(inactiveCircle.width, 8, 0.5, "inactive stays a dotSize circle (width)");
        fuzzyCompare(inactiveCircle.height, 8, 0.5, "inactive stays a dotSize circle (height)");
        fuzzyCompare(inactiveCircle.radius, 4, 0.5, "inactive radius is dotSize/2");
    }

    // hover

    // A fresh dot is not hovered and exposes a numeric hoverOpacity (the brighten target).
    function test_hoverDefaults() {
        const dot = makeDot({});
        compare(dot.hovered, false, "a fresh dot is not hovered");
        compare(typeof dot.hoverOpacity, "number", "hoverOpacity is a number");
    }

    // Hovering an INACTIVE dot brightens to hoverOpacity; leaving restores inactiveOpacity (the branch
    // logic is covered by tst_logic::test_dotOpacity; this proves the dot wires the pointer through).
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

    // occupied-dot indicator: an occupied (desktop-with-windows) inactive dot renders at occupiedOpacity,
    // between empty and hover. The dot wires `occupied`/`occupiedOpacity` through; the branch ORDER is
    // covered by tst_logic::test_dotOpacity.
    function test_occupiedDotUsesOccupiedOpacity() {
        const dot = makeDot({ active: false, occupied: true, inactiveOpacity: 0.45, hoverOpacity: 0.8, occupiedOpacity: 0.7 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.occupiedOpacity, 0.001, "an occupied inactive dot uses occupiedOpacity");

        dot.occupied = false;
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "an empty inactive dot falls back to inactiveOpacity");
    }

    // Precedence through the dot's wiring: active and hover both outrank occupied.
    function test_occupiedPrecedence() {
        const active = makeDot({ active: true, occupied: true, occupiedOpacity: 0.7 });
        fuzzyCompare(circleOf(active).opacity, 1.0, 0.001, "active beats occupied (full strength)");

        const dot = makeDot({ active: false, occupied: true, hoverOpacity: 0.8, occupiedOpacity: 0.7 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.occupiedOpacity, 0.001, "occupied at rest");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        tryCompare(circle, "opacity", dot.hoverOpacity, 2000, "hover beats occupied");
    }

    // occupancy style: Filled — an occupied dot's whole body takes the occupied colour AND the occupied opacity.
    function test_filledStyleColorsOccupied() {
        const dot = makeDot({ occupied: true, occupancyStyle: Logic.OCCUPANCY.Filled, active: false, inactiveOpacity: 0.45, occupiedOpacity: 0.7 });
        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.highlightColor, "Filled: occupied dot uses the occupied (theme accent) colour");
        fuzzyCompare(circle.opacity, dot.occupiedOpacity, 0.001, "Filled: occupied dot uses the occupied opacity");

        dot.occupied = false;
        compare(circle.color, Kirigami.Theme.textColor, "Filled: an empty dot stays the inactive (text) colour");
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "Filled: an empty dot is dim");
    }

    // occupancy style: Inner dot — an occupied dot shows a small occupied-colour dot in its centre (a 2nd visible
    // circle) at the occupied opacity, concentric with the dot; the outer body stays dim.
    function test_innerDotStyleShowsCentreDot() {
        const dot = makeDot({ occupied: true, occupancyStyle: Logic.OCCUPANCY.InnerDot, active: false, inactiveOpacity: 0.45, occupiedOpacity: 0.7 });
        verify(dot.showInnerDot, "occupied + InnerDot style → inner dot shown");
        const circle = circleOf(dot);   // the outer dot body
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "InnerDot: the outer body stays dim");

        const circles = TreeWalk.collect(dot, Elements.isCircle).filter(c => c.visible);
        compare(circles.length, 2, "two visible circles: the dim dot and the centre marker");
        const inner = circles.find(c => c !== circle);
        verify(inner, "found the inner dot");
        compare(inner.color, Kirigami.Theme.highlightColor, "the inner dot uses the occupied (theme accent) colour");
        fuzzyCompare(inner.opacity, dot.occupiedOpacity, 0.001, "the inner dot uses the occupied opacity");
        verify(inner.width < dot.dotSize, "the inner dot is smaller than the full dot");
        // Concentric with the dot (guards the off-centre regression): inner centre == outer centre.
        const ic = inner.mapToItem(dot, inner.width / 2, inner.height / 2);
        const cc = circle.mapToItem(dot, circle.width / 2, circle.height / 2);
        fuzzyCompare(ic.x, cc.x, 0.5, "inner dot is horizontally centred on the dot");
        fuzzyCompare(ic.y, cc.y, 0.5, "inner dot is vertically centred on the dot");

        const empty = makeDot({ occupied: false, occupancyStyle: Logic.OCCUPANCY.InnerDot });
        verify(!empty.showInnerDot, "an empty dot shows no inner dot");
        compare(TreeWalk.collect(empty, Elements.isCircle).filter(c => c.visible).length, 1, "only the dot renders when empty");
    }

    // occupancy style: Hollow ring — a hollow occupied-colour ring drawn ON TOP of the normal dim dot (the dot
    // background stays); empty dots show no overlay. The ring is a separate element at the occupied opacity.
    function test_ringStyleOverlaysOccupiedDots() {
        const dot = makeDot({ occupied: true, occupancyStyle: Logic.OCCUPANCY.Ring, active: false, inactiveOpacity: 0.45, occupiedOpacity: 0.7 });
        verify(dot.showRing, "occupied + Ring style → ring overlay shown");
        const circle = circleOf(dot);   // the dot body stays a normal dim dot (background preserved)
        verify(!Qt.colorEqual(circle.color, "transparent"), "Ring: the dot body keeps its fill (not hollowed)");
        compare(circle.color, Kirigami.Theme.textColor, "Ring: the dot body stays the inactive (text) colour");
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "Ring: the dot body stays dim");

        const circles = TreeWalk.collect(dot, Elements.isCircle).filter(c => c.visible);
        compare(circles.length, 2, "two visible circles: the dim dot and the ring overlay");
        const ring = circles.find(c => c !== circle);
        verify(ring, "found the ring overlay");
        verify(Qt.colorEqual(ring.color, "transparent"), "the ring overlay has a transparent fill (hollow)");
        verify(ring.border.width > 0, "the ring overlay has a visible border");
        compare(ring.border.color, Kirigami.Theme.highlightColor, "the ring uses the occupied (theme accent) colour");
        fuzzyCompare(ring.opacity, dot.occupiedOpacity, 0.001, "the ring uses the occupied opacity");

        const empty = makeDot({ occupied: false, occupancyStyle: Logic.OCCUPANCY.Ring });
        verify(!empty.showRing, "an empty dot shows no ring overlay");
        compare(TreeWalk.collect(empty, Elements.isCircle).filter(c => c.visible).length, 1, "only the dot renders when empty");
    }

    // Custom occupied colour: with followThemeColors off, the occupied MARKER uses the configured
    // occupiedColor (via resolvedOccupied) in EVERY style — the Filled body, the inner dot, the ring
    // border. (The theme-accent path is covered by the three style tests above; the colour branch itself
    // by tst_logic::test_dotColor — this proves the dot wires occupiedColor through.)
    function test_customOccupiedColorWhenNotFollowingTheme() {
        const occ = "#abcdef";

        // Filled: the whole dot body takes the custom occupied colour.
        const filled = makeDot({ followThemeColors: false, occupiedColor: occ, occupied: true,
                                 occupancyStyle: Logic.OCCUPANCY.Filled, active: false });
        compare(circleOf(filled).color, filled.occupiedColor, "Filled: occupied body uses the custom occupiedColor");

        // Inner dot: the centre marker takes the custom occupied colour.
        const innerStyle = makeDot({ followThemeColors: false, occupiedColor: occ, occupied: true,
                                     occupancyStyle: Logic.OCCUPANCY.InnerDot, active: false });
        const inner = TreeWalk.collect(innerStyle, Elements.isCircle).filter(c => c.visible)
                              .find(c => c !== circleOf(innerStyle));
        verify(inner, "found the inner dot");
        compare(inner.color, innerStyle.occupiedColor, "InnerDot: centre marker uses the custom occupiedColor");

        // Ring: the border takes the custom occupied colour (transparent fill is asserted in the style test).
        const ringStyle = makeDot({ followThemeColors: false, occupiedColor: occ, occupied: true,
                                    occupancyStyle: Logic.OCCUPANCY.Ring, active: false });
        const ring = TreeWalk.collect(ringStyle, Elements.isCircle).filter(c => c.visible)
                             .find(c => c !== circleOf(ringStyle));
        verify(ring, "found the ring overlay");
        compare(ring.border.color, ringStyle.occupiedColor, "Ring: border uses the custom occupiedColor");
    }

    // tooltip

    // The dot carries a tooltip whose text is the desktop name it was given.
    function test_tooltipShowsDesktopName() {
        const dot = makeDot({ desktopName: "Web" });
        const tip = tooltipOf(dot);
        verify(tip, "the dot has a tooltip area");
        compare(tip.mainText, "Web", "tooltip text is the desktop name");
    }

    // accessibility: a screen reader (Orca) announces each dot as a named button it can activate; the
    // accessible name is the desktop name and tracks it.
    function test_accessibleExposesButtonRole() {
        const dot = makeDot({ desktopName: "Web" });
        compare(dot.Accessible.role, Accessible.Button, "dot exposes a Button role to assistive tech");
        compare(dot.Accessible.name, "Web", "accessible name is the desktop name");

        dot.desktopName = "Mail";
        compare(dot.Accessible.name, "Mail", "accessible name tracks the desktop name");
    }

    // checkable/checked convey WHICH dot is the current desktop, so a screen reader can distinguish
    // the active one from the otherwise identically-named inactive buttons. `checked` tracks `active`.
    function test_accessibleCheckedTracksActive() {
        const dot = makeDot({ desktopName: "Web", active: false });
        verify(dot.Accessible.checkable, "dot is checkable so AT can report a current state");
        compare(dot.Accessible.checked, false, "an inactive dot is not checked");

        dot.active = true;
        compare(dot.Accessible.checked, true, "the active (current) dot reports checked");
    }

    // The accessibility press action routes through the SAME activated() signal as a click, so an
    // AT-driven press switches desktops exactly like a pointer click would.
    function test_accessiblePressEmitsActivated() {
        const dot = makeDot({ desktopName: "Web" });
        activatedSpy.target = dot;
        activatedSpy.clear();
        dot.Accessible.pressAction();
        compare(activatedSpy.count, 1, "the accessibility press action emits activated");
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

    // window-list tooltip: the dot renders tooltipText as rich-text subText

    // The window-list HTML is wired into the tooltip's subText.
    function test_tooltipShowsSubText() {
        const html = "2 Windows:<ul><li>Foo</li><li>Bar</li></ul>";
        const dot = makeDot({ desktopName: "Web", tooltipText: html });
        const tip = tooltipOf(dot);
        verify(tip, "the dot has a tooltip area");
        compare(tip.subText, html, "tooltip subText is the window-list HTML");
    }

    // The subText is rich text (a <ul> list), so the area must render RichText, not PlainText.
    function test_tooltipTextFormatIsRichText() {
        const dot = makeDot({ desktopName: "Web", tooltipText: "<ul><li>Foo</li></ul>" });
        const tip = tooltipOf(dot);
        compare(tip.textFormat, Text.RichText, "tooltip renders as rich text");
    }

    // Still gated on the NAME: a window list with no name (transient: names lag ids) shows no tooltip.
    function test_subTextDoesNotActivateWithoutName() {
        const dot = makeDot({ desktopName: "", tooltipText: "<ul><li>Foo</li></ul>", showTooltips: true });
        const tip = tooltipOf(dot);
        verify(!tip.active, "no name → no tooltip even when a window list is present");
    }

    // configurable colours: followThemeColors false uses activeColor/inactiveColor (the 2×2 branch is
    // covered by tst_logic::test_dotColor; this proves the dot wires its colour props through).
    function test_customColorsWhenNotFollowingTheme() {
        const dot = makeDot({ followThemeColors: false, activeColor: "#ff0000", inactiveColor: "#00ff00", active: false });
        const circle = circleOf(dot);
        compare(circle.color, dot.inactiveColor, "inactive uses the custom inactive colour");

        dot.active = true;
        compare(circle.color, dot.activeColor, "active uses the custom active colour");
    }

    // followThemeColors true (default) keeps the colour-scheme binding (regression guard).
    function test_followThemeColorsUsesTheme() {
        const dot = makeDot({ followThemeColors: true, active: false });
        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.textColor, "inactive follows the theme text colour");

        dot.active = true;
        compare(circle.color, Kirigami.Theme.highlightColor, "active follows the theme highlight colour");
    }

    // configurable animation duration: 0 = auto (themed longDuration), a positive value overrides. The
    // reduce-animations branch is covered by tst_logic::test_effectiveDuration; here we resolve the sentinel.
    function test_effectiveDurationSentinelAndOverride() {
        const auto = makeDot({ animationDuration: 0 });
        compare(auto.effectiveDuration, Kirigami.Units.longDuration, "0 resolves to the themed default");

        const overridden = makeDot({ animationDuration: 250 });
        compare(overridden.effectiveDuration, 250, "a positive value overrides the themed default");
    }

    // morph gating: the FIRST placement is instant, later switches animate. morphEnabled (= animate &&
    // effectiveDuration > 0) is the single gate on the four Behaviors; every other test runs animate:false.

    // The gate combines the animate latch with the resolved duration: off until BOTH hold.
    function test_morphGateReflectsAnimateAndDuration() {
        const notLatched = makeDot({ animate: false, animationDuration: 200 });
        compare(notLatched.morphEnabled, false, "gate is off before the animate latch (instant first placement)");

        const latched = makeDot({ animate: true, animationDuration: 200 });
        compare(latched.morphEnabled, true, "gate is on once latched with a positive duration");
    }

    // With the latch on, toggling `active` MORPHS the width over effectiveDuration (a Behavior fires),
    // vs test_activeChangesAppearance (animate:false, instant). Guarded against reduce-animations.
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

    // The COLOUR morph fires when latched too: `active` eases text → highlight rather than snapping
    // (companion to test_morphAnimatesWhenLatched; skip under reduce-animations).
    function test_colorMorphAnimatesWhenLatched() {
        const dot = makeDot({ active: false, animate: true, animationDuration: 200 });
        if (!dot.morphEnabled)
            skip("animations disabled in this environment (reduce-animations / longDuration == 0)");

        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.textColor, "starts at the theme text colour");

        dot.active = true;   // morph the colour toward the highlight
        verify(!Qt.colorEqual(circle.color, Kirigami.Theme.highlightColor), "colour animates (has not snapped to highlight)");
        tryVerify(() => Qt.colorEqual(circle.color, Kirigami.Theme.highlightColor), 2000, "the colour settles at the highlight");
    }

    // The OPACITY morph fires too: inactiveOpacity eases up to full strength when the dot becomes active.
    function test_opacityMorphAnimatesWhenLatched() {
        const dot = makeDot({ active: false, inactiveOpacity: 0.45, animate: true, animationDuration: 200 });
        if (!dot.morphEnabled)
            skip("animations disabled in this environment (reduce-animations / longDuration == 0)");

        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "starts dimmed");

        dot.active = true;   // morph opacity toward 1.0
        verify(circle.opacity < 1.0 - 0.001, "opacity animates upward (no instant jump to full strength)");
        tryCompare(circle, "opacity", 1.0, 2000, "the opacity settles at full strength");
    }

    // Vertical morph: with the latch on, the capsule grows TALL over effectiveDuration (the major-axis
    // Behavior is `height` when vertical). The existing morph test is horizontal (width-only).
    function test_verticalHeightMorphAnimatesWhenLatched() {
        const dot = makeDot({ vertical: true, active: false, animate: true, animationDuration: 200 });
        if (!dot.morphEnabled)
            skip("animations disabled in this environment (reduce-animations / longDuration == 0)");

        const circle = circleOf(dot);
        fuzzyCompare(circle.height, dot.dotSize, 0.5, "starts a dot tall");

        dot.active = true;   // morph dot → tall capsule
        verify(circle.height < dot.pillWidth - 0.5, "height animates toward the capsule (no instant jump)");
        tryCompare(circle, "height", dot.pillWidth, 2000, "the morph settles at the capsule height");
    }

    // First placement is instant EVEN with the latch on: a born-active element is a capsule on frame 0
    // (initial values never animate), so no grow-in despite a positive duration.
    function test_bornActiveWithLatchIsInstant() {
        const dot = makeDot({ active: true, animate: true, animationDuration: 200 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.width, dot.pillWidth, 0.5, "born-active is already a capsule (no grow-in from a dot)");
    }

    // The `hovered` alias (mouseArea.containsMouse) flips true under the pointer, false when it leaves.
    function test_hoveredAliasFlipsTrue() {
        const dot = makeDot({});
        compare(dot.hovered, false, "not hovered at rest");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        tryCompare(dot, "hovered", true, 2000, "hovered becomes true under the pointer");

        mouseMove(dot, -5, -5);   // pointer leaves the element
        tryCompare(dot, "hovered", false, 2000, "hovered returns to false when the pointer leaves");
    }
}
