/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WorkspaceDot on its own, driven only through its properties, with `animate: false` unless a test
 * is about the morph. Expected colours and sizes come from theme and unit tokens, never literals.
 */
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui" as Pager
import "../../package/contents/ui/logic.mjs" as Logic
import "../shared/treewalk.mjs" as TreeWalk
import "../shared/elements.mjs" as Elements

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

    function makeDot(props) {
        return createTemporaryObject(dotComponent, testCase, props || {});
    }

    function circleOf(dot) {
        return Elements.circleOf(dot);
    }
    function tooltipOf(dot) {
        return Elements.tooltipOf(dot);
    }

    function test_rendersOneCapsule() {
        const dot = makeDot({});   // inactive by default
        verify(dot, "dot created");
        compare(dot.implicitWidth, dot.dotSize, "inactive footprint is a dot wide");
        compare(dot.implicitHeight, dot.dotSize, "implicitHeight advertises the dot size");

        // Visible ones only, as a marker can exist in the tree while hidden.
        const rects = TreeWalk.collect(dot, Elements.isCircle).filter(r => r.visible);
        compare(rects.length, 1, "renders exactly one visible dot/capsule rectangle");
    }

    function test_inactiveCircleFollowsTheme() {
        const dot = makeDot({ inactiveOpacity: 0.45 });
        const circle = circleOf(dot);
        verify(circle, "found the circle");
        compare(circle.color, Kirigami.Theme.textColor, "dim circle uses the theme text colour");
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "circle is dimmed to inactiveOpacity");
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "inactive is a dot-sized circle");
    }

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

    function test_clickEmitsActivated() {
        const dot = makeDot({});
        activatedSpy.target = dot;
        activatedSpy.clear();

        mouseClick(dot, dot.width / 2, dot.height / 2);
        compare(activatedSpy.count, 1, "clicking the dot emits activated");
    }

    // Near the pill's left edge, outside where a dot would be.
    function test_hitAreaCoversCapsule() {
        const dot = makeDot({ active: true });   // active → width is pillWidth (wider than a dot)
        activatedSpy.target = dot;
        activatedSpy.clear();

        mouseClick(dot, 2, dot.height / 2);   // near the left edge of the capsule
        compare(activatedSpy.count, 1, "the whole capsule is the click target");
    }

    // vertical

    function test_verticalActiveGrowsTall() {
        const dot = makeDot({ vertical: true, active: true });
        const circle = circleOf(dot);
        fuzzyCompare(circle.height, dot.pillWidth, 0.5, "active vertical capsule grows tall (height → pillWidth)");
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "width stays a dot thick");
        fuzzyCompare(dot.implicitHeight, dot.pillWidth, 0.5, "implicitHeight tracks the capsule length");
        fuzzyCompare(dot.implicitWidth, dot.dotSize, 0.5, "implicitWidth stays a dot thick");
    }

    function test_verticalInactiveIsDot() {
        const dot = makeDot({ vertical: true, active: false });
        const circle = circleOf(dot);
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "inactive width is a dot");
        fuzzyCompare(circle.height, dot.dotSize, 0.5, "inactive height is a dot");
        fuzzyCompare(dot.implicitWidth, dot.dotSize, 0.5, "implicitWidth is a dot");
        fuzzyCompare(dot.implicitHeight, dot.dotSize, 0.5, "implicitHeight is a dot");
    }

    // A radius taken from the long side rounded a tall pill into a lozenge.
    function test_verticalRadiusStaysStadium() {
        const dot = makeDot({ vertical: true, active: true });
        const circle = circleOf(dot);
        fuzzyCompare(circle.radius, dot.dotSize / 2, 0.5, "vertical capsule keeps stadium ends (radius == dotSize/2)");
    }

    function test_horizontalRadiusUnchanged() {
        const dot = makeDot({ active: true });   // default horizontal
        const circle = circleOf(dot);
        fuzzyCompare(circle.radius, dot.dotSize / 2, 0.5, "horizontal capsule radius is dotSize/2");
    }

    function test_independentPillThickness() {
        const active = makeDot({ active: true, dotSize: 8, pillSize: 24, pillWidth: 72 });
        const circle = circleOf(active);
        fuzzyCompare(circle.height, 24, 0.5, "horizontal active capsule is pill-thick across (height == pillSize)");
        fuzzyCompare(circle.width, 72, 0.5, "horizontal active capsule is pill-long (width == pillWidth)");
        fuzzyCompare(circle.radius, 12, 0.5, "stadium ends at half the pill thickness (pillSize/2)");

        const inactive = makeDot({ active: false, dotSize: 8, pillSize: 24, pillWidth: 72 });
        const inactiveCircle = circleOf(inactive);
        fuzzyCompare(inactiveCircle.width, 8, 0.5, "inactive stays a dotSize circle (width)");
        fuzzyCompare(inactiveCircle.height, 8, 0.5, "inactive stays a dotSize circle (height)");
        fuzzyCompare(inactiveCircle.radius, 4, 0.5, "inactive radius is dotSize/2");
    }

    // hover

    function test_hoverDefaults() {
        const dot = makeDot({});
        compare(dot.hovered, false, "a fresh dot is not hovered");
        compare(typeof dot.hoverOpacity, "number", "hoverOpacity is a number");
    }

    // tst_logic.qml holds the opacity rule; this holds the pointer's way into it.
    function test_hoverBrightensInactiveDot() {
        const dot = makeDot({ active: false, inactiveOpacity: 0.45, hoverOpacity: 0.8 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "starts dim");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        tryCompare(circle, "opacity", dot.hoverOpacity, 2000, "brightens to hoverOpacity on hover");

        mouseMove(dot, -5, -5);   // move the pointer off the element
        tryCompare(circle, "opacity", dot.inactiveOpacity, 2000, "returns to inactiveOpacity when not hovered");
    }

    function test_activeCapsuleFullStrengthHoverNoEffect() {
        const dot = makeDot({ active: true, inactiveOpacity: 0.45, hoverOpacity: 0.8 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, 1.0, 0.001, "active capsule is full strength at rest");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        // Long enough for a wrong animation to have moved it.
        wait(Math.max(50, Kirigami.Units.longDuration * 2));
        fuzzyCompare(circle.opacity, 1.0, 0.001, "hover does not change the active capsule");
    }

    // occupancy
    function test_occupiedDotUsesOccupiedOpacity() {
        const dot = makeDot({ active: false, occupied: true, occupancyStyle: Logic.OCCUPANCY.Filled,
                              inactiveOpacity: 0.45, hoverOpacity: 0.8, occupiedOpacity: 0.7 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.occupiedOpacity, 0.001, "an occupied inactive dot uses occupiedOpacity");

        dot.occupied = false;
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "an empty inactive dot falls back to inactiveOpacity");
    }

    function test_occupiedPrecedence() {
        const active = makeDot({ active: true, occupied: true, occupancyStyle: Logic.OCCUPANCY.Filled, occupiedOpacity: 0.7 });
        fuzzyCompare(circleOf(active).opacity, 1.0, 0.001, "active beats occupied (full strength)");

        const dot = makeDot({ active: false, occupied: true, occupancyStyle: Logic.OCCUPANCY.Filled, hoverOpacity: 0.8, occupiedOpacity: 0.7 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, dot.occupiedOpacity, 0.001, "occupied at rest");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        tryCompare(circle, "opacity", dot.hoverOpacity, 2000, "hover beats occupied");
    }

    function test_filledStyleColorsOccupied() {
        const dot = makeDot({ occupied: true, occupancyStyle: Logic.OCCUPANCY.Filled, active: false, inactiveOpacity: 0.45, occupiedOpacity: 0.7 });
        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.highlightColor, "Filled: occupied dot uses the occupied (theme accent) colour");
        fuzzyCompare(circle.opacity, dot.occupiedOpacity, 0.001, "Filled: occupied dot uses the occupied opacity");

        dot.occupied = false;
        compare(circle.color, Kirigami.Theme.textColor, "Filled: an empty dot stays the inactive (text) colour");
        fuzzyCompare(circle.opacity, dot.inactiveOpacity, 0.001, "Filled: an empty dot is dim");
    }

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
        // The marker once sat off-centre.
        const ic = inner.mapToItem(dot, inner.width / 2, inner.height / 2);
        const cc = circle.mapToItem(dot, circle.width / 2, circle.height / 2);
        fuzzyCompare(ic.x, cc.x, 0.5, "inner dot is horizontally centred on the dot");
        fuzzyCompare(ic.y, cc.y, 0.5, "inner dot is vertically centred on the dot");

        const empty = makeDot({ occupied: false, occupancyStyle: Logic.OCCUPANCY.InnerDot });
        verify(!empty.showInnerDot, "an empty dot shows no inner dot");
        compare(TreeWalk.collect(empty, Elements.isCircle).filter(c => c.visible).length, 1, "only the dot renders when empty");
    }

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

    // tst_logic.qml holds the colour rule; this holds the custom colour's way to each marker.
    function test_customOccupiedColorWhenNotFollowingTheme() {
        const occ = "#abcdef";

        const filled = makeDot({ followThemeColors: false, occupiedColor: occ, occupied: true,
                                 occupancyStyle: Logic.OCCUPANCY.Filled, active: false });
        compare(circleOf(filled).color, filled.occupiedColor, "Filled: occupied body uses the custom occupiedColor");

        const innerStyle = makeDot({ followThemeColors: false, occupiedColor: occ, occupied: true,
                                     occupancyStyle: Logic.OCCUPANCY.InnerDot, active: false });
        const inner = TreeWalk.collect(innerStyle, Elements.isCircle).filter(c => c.visible)
                              .find(c => c !== circleOf(innerStyle));
        verify(inner, "found the inner dot");
        compare(inner.color, innerStyle.occupiedColor, "InnerDot: centre marker uses the custom occupiedColor");

        const ringStyle = makeDot({ followThemeColors: false, occupiedColor: occ, occupied: true,
                                    occupancyStyle: Logic.OCCUPANCY.Ring, active: false });
        const ring = TreeWalk.collect(ringStyle, Elements.isCircle).filter(c => c.visible)
                             .find(c => c !== circleOf(ringStyle));
        verify(ring, "found the ring overlay");
        compare(ring.border.color, ringStyle.occupiedColor, "Ring: border uses the custom occupiedColor");
    }

    // ring style
    function test_filledRingStyleInactiveIsHollow() {
        const dot = makeDot({ dotStyle: Logic.DOT_STYLE.Ring, active: false, inactiveOpacity: 0.45 });
        verify(dot.hasRing, "a non-current dot in the Filled & ring style draws the ring outline");
        verify(dot.bodyIsHollow, "an empty non-current dot has a transparent interior");
        const circle = circleOf(dot);
        verify(Qt.colorEqual(circle.color, "transparent"), "inactive ring body has a transparent fill (hollow)");
        verify(circle.border.width > 0, "inactive ring body has a visible border");
        compare(circle.border.color, Kirigami.Theme.textColor, "the ring border uses the inactive (text) colour");
        fuzzyCompare(circle.opacity, 1.0, 0.001, "the ring body is full opacity, not dimmed to inactiveOpacity");
        compare(TreeWalk.collect(dot, Elements.isCircle).filter(c => c.visible).length, 1, "ring body is the single element (no overlay)");

        dot.active = true;
        verify(!dot.hasRing, "the current dot has no ring outline (filled circle)");
        verify(!dot.bodyIsHollow, "the current dot is filled, not hollow");
        compare(circle.color, Kirigami.Theme.highlightColor, "active → filled highlight circle");
        fuzzyCompare(circle.border.width, 0, 0.001, "active → no ring border (solid fill)");
    }

    function test_filledRingStyleOccupancyComposition() {
        // Filled once took the ring's outline away along with the hollow interior.
        const filled = makeDot({ dotStyle: Logic.DOT_STYLE.Ring, occupied: true,
                                 occupancyStyle: Logic.OCCUPANCY.Filled, occupiedOpacity: 0.7, active: false });
        verify(filled.hasRing, "Filled occupancy keeps the ring outline in the Filled & ring style");
        verify(!filled.bodyIsHollow, "Filled occupancy fills the ring interior");
        verify(filled.ringFilled, "occupied + Filled → ring outline + filled background");
        const fc = circleOf(filled);
        verify(fc.border.width > 0, "the ring outline stays visible (regression: it must not vanish)");
        compare(fc.border.color, Kirigami.Theme.textColor, "the outline keeps the dim ring colour");
        fuzzyCompare(fc.opacity, 1.0, 0.001, "the body opacity is full (the outline stays crisp)");
        verify(!Qt.colorEqual(fc.color, "transparent"), "the interior is filled, not transparent");
        fuzzyCompare(fc.color.a, filled.occupiedOpacity, 0.01, "the filled interior carries the occupied opacity (baked into the fill)");

        const inner = makeDot({ dotStyle: Logic.DOT_STYLE.Ring, occupied: true,
                                occupancyStyle: Logic.OCCUPANCY.InnerDot, active: false });
        verify(inner.hasRing, "InnerDot occupancy keeps the ring outline");
        verify(inner.bodyIsHollow, "InnerDot occupancy keeps a hollow interior");
        verify(inner.showInnerDot, "InnerDot occupancy still adds the centre dot on the ring");
        compare(TreeWalk.collect(inner, Elements.isCircle).filter(c => c.visible).length, 2, "ring body + inner dot");

        const ring = makeDot({ dotStyle: Logic.DOT_STYLE.Ring, occupied: true,
                               occupancyStyle: Logic.OCCUPANCY.Ring, active: false });
        verify(ring.hasRing, "Ring occupancy keeps the ring outline");
        verify(ring.ringFilled, "Ring occupancy is drawn as Filled in the Filled & ring style, whose dots already are rings");
        verify(!ring.bodyIsHollow, "Ring occupancy fills the ring interior");
        verify(!ring.showRing, "no Ring overlay on top of a ring");
        compare(TreeWalk.collect(ring, Elements.isCircle).filter(c => c.visible).length, 1, "only the filled ring body (no overlay)");
    }

    // tooltip

    function test_tooltipShowsDesktopName() {
        const dot = makeDot({ desktopName: "Web" });
        const tip = tooltipOf(dot);
        verify(tip, "the dot has a tooltip area");
        compare(tip.mainText, "Web", "tooltip text is the desktop name");
    }

    // accessibility
    function test_accessibleExposesButtonRole() {
        const dot = makeDot({ desktopName: "Web" });
        compare(dot.Accessible.role, Accessible.Button, "dot exposes a Button role to assistive tech");
        compare(dot.Accessible.name, "Web", "accessible name is the desktop name");

        dot.desktopName = "Mail";
        compare(dot.Accessible.name, "Mail", "accessible name tracks the desktop name");
    }

    // Otherwise every dot is the same kind of button, and nothing tells the current one apart.
    function test_accessibleCheckedTracksActive() {
        const dot = makeDot({ desktopName: "Web", active: false });
        verify(dot.Accessible.checkable, "dot is checkable so AT can report a current state");
        compare(dot.Accessible.checked, false, "an inactive dot is not checked");

        dot.active = true;
        compare(dot.Accessible.checked, true, "the active (current) dot reports checked");
    }

    function test_accessiblePressEmitsActivated() {
        const dot = makeDot({ desktopName: "Web" });
        activatedSpy.target = dot;
        activatedSpy.clear();
        dot.Accessible.pressAction();
        compare(activatedSpy.count, 1, "the accessibility press action emits activated");
    }

    // Names can lag the ids for a frame, and an empty tooltip mustn't flash up meanwhile.
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

    // window list

    function test_tooltipShowsSubText() {
        const html = "2 Windows:<ul><li>Foo</li><li>Bar</li></ul>";
        const dot = makeDot({ desktopName: "Web", tooltipText: html });
        const tip = tooltipOf(dot);
        verify(tip, "the dot has a tooltip area");
        compare(tip.subText, html, "tooltip subText is the window-list HTML");
    }

    function test_tooltipTextFormatIsRichText() {
        const dot = makeDot({ desktopName: "Web", tooltipText: "<ul><li>Foo</li></ul>" });
        const tip = tooltipOf(dot);
        compare(tip.textFormat, Text.RichText, "tooltip renders as rich text");
    }

    function test_subTextDoesNotActivateWithoutName() {
        const dot = makeDot({ desktopName: "", tooltipText: "<ul><li>Foo</li></ul>", showTooltips: true });
        const tip = tooltipOf(dot);
        verify(!tip.active, "no name → no tooltip even when a window list is present");
    }

    // colours
    function test_customColorsWhenNotFollowingTheme() {
        const dot = makeDot({ followThemeColors: false, activeColor: "#ff0000", inactiveColor: "#00ff00", active: false });
        const circle = circleOf(dot);
        compare(circle.color, dot.inactiveColor, "inactive uses the custom inactive colour");

        dot.active = true;
        compare(circle.color, dot.activeColor, "active uses the custom active colour");
    }

    function test_followThemeColorsUsesTheme() {
        const dot = makeDot({ followThemeColors: true, active: false });
        const circle = circleOf(dot);
        compare(circle.color, Kirigami.Theme.textColor, "inactive follows the theme text colour");

        dot.active = true;
        compare(circle.color, Kirigami.Theme.highlightColor, "active follows the theme highlight colour");
    }

    // animation
    function test_effectiveDurationSentinelAndOverride() {
        const auto = makeDot({ animationDuration: 0 });
        compare(auto.effectiveDuration, Kirigami.Units.longDuration, "0 resolves to the themed default");

        const overridden = makeDot({ animationDuration: 250 });
        compare(overridden.effectiveDuration, 250, "a positive value overrides the themed default");
    }

    function test_morphGateReflectsAnimateAndDuration() {
        const notLatched = makeDot({ animate: false, animationDuration: 200 });
        compare(notLatched.morphEnabled, false, "gate is off before the animate latch (instant first placement)");

        const latched = makeDot({ animate: true, animationDuration: 200 });
        compare(latched.morphEnabled, true, "gate is on once latched with a positive duration");
    }

    function test_morphAnimatesWhenLatched() {
        const dot = makeDot({ active: false, animate: true, animationDuration: 200 });
        if (!dot.morphEnabled)
            skip("animations disabled in this environment (reduce-animations / longDuration == 0)");

        const circle = circleOf(dot);
        fuzzyCompare(circle.width, dot.dotSize, 0.5, "starts as a dot");

        dot.active = true;   // morph dot → capsule
        // Still on its way on this tick, not already at the pill's width.
        verify(circle.width < dot.pillWidth - 0.5, "width animates toward the capsule (no instant jump)");
        tryCompare(circle, "width", dot.pillWidth, 2000, "the morph settles at the capsule width");
    }

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

    // A Behavior doesn't animate an initial value, so a dot created current is a pill on its first frame.
    function test_bornActiveWithLatchIsInstant() {
        const dot = makeDot({ active: true, animate: true, animationDuration: 200 });
        const circle = circleOf(dot);
        fuzzyCompare(circle.width, dot.pillWidth, 0.5, "born-active is already a capsule (no grow-in from a dot)");
    }

    function test_hoveredAliasFlipsTrue() {
        const dot = makeDot({});
        compare(dot.hovered, false, "not hovered at rest");

        mouseMove(dot, dot.width / 2, dot.height / 2);
        tryCompare(dot, "hovered", true, 2000, "hovered becomes true under the pointer");

        mouseMove(dot, -5, -5);   // pointer leaves the element
        tryCompare(dot, "hovered", false, 2000, "hovered returns to false when the pointer leaves");
    }
}
