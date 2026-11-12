/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A built WorkspaceIndicator on VdiMock: what reaches each dot (this screen's current desktop, names,
 * tooltips, occupancy, colours, accessibility) and the hover background, as the sources change live.
 */
import QtQuick                        // Text.RichText + the Accessible attached property
import org.kde.kirigami as Kirigami
import "../shared"
import "../shared/elements.js" as Elements

IndicatorTestCase {
    id: contentCase
    name: "IndicatorContent"

    function test_perScreenActiveFollowsOwnScreen() {
        const vdi = makeMock(ids, ids[0]);              // global current = first desktop
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[2], "resolves this screen's current, not the global one");
        verify(dotByUuid(indicator, ids[2]).active, "this screen's current desktop is the active dot");
        verify(!dotByUuid(indicator, ids[0]).active, "the global current is NOT active on this screen");
    }

    // The reported bug: switching on one monitor moved the pill on every monitor.
    function test_perScreenIgnoresOtherScreenSwitch() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[2]).active, "starts on this screen's current (uuid-c)");

        // DP-1 switches, which moves the global current desktop with it.
        vdi.perScreenCurrent = { "DP-1": ids[1], "DP-2": ids[2] };
        vdi.currentDesktop = ids[1];                    // global follows the active output (DP-1)
        vdi.currentDesktopForScreenChanged("DP-1");

        compare(indicator.currentDesktop, ids[2], "this screen's current is unchanged");
        verify(dotByUuid(indicator, ids[2]).active, "this screen's pill stays put when ANOTHER screen switches");
        verify(!dotByUuid(indicator, ids[1]).active, "it does not follow the other screen's new desktop");
    }

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

    function test_perScreenFallsBackToGlobalWhenScreenUnknown() {
        const vdi = makeMock(ids, ids[1]);
        vdi.perScreenCurrent = { "DP-1": ids[2] };       // only DP-1 has an entry
        const indicator = makeIndicator(vdi, { screenName: "DP-UNKNOWN" });
        compare(indicator.currentDesktop, ids[1], "unknown screen falls back to the global current");
        verify(dotByUuid(indicator, ids[1]).active, "global current is active when this screen is unknown");
    }

    // The screen name is empty until the panel places the representation.
    function test_perScreenEmptyScreenNameUsesGlobal() {
        const vdi = makeMock(ids, ids[2]);
        vdi.perScreenCurrent = { "DP-1": ids[0] };
        const indicator = makeIndicator(vdi, { screenName: "" });
        compare(indicator.currentDesktop, ids[2], "empty screenName uses the global current");
        verify(dotByUuid(indicator, ids[2]).active, "global current is active with no screen name");
    }

    function test_dotsReceiveDesktopName() {
        const names = ["One", "Two", "Three"];
        const indicator = makeIndicator(makeMock(ids, currentUuid, names));
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            compare(dot.desktopName, names[i], "dot " + i + " gets its index-aligned name");
        }
    }

    // Names can lag the ids during an add or remove.
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

    // window list

    function test_dotsReceiveTooltipText() {
        const tips = ["win-a", "win-b", "win-c"];
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: tips });
        for (let i = 0; i < ids.length; i++) {
            const dot = dotByUuid(indicator, ids[i]);
            compare(dot.tooltipText, tips[i], "dot " + i + " gets its index-aligned window-list subText");
        }
    }

    function test_dotTooltipTextGuardsShortArray() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: ["win-a"] });
        compare(dotByUuid(indicator, ids[2]).tooltipText, "", "missing tooltip resolves to empty string");
    }

    function test_tooltipTextMapsAcrossLines() {
        const tips = ["w0", "w1", "w2", "w3"];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { desktopTooltips: tips });
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).tooltipText, tips[i], "dot " + i + " keeps its global window-list subText");
    }

    // occupancy
    function test_dotsReceiveOccupancy() {
        const occ = [true, false, true];
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: true, desktopOccupancy: occ });
        for (let i = 0; i < ids.length; i++)
            compare(dotByUuid(indicator, ids[i]).occupied, occ[i], "dot " + i + " gets its index-aligned occupancy");
    }

    function test_occupancyIgnoredWhenShowOccupancyOff() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: false, desktopOccupancy: [true, true, true] });
        for (let i = 0; i < ids.length; i++)
            verify(!dotByUuid(indicator, ids[i]).occupied, "dot " + i + " is not occupied while showOccupancy is off");
    }

    function test_dotOccupancyGuardsShortArray() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: true, desktopOccupancy: [true] });
        verify(!dotByUuid(indicator, ids[2]).occupied, "missing occupancy resolves to false");
    }

    function test_occupancyMapsAcrossLines() {
        const occ = [true, false, false, true];
        const indicator = makeIndicator(makeMock(fourIds, fourIds[0], [], 2), { showOccupancy: true, desktopOccupancy: occ });
        for (let i = 0; i < fourIds.length; i++)
            compare(dotByUuid(indicator, fourIds[i]).occupied, occ[i], "dot " + i + " keeps its global occupancy");
    }

    function test_dotsReceiveOccupancyStyle() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { showOccupancy: true, occupancyStyle: 2, desktopOccupancy: [true, false, true] });
        const dots = collectDots(indicator);
        for (let i = 0; i < dots.length; i++)
            compare(dots[i].occupancyStyle, 2, "dot " + i + " receives the occupancyStyle");
    }

    // The custom colour reaches the dots either way; each dot decides between it and the theme.
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

    // appearance
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

    function test_animationDurationFlowsThrough() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { animationDuration: 250 });
        const dot = dotByUuid(indicator, ids[0]);
        compare(dot.animationDuration, 250, "dot gets the configured duration");
        compare(dot.effectiveDuration, 250, "dot resolves it to effectiveDuration");
    }

    // The panel dragged to another monitor.
    function test_perScreenReactiveToScreenNameChange() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-1": ids[0], "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-1" });
        verify(dotByUuid(indicator, ids[0]).active, "starts on DP-1's current (uuid-a)");

        indicator.screenName = "DP-2";

        compare(indicator.currentDesktop, ids[2], "current re-resolves to the new screen's current");
        verify(dotByUuid(indicator, ids[2]).active, "the active dot follows the new output");
        verify(!dotByUuid(indicator, ids[0]).active, "the old output's dot deactivates");
    }

    // Removing a desktop can move this screen's current one.
    function test_perScreenReResolvesOnDesktopRemoval() {
        const vdi = makeMock(ids, ids[0]);
        vdi.perScreenCurrent = { "DP-2": ids[2] };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        verify(dotByUuid(indicator, ids[2]).active, "starts on this screen's current (uuid-c)");

        // KWin moves this screen to uuid-b before the list loses uuid-c.
        vdi.perScreenCurrent = { "DP-2": ids[1] };
        vdi.desktopIds = [ids[0], ids[1]];

        tryCompare(indicator, "currentDesktop", ids[1], 2000, "re-resolves this screen's current after the removal");
        verify(dotByUuid(indicator, ids[1]).active, "the surviving per-screen current is the active dot");
        verify(!dotByUuid(indicator, ids[2]), "the removed desktop's dot is gone");
    }

    // hover

    // Through the composed strip, where the wheel layer sits behind the dots.
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

    function test_hoverBackgroundAppearsOnHover() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        const bg = hoverBackgroundOf(indicator);
        compare(bg.visible, false, "no background at rest");

        mouseMove(indicator, 5, indicator.height / 2);   // a dot-free spot inside the cell
        tryCompare(bg, "opacity", indicator.hoverBackgroundOpacity, 2000, "fades in to the configured opacity");
        compare(bg.visible, true, "and is rendered");

        mouseMove(indicator, -5, -5);                    // pointer leaves the widget
        tryCompare(bg, "opacity", 0, 2000, "fades back out");
        tryCompare(bg, "visible", false, 2000, "and is dropped again");
    }

    // Driven by the wheel layer alone, the background blinked off over every dot. Each check after the
    // first fade-in is synchronous: `hovered` ORs two sources that change in separate notifications, so
    // a dip inside one mouseMove restarts the fade, and a tryCompare would pass once it had healed.
    function test_hoverBackgroundStaysVisibleOverADot() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        const bg = hoverBackgroundOf(indicator);
        const lit = indicator.hoverBackgroundOpacity;

        mouseMove(indicator, 5, indicator.height / 2);   // the gap first; only this one waits for the fade
        tryCompare(bg, "opacity", lit, 2000, "lit over a dot-free spot");

        const inactive = Elements.centerOf(dotByUuid(indicator, ids[0]), indicator);
        mouseMove(indicator, inactive.x, inactive.y);    // gap → dot
        compare(indicator.hovered, true, "the dot hands its hover back up to the indicator");
        fuzzyCompare(bg.opacity, lit, 0.001, "and the background never dips crossing onto a dot");

        const pill = Elements.centerOf(dotByUuid(indicator, currentUuid), indicator);
        mouseMove(indicator, pill.x, pill.y);            // dot → adjacent dot: the delegate's index guard
        compare(indicator.hovered, true, "still hovered handing straight over to the next dot");
        fuzzyCompare(bg.opacity, lit, 0.001, "and never dips between two dots");

        mouseMove(indicator, 5, indicator.height / 2);   // dot → gap: the wheel layer takes the hover back
        compare(indicator.hovered, true, "the wheel layer picks the hover back up");
        fuzzyCompare(bg.opacity, lit, 0.001, "and never dips leaving a dot");
    }

    function test_hoverBackgroundDisabledNeverShows() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50, showHoverBackground: false });
        const bg = hoverBackgroundOf(indicator);
        mouseMove(indicator, 5, indicator.height / 2);
        tryCompare(indicator, "hovered", true, 2000, "the indicator still tracks hover");
        wait(Math.max(50, Kirigami.Units.longDuration * 2));
        compare(bg.opacity, 0, "but the background stays fully transparent");
        compare(bg.visible, false, "and unrendered");
    }

    function test_hoverBackgroundFollowsThemeColor() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { width: 200, height: 50 });
        compare(hoverBackgroundOf(indicator).color, Kirigami.Theme.textColor, "follows the theme text colour");
    }
    function test_hoverBackgroundCustomColor() {
        const custom = "#ff00ff";
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            width: 200, height: 50, followThemeColors: false, hoverBackgroundColor: custom
        });
        compare(hoverBackgroundOf(indicator).color, custom, "uses the custom colour when not following the theme");

        indicator.followThemeColors = true;
        tryCompare(hoverBackgroundOf(indicator), "color", Kirigami.Theme.textColor, 2000, "and flips back live");
    }

    // The latch reads activeIndex after the screen's current desktop has resolved, not before.
    function test_firstPlacementImmediatePerScreen() {
        const vdi = makeMock(ids, ids[0]);              // global current is uuid-a
        vdi.perScreenCurrent = { "DP-2": ids[2] };      // and this screen's is uuid-c
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[2], "onCompleted resolved the per-screen current");
        compare(indicator.animate, true, "the latch is on after a valid per-screen placement");
        fuzzyCompare(dotByUuid(indicator, ids[2]).width, indicator.pillWidth, 0.5,
                     "this screen's current is already a capsule on the first frame");
    }

    function test_perScreenEmptyEntryFallsBackToGlobal() {
        const vdi = makeMock(ids, ids[1]);
        vdi.perScreenCurrent = { "DP-2": "" };
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });
        compare(indicator.currentDesktop, ids[1], "empty per-screen entry falls back to the global current");
        verify(dotByUuid(indicator, ids[1]).active, "the global current is the active dot");
    }

    function test_olderPlasmaDegradesToGlobal() {
        const vdi = makeLegacyVdi({ desktopIds: ids, currentDesktop: ids[2] });
        const indicator = makeIndicator(vdi, { screenName: "DP-9" });
        compare(indicator.currentDesktop, ids[2], "no per-screen API → resolves the global current");
        verify(dotByUuid(indicator, ids[2]).active, "the global current is the active dot on older Plasma");
    }

    function test_reactiveDesktopNamesMutation() {
        const vdi = makeMock(ids, currentUuid, ["One", "Two", "Three"]);
        const indicator = makeIndicator(vdi);
        compare(dotByUuid(indicator, ids[0]).desktopName, "One", "initial name");

        vdi.desktopNames = ["Uno", "Dos", "Tres"];   // renamed by KWin / another pager

        tryCompare(dotByUuid(indicator, ids[0]), "desktopName", "Uno", 2000, "the dot's name updates reactively");
    }

    // A reorder in KWin's Grid view or settings re-sorts the lists in place and emits only
    // desktopPositionsChanged.
    function test_dotsFollowReorderedDesktops() {
        const vdi = makeMock(ids, ids[0]);
        const indicator = makeIndicator(vdi);

        vdi.reorder([ids[1], ids[2], ids[0]]);   // the first desktop moved to the end

        compare(dotsByIndex(indicator).map(dot => dot.modelData), [ids[1], ids[2], ids[0]],
            "the dots take KWin's new order");
    }

    function test_dotNamesFollowReorderedDesktops() {
        const vdi = makeMock(ids, ids[0], ["One", "Two", "Three"]);
        const indicator = makeIndicator(vdi);

        vdi.reorder([ids[1], ids[2], ids[0]]);

        compare(dotsByIndex(indicator).map(dot => dot.desktopName), ["Two", "Three", "One"],
            "each name moves with its desktop, not with its old position");
    }

    function test_reactiveDesktopTooltipsMutation() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), { desktopTooltips: ["w0", "w1", "w2"] });
        compare(dotByUuid(indicator, ids[1]).tooltipText, "w1", "initial window-list subText");

        indicator.desktopTooltips = ["x0", "x1", "x2"];   // main.qml rebuilt the window lists

        tryCompare(dotByUuid(indicator, ids[1]), "tooltipText", "x1", 2000, "the dot's window-list subText updates reactively");
    }

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

    // Down to each dot's own ToolTipArea, not just the dot's properties.

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

        indicator.showTooltips = false;
        for (let j = 0; j < ids.length; j++)
            verify(!Elements.tooltipOf(dotByUuid(indicator, ids[j])).active, "ToolTipArea inactive once showTooltips is off");
    }

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

    // The checked dot is this screen's current desktop, not the global one.

    function test_accessibleCheckedTracksPerScreenActiveDot() {
        const vdi = makeMock(ids, ids[0], ["One", "Two", "Three"]);   // global current = uuid-a
        vdi.perScreenCurrent = { "DP-2": ids[2] };                    // this screen's is uuid-c
        const indicator = makeIndicator(vdi, { screenName: "DP-2" });

        verify(dotByUuid(indicator, ids[2]).Accessible.checked, "this screen's current dot reports checked to AT");
        verify(!dotByUuid(indicator, ids[0]).Accessible.checked, "the GLOBAL current is NOT checked on this screen");
        compare(dotByUuid(indicator, ids[1]).Accessible.name, "Two", "accessible name is the index-aligned desktop name");

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

    // The colour Behavior animates the change, hence the polling.
    function test_followThemeColorsToggledLive() {
        const indicator = makeIndicator(makeMock(ids, currentUuid), {
            followThemeColors: true, activeColor: "#ff0000", inactiveColor: "#00ff00"
        });
        const activeCircle = circleOf(dotByUuid(indicator, currentUuid));
        const inactiveCircle = circleOf(dotByUuid(indicator, ids[0]));
        compare(activeCircle.color, Kirigami.Theme.highlightColor, "following the theme: active dot uses highlightColor");
        compare(inactiveCircle.color, Kirigami.Theme.textColor, "following the theme: inactive dot uses textColor");

        indicator.followThemeColors = false;
        tryVerify(function () {
            return Qt.colorEqual(activeCircle.color, indicator.activeColor)
                && Qt.colorEqual(inactiveCircle.color, indicator.inactiveColor);
        }, 2000, "custom colours take over reactively when follow-theme is turned off");

        indicator.followThemeColors = true;
        tryVerify(function () {
            return Qt.colorEqual(activeCircle.color, Kirigami.Theme.highlightColor)
                && Qt.colorEqual(inactiveCircle.color, Kirigami.Theme.textColor);
        }, 2000, "toggling follow-theme back on restores the theme colours");
    }
}
