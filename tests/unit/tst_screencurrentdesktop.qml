/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ScreenCurrentDesktop on VdiMock: which current desktop it picks for its screen, and every signal
 * that makes it pick again.
 */
import QtQuick
import QtTest
import "../../package/contents/ui" as Pager
import "../shared" as Shared

TestCase {
    id: testCase
    name: "ScreenCurrentDesktop"

    Component {
        id: resolverComponent
        Pager.ScreenCurrentDesktop {}
    }
    Component {
        id: vdiComponent
        Shared.VdiMock {}
    }
    // Plasma before 6.7: neither the per-screen method nor its signal.
    Component {
        id: legacyVdiComponent
        QtObject {
            property var desktopIds: []
            property string currentDesktop: ""
        }
    }

    function makeVdi(props) { return createTemporaryObject(vdiComponent, testCase, props || {}); }
    function makeResolver(props) { return createTemporaryObject(resolverComponent, testCase, props || {}); }

    function test_fallsBackToGlobalWhenNoPerScreen() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a" });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "no per-screen info → global current");
        vdi.currentDesktop = "b";   // auto-emits currentDesktopChanged
        compare(r.currentDesktop, "b", "recomputes on the global currentDesktopChanged");
    }

    function test_prefersPerScreenCurrent() {
        const vdi = makeVdi({ desktopIds: ["a", "b", "c"], currentDesktop: "a", perScreenCurrent: { "DP-1": "b", "DP-2": "c" } });
        const r1 = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        const r2 = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-2" });
        compare(r1.currentDesktop, "b", "DP-1 shows its own current");
        compare(r2.currentDesktop, "c", "DP-2 shows its own current (different from DP-1)");
    }

    function test_unknownScreenFallsBackToGlobal() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a", perScreenCurrent: { "DP-1": "b" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "HDMI-9" });
        compare(r.currentDesktop, "a", "unknown screen → global current");
    }

    function test_recomputesOnlyForThisScreen() {
        const vdi = makeVdi({ desktopIds: ["a", "b", "c"], currentDesktop: "a", perScreenCurrent: { "DP-1": "a", "DP-2": "a" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "initial");
        vdi.perScreenCurrent = { "DP-1": "a", "DP-2": "c" };   // another output switched
        vdi.currentDesktopForScreenChanged("DP-2");
        compare(r.currentDesktop, "a", "a change on DP-2 does not move DP-1's resolver");
        vdi.perScreenCurrent = { "DP-1": "b", "DP-2": "c" };   // this output switched
        vdi.currentDesktopForScreenChanged("DP-1");
        compare(r.currentDesktop, "b", "a change on DP-1 moves DP-1's resolver");
    }

    // The panel moving to another output.
    function test_recomputesOnScreenNameChange() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a", perScreenCurrent: { "DP-1": "a", "DP-2": "b" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "on DP-1");
        r.screenName = "DP-2";
        compare(r.currentDesktop, "b", "re-resolves when the panel moves to DP-2");
    }

    // The source can arrive a frame after the resolver.
    function test_recomputesWhenSourceSwapsIn() {
        const r = makeResolver({ screenName: "DP-1" });
        compare(r.currentDesktop, "", "no source yet → empty");
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "b" });
        r.virtualDesktopInfo = vdi;
        compare(r.currentDesktop, "b", "re-resolves when the source is injected");
    }

    // A screen's current desktop may be the one removed.
    function test_recomputesOnDesktopIdsChanged() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a", perScreenCurrent: { "DP-1": "a" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "initial");
        vdi.perScreenCurrent = { "DP-1": "b" };
        vdi.desktopIds = ["b"];   // auto-emits desktopIdsChanged
        compare(r.currentDesktop, "b", "recomputes on desktopIdsChanged");
    }

    function test_degradesWhenApiAbsent() {
        const legacy = createTemporaryObject(legacyVdiComponent, testCase, { desktopIds: ["a", "b"], currentDesktop: "a" });
        const r = makeResolver({ virtualDesktopInfo: legacy, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "no currentDesktopByScreenName → global current (degraded)");
    }
}
