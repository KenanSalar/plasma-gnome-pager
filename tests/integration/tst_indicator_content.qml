/*
 * Plasma Gnome Pager — tst_indicator_content.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Content & reactivity: per-screen current desktop, names/tooltips/occupancy relay, colours, hover,
 * accessibility, and bind-don't-cache mutations.
 * Derives from the shared IndicatorTestCase (tests/shared/) for the fixtures: the component
 * factory, the VirtualDesktopInfo doubles, the switchRequested spy, and the dot-tree locators.
 */
import QtQuick                        // Text.RichText + the Accessible attached property
import org.kde.kirigami as Kirigami
import "../shared"
import "../shared/elements.js" as Elements

IndicatorTestCase {
    id: contentCase
    name: "IndicatorContent"

    // The active dot follows THIS screen's current desktop, not the global one.
    function test_perScreenActiveFollowsOwnScreen() {
        const vdi = makeMock(ids, ids[0]);              // global current = first desktop
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[2], "resolves this screen's current, not the global one");
        verify(dotByUuid(indicator, ids[2]).active, "this screen's current desktop is the active dot");
        verify(!dotByUuid(indicator, ids[0]).active, "the global current is NOT active on this screen");
    }

    // The reported bug: switching ANOTHER monitor's desktop must NOT move this strip's pill.
    function test_perScreenIgnoresOtherScreenSwitch() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[2]).active, "starts on this screen's current (uuid-c)");

        // Monitor DP-1 switches to uuid-b: its per-screen current and the global current both move.
        vdi.perScreenCurrent = { "DP-1": ids[1], "DP-2": ids[2] };
        vdi.currentDesktop = ids[1];                    // global follows the active output (DP-1)
        vdi.currentDesktopForScreenChanged("DP-1");

        compare(indicator.currentDesktop, ids[2], "this screen's current is unchanged");
        verify(dotByUuid(indicator, ids[2]).active, "this screen's pill stays put when ANOTHER screen switches");
        verify(!dotByUuid(indicator, ids[1]).active, "it does not follow the other screen's new desktop");
    }

    // This screen's own switch updates the active dot reactively (bind, don't cache).
    function test_perScreenReactiveToOwnScreenSwitch() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-2": ids[0] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[0]).active, "starts on uuid-a");

        vdi.perScreenCurrent = { "DP-2": ids[1] };
        vdi.currentDesktopForScreenChanged("DP-2");     // this output switched

        compare(indicator.currentDesktop, ids[1], "current re-resolves to this screen's new desktop");
        verify(dotByUuid(indicator, ids[1]).active, "the active dot moves to the new current");
        verify(!dotByUuid(indicator, ids[0]).active, "the old dot deactivates");
    }

    // An unknown screen falls back to the global current (models a screen the API doesn't know).
    function test_perScreenFallsBackToGlobalWhenScreenUnknown() {
        const vdi = makeMock(ids, ids[1]);
        vdi.perScreenCurrent = { "DP-1": ids[2] };       // only DP-1 has an entry
        const indicator = makeIndicator(vdi, { screenName: "DP-UNKNOWN" });
        compare(indicator.currentDesktop, ids[1], "unknown screen falls back to the global current");
        verify(dotByUuid(indicator, ids[1]).active, "global current is active when this screen is unknown");
    }

    // Empty screenName (representation not yet placed) → global current, exercising the screenName guard.
    function test_perScreenEmptyScreenNameUsesGlobal() {
        const vdi = makeMock(ids, ids[2]);
        vdi.perScreenCurrent = { "DP-1": ids[0] };
        const indicator = makeIndicator(vdi, { screenName: "" });
        compare(indicator.currentDesktop, ids[2], "empty screenName uses the global current");
        verify(dotByUuid(indicator, ids[2]).active, "global current is active with no screen name");
    }

    // animate latch: a one-way latch gating the morph so the FIRST valid placement is instant (active
    // element already a capsule, no grow-in on reload). See CLAUDE.md.

    function test_dotsReceiveDesktopName() {
        const names = ["One", "Two", "Three"];
        const indicator = makeIndicator(makeMock(ids, currentUuid, names));
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            compare(dot.desktopName, names[i], "dot " + i + " gets its index-aligned name");
        }
    }

    // robustness.md: names can lag ids during an add/remove — the dot gets "" (no OOB).
    function test_dotDesktopNameGuardsShortNames() {
        const indicator = makeIndicator(makeMock(ids, currentUuid, ["One"]));   // names shorter than ids
        compare(dotByUuid(indicator, ids[2]).desktopName, "", "missing name resolves to empty string");
    }

    function test_showTooltipsPropagatesToDots() {
        const indicator = makeIndicator(makeMock(ids, currentUuid, ["One", "Two", "Three"]), { showTooltips: false });
        verify(!dotByUuid(indicator, ids[0]).showTooltips, "showTooltips=false reaches the dots");

        indicator.showTooltips = true;
        verify(dotByUuid(indicator, ids[0]).showTooltips, "toggling showTooltips updates the dots reactively");
    }

    // window-list tooltip: per-dot subText, index-aligned with desktopIds. main.qml hands the indicator an
    // array parallel to desktopNames; the indicator feeds each dot its entry by globalIndex (like the name).

    function test_dotsReceiveTooltipText() {
        const tips = ["win-a", "win-b", "win-c"];
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: tips });
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            compare(dot.tooltipText, tips[i], "dot " + i + " gets its index-aligned window-list subText");
        }
    }

    // robustness.md: the tooltip array can lag ids during an add/remove — the dot gets "" (no OOB).
    function test_dotTooltipTextGuardsShortArray() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: ["win-a"] });
        compare(dotByUuid(indicator, ids[2]).tooltipText, "", "missing tooltip resolves to empty string");
    }

    // Index-aligned across the whole flat list, not reset per line (mirrors test_gridNamesMapAcrossLines).
    function test_tooltipTextMapsAcrossLines() {
        const tips = ["w0", "w1", "w2", "w3"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { desktopTooltips: tips });
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).tooltipText, tips[i], "dot " + i + " keeps its global window-list subText");
    }

    // occupied-dot indicator: per-dot `occupied`, index-aligned with desktopIds (like the tooltip text). main.qml
    // hands the indicator a bool[] from the window aggregator; the indicator feeds each dot its entry by globalIndex.
    function test_dotsReceiveOccupancy() {
        const occ = [true, false, true];
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: true, desktopOccupancy: occ });
        for (let i = 0; i < ids.length; i++)
            compare(dotByUuid(indicator, ids[i]).occupied, occ[i], "dot " + i + " gets its index-aligned occupancy");
    }

    // Gated on showOccupancy: with the feature off, no dot is marked occupied (the array is ignored).
    function test_occupancyIgnoredWhenShowOccupancyOff() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: false, desktopOccupancy: [true, true, true] });
        for (let i = 0; i < ids.length; i++)
            verify(!dotByUuid(indicator, ids[i]).occupied, "dot " + i + " is not occupied while showOccupancy is off");
    }

    // robustness.md: the occupancy array can lag ids during an add/remove — a missing entry resolves to false (no OOB).
    function test_dotOccupancyGuardsShortArray() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: true, desktopOccupancy: [true] });
        verify(!dotByUuid(indicator, ids[2]).occupied, "missing occupancy resolves to false");
    }

    // Index-aligned across the whole flat list, not reset per line (mirrors test_tooltipTextMapsAcrossLines).
    function test_occupancyMapsAcrossLines() {
        const occ = [true, false, false, true];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { showOccupancy: true, desktopOccupancy: occ });
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).occupied, occ[i], "dot " + i + " keeps its global occupancy");
    }

    // The chosen occupancy STYLE reaches every dot (2 = Hollow ring); the per-style visuals are unit-tested on the dot.
    function test_dotsReceiveOccupancyStyle() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: true, occupancyStyle: 2, desktopOccupancy: [true, false, true] });
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            compare(dots[i].occupancyStyle, 2, "dot " + i + " receives the occupancyStyle");
    }

    // occupiedOpacity + occupiedColor reach every dot. Like test_dotsReceiveOccupancyStyle, this asserts
    // the wiring (the per-style look is unit-tested on the dot); occupiedColor forwards regardless of
    // followThemeColors — the dot resolves theme-vs-custom itself.
    function test_dotsReceiveOccupiedColorAndOpacity() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            showOccupancy: true, desktopOccupancy: [true, false, true],
            occupiedOpacity: 0.55, occupiedColor: "#abcdef"
        });
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++) {
            fuzzyCompare(dots[i].occupiedOpacity, 0.55, 0.001, "dot " + i + " receives occupiedOpacity");
            compare(dots[i].occupiedColor, indicator.occupiedColor, "dot " + i + " receives occupiedColor");
        }
    }

    // appearance / colour / animation config flow through: main.qml feeds the indicator the Appearance
    // keys, which it forwards per-dot. These assert the wiring (the look is covered by the dot unit tests).

    // Custom colours flow through: with followThemeColors off, each dot uses the configured colours.
    function test_colorsFlowThrough() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            followThemeColors: false,
            activeColor: "#ff0000",
            inactiveColor: "#00ff00"
        });
        const activeDot = dotByUuid(indicator, currentUuid);
        const inactiveDot = dotByUuid(indicator, ids[0]);
        compare(circleOf(activeDot).color, indicator.activeColor, "active dot uses the custom active colour");
        compare(circleOf(inactiveDot).color, indicator.inactiveColor, "inactive dot uses the custom inactive colour");
    }

    // animationDuration flows through to each dot and resolves there.
    function test_animationDurationFlowsThrough() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { animationDuration: 250 });
        const dot = dotByUuid(indicator, ids[0]);
        compare(dot.animationDuration, 250, "dot gets the configured duration");
        compare(dot.effectiveDuration, 250, "dot resolves it to effectiveDuration");
    }

    // Per-screen current: re-resolution on a LIVE indicator via the two Connections —
    // onScreenNameChanged (panel moved output) and onDesktopIdsChanged (a desktop was removed/reassigned).

    // Panel dragged to another monitor: screenName changes on a live indicator → current re-resolves
    // (onScreenNameChanged).
    function test_perScreenReactiveToScreenNameChange() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-1" });
        verify(dotByUuid(indicator, ids[0]).active, "starts on DP-1's current (uuid-a)");

        indicator.screenName = "DP-2";   // the widget's panel moved to the other monitor

        compare(indicator.currentDesktop, ids[2], "current re-resolves to the new screen's current");
        verify(dotByUuid(indicator, ids[2]).active, "the active dot follows the new output");
        verify(!dotByUuid(indicator, ids[0]).active, "the old output's dot deactivates");
    }

    // A desktop add/remove can change THIS screen's current; onDesktopIdsChanged must re-resolve it.
    function test_perScreenReResolvesOnDesktopRemoval() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[2]).active, "starts on this screen's current (uuid-c)");

        // uuid-c removed; KWin moves this screen to uuid-b. Update the map, then shrink desktopIds (which
        // fires onDesktopIdsChanged → re-resolve).
        vdi.perScreenCurrent = { "DP-2": ids[1] };
        vdi.desktopIds = [ids[0], ids[1]];

        tryCompare(indicator, "currentDesktop", ids[1], 2000, "re-resolves this screen's current after the removal");
        verify(dotByUuid(indicator, ids[1]).active, "the surviving per-screen current is the active dot");
        verify(!dotByUuid(indicator, ids[2]), "the removed desktop's dot is gone");
    }

    // Scroll edge: no active element, and remainder sign across events

    // Hover passes through the wheel layer: the behind-dots wheelArea (NoButton, no hover) must not swallow
    // hover — hovering an inactive dot in the REAL composition brightens it (analogue of the click test).
    function test_hoverBrightensDotInComposedStrip() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        const dot = dotByUuid(indicator, ids[0]);   // inactive (current is uuid-b)
        const circle = circleOf(dot);
        fuzzyCompare(circle.opacity, indicator.inactiveOpacity, 0.001, "inactive dot starts dim");

        const c = Elements.centerOf(dot, indicator);
        mouseMove(indicator, c.x, c.y);
        tryCompare(circle, "opacity", indicator.hoverOpacity, 2000, "hover brightens through the wheel layer");

        mouseMove(indicator, -5, -5);   // pointer leaves the strip
        tryCompare(circle, "opacity", indicator.inactiveOpacity, 2000, "returns to dim when not hovered");
    }

    // The placement check runs AFTER the per-screen current resolves in onCompleted: created on this
    // screen's current, that element is a capsule on frame 0 (per-screen variant of firstPlacementImmediate).
    function test_firstPlacementImmediatePerScreen() {
        const vdi = makeMock(ids, ids[0]);              // global current is uuid-a
        vdi.perScreenCurrent = { "DP-2": ids[2] };      // but THIS screen is on uuid-c
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[2], "onCompleted resolved the per-screen current");
        compare(indicator.animate, true, "the latch is on after a valid per-screen placement");
        fuzzyCompare(dotByUuid(indicator, ids[2]).width, indicator.pillWidth, 0.5,
                     "this screen's current is already a capsule on the first frame");
    }

    // per-screen degrade paths: an explicit EMPTY per-screen entry ("") is excluded by
    // resolveCurrentDesktop, so the indicator falls back to the global current (drives the pure rule e2e).
    function test_perScreenEmptyEntryFallsBackToGlobal() {
        const vdi = makeMock(ids, ids[1]);
        vdi.perScreenCurrent = { "DP-2": "" };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[1], "empty per-screen entry falls back to the global current");
        verify(dotByUuid(indicator, ids[1]).active, "the global current is the active dot");
    }

    // Older Plasma (pre-6.7): no currentDesktopByScreenName, so the typeof guard resolves the global current.
    function test_olderPlasmaDegradesToGlobal() {
        const vdi = makeLegacyVdi({ desktopIds: ids, currentDesktop: ids[2] });
        const indicator = makeIndicator(vdi, { screenName: "DP-9" });
        compare(indicator.currentDesktop, ids[2], "no per-screen API → resolves the global current");
        verify(dotByUuid(indicator, ids[2]).active, "the global current is the active dot on older Plasma");
    }

    // bind-don't-cache for the names / tooltips arrays: mutate them on a LIVE indicator and assert the
    // dots update (a cached copy would not).
    function test_reactiveDesktopNamesMutation() {
        const vdi = makeMock(ids, currentUuid, ["One", "Two", "Three"]);
        const indicator = makeIndicator(vdi);
        compare(dotByUuid(indicator, ids[0]).desktopName, "One", "initial name");

        vdi.desktopNames = ["Uno", "Dos", "Tres"];   // renamed by KWin / another pager

        tryCompare(dotByUuid(indicator, ids[0]), "desktopName", "Uno", 2000, "the dot's name updates reactively");
    }

    function test_reactiveDesktopTooltipsMutation() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: ["w0", "w1", "w2"] });
        compare(dotByUuid(indicator, ids[1]).tooltipText, "w1", "initial window-list subText");

        indicator.desktopTooltips = ["x0", "x1", "x2"];   // main.qml rebuilt the window lists

        tryCompare(dotByUuid(indicator, ids[1]), "tooltipText", "x1", 2000, "the dot's window-list subText updates reactively");
    }

    // The active capsule stays full strength on hover IN THE COMPOSED STRIP — hover affects inactive dots
    // only, even through the behind-dots wheel layer.
    function test_activeCapsuleNoHoverEffectInComposition() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        const capsule = dotByUuid(indicator, currentUuid);
        const circle = circleOf(capsule);
        fuzzyCompare(circle.opacity, 1.0, 0.001, "active capsule starts at full strength");

        const c = Elements.centerOf(capsule, indicator);
        mouseMove(indicator, c.x, c.y);
        wait(Math.max(50, Kirigami.Units.longDuration * 2));
        fuzzyCompare(circle.opacity, 1.0, 0.001, "hover does not change the active capsule in the strip");
    }

    // tooltip routing THROUGH the composed strip (not just the dot properties): reach into each dot's
    // actual PlasmaCore.ToolTipArea and assert the strip-level data lands on mainText/subText/active/textFormat.

    function test_tooltipAreaRoutesNameAndSubTextThroughStrip() {
        const names = ["One", "Two", "Three"];
        const tips = ["<ul><li>a</li></ul>", "<ul><li>b</li></ul>", "<ul><li>c</li></ul>"];
        const indicator = makeIndicator(makeMock(ids, currentUuid, names), { showTooltips: true, desktopTooltips: tips });
        for (let i = 0; i < ids.length; i++) {
            const tip = Elements.tooltipOf(dotByUuid(indicator, ids[i]));
            verify(tip, "dot " + i + " carries a ToolTipArea");
            compare(tip.mainText, names[i], "ToolTipArea.mainText is this desktop's name");
            compare(tip.subText, tips[i], "ToolTipArea.subText is this desktop's window list");
            compare(tip.textFormat, Text.RichText, "the window list renders as rich text");
            verify(tip.active, "tooltip is active when enabled and named");
        }

        // Turning tooltips off at runtime deactivates every dot's ToolTipArea (reactive through the strip).
        indicator.showTooltips = false;
        for (let j = 0; j < ids.length; j++)
            verify(!Elements.tooltipOf(dotByUuid(indicator, ids[j])).active, "ToolTipArea inactive once showTooltips is off");
    }

    // The ToolTipArea data follows the GLOBAL index across grid lines (the mapping reaches the actual tooltip).
    function test_tooltipAreaMapsAcrossGridLines() {
        const names = ["n0", "n1", "n2", "n3"];
        const tips = ["t0", "t1", "t2", "t3"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], names, 2), { showTooltips: true, desktopTooltips: tips });
        for (let i = 0; i < fourIds.length; i++) {
            const tip = Elements.tooltipOf(dotByUuid(indicator, fourIds[i]));
            compare(tip.mainText, names[i], "mainText keeps its global index across the two lines");
            compare(tip.subText, tips[i], "subText keeps its global index across the two lines");
        }
    }

    // accessibility THROUGH the composed strip (per-screen + multi-line): role/name/checked are unit-tested
    // on a lone dot; these verify they hold once composed and driven live — the CHECKED dot is THIS screen's
    // current, not the global current.

    function test_accessibleCheckedTracksPerScreenActiveDot() {
        const vdi = makeMock(ids, ids[0], ["One", "Two", "Three"]);   // global current = uuid-a
        vdi.perScreenCurrent = { "DP-2": ids[2] };                    // THIS screen is on uuid-c
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });

        verify(dotByUuid(indicator, ids[2]).Accessible.checked, "this screen's current dot reports checked to AT");
        verify(!dotByUuid(indicator, ids[0]).Accessible.checked, "the GLOBAL current is NOT checked on this screen");
        compare(dotByUuid(indicator, ids[1]).Accessible.name, "Two", "accessible name is the index-aligned desktop name");

        // This screen switches: the checked state moves reactively (same path as the visible pill).
        vdi.perScreenCurrent = { "DP-2": ids[1] };
        vdi.currentDesktopForScreenChanged("DP-2");
        verify(dotByUuid(indicator, ids[1]).Accessible.checked, "checked follows this screen's new current");
        verify(!dotByUuid(indicator, ids[2]).Accessible.checked, "the previously-current dot is no longer checked");
    }

    function test_accessibleNameMapsAcrossGridLines() {
        const names = ["n0", "n1", "n2", "n3"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], names, 2));
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).Accessible.name, names[i], "accessible name keeps its global index across lines");
    }

    // followThemeColors live toggle at the indicator level: toggle it on a running strip and assert the
    // dots' colours switch theme<->custom (the colour Behavior animates, so poll).
    function test_followThemeColorsToggledLive() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            followThemeColors: true, activeColor: "#ff0000", inactiveColor: "#00ff00"
        });
        const activeCircle = circleOf(dotByUuid(indicator, currentUuid));
        const inactiveCircle = circleOf(dotByUuid(indicator, ids[0]));
        compare(activeCircle.color, Kirigami.Theme.highlightColor, "following the theme: active dot uses highlightColor");
        compare(inactiveCircle.color, Kirigami.Theme.textColor, "following the theme: inactive dot uses textColor");

        indicator.followThemeColors = false;   // user opts into custom colours mid-session
        tryVerify(function () {
            return Qt.colorEqual(activeCircle.color, indicator.activeColor)
                && Qt.colorEqual(inactiveCircle.color, indicator.inactiveColor);
        }, 2000, "custom colours take over reactively when follow-theme is turned off");

        indicator.followThemeColors = true;    // ...and back to the theme
        tryVerify(function () {
            return Qt.colorEqual(activeCircle.color, Kirigami.Theme.highlightColor)
                && Qt.colorEqual(inactiveCircle.color, Kirigami.Theme.textColor);
        }, 2000, "toggling follow-theme back on restores the theme colours");
    }
}
