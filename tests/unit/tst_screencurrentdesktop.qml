/*
 * Plasma Gnome Pager — tst_screencurrentdesktop.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * UNIT test for ScreenCurrentDesktop in isolation — the per-screen current-desktop resolver extracted
 * from WorkspaceIndicator. It is pure QtQuick + logic.js (no Plasma), driven by the shared VdiMock, so
 * it loads headless. Asserts the prefer-per-screen / fall-back-to-global contract (Plasma 6.7), that
 * only THIS screen's change recomputes, the screenName/source-swap recompute paths, and the typeof
 * guard that degrades to the global current on an older Plasma without the per-screen API.
 *
 * Run with `make check-unit` (or `make check`), which sets QT_QPA_PLATFORM=offscreen.
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
    // A source WITHOUT the per-screen API (older Plasma): the per-screen signal exists (so Connections
    // resolves) but currentDesktopByScreenName does NOT, exercising the typeof guard.
    Component {
        id: legacyVdiComponent
        QtObject {
            property var desktopIds: []
            property string currentDesktop: ""
            signal currentDesktopForScreenChanged(string screenName)
        }
    }

    function makeVdi(props) { return createTemporaryObject(vdiComponent, testCase, props || {}); }
    function makeResolver(props) { return createTemporaryObject(resolverComponent, testCase, props || {}); }

    // Per-screen OFF (the default): the resolver follows the global current, and recomputes when it moves.
    function test_fallsBackToGlobalWhenNoPerScreen() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a" });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "no per-screen info → global current");
        vdi.currentDesktop = "b";   // auto-emits currentDesktopChanged
        compare(r.currentDesktop, "b", "recomputes on the global currentDesktopChanged");
    }

    // Per-screen ON: each output shows its own current.
    function test_prefersPerScreenCurrent() {
        const vdi = makeVdi({ desktopIds: ["a", "b", "c"], currentDesktop: "a", perScreenCurrent: { "DP-1": "b", "DP-2": "c" } });
        const r1 = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        const r2 = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-2" });
        compare(r1.currentDesktop, "b", "DP-1 shows its own current");
        compare(r2.currentDesktop, "c", "DP-2 shows its own current (different from DP-1)");
    }

    // An unknown screen falls back to the global even when per-screen data exists for others.
    function test_unknownScreenFallsBackToGlobal() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a", perScreenCurrent: { "DP-1": "b" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "HDMI-9" });
        compare(r.currentDesktop, "a", "unknown screen → global current");
    }

    // Only THIS screen's per-screen change recomputes; another output's change is ignored.
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

    // Moving the panel to another output (screenName change) re-resolves.
    function test_recomputesOnScreenNameChange() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a", perScreenCurrent: { "DP-1": "a", "DP-2": "b" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "on DP-1");
        r.screenName = "DP-2";
        compare(r.currentDesktop, "b", "re-resolves when the panel moves to DP-2");
    }

    // Swapping the source in (it populates a frame late) re-resolves.
    function test_recomputesWhenSourceSwapsIn() {
        const r = makeResolver({ screenName: "DP-1" });
        compare(r.currentDesktop, "", "no source yet → empty");
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "b" });
        r.virtualDesktopInfo = vdi;
        compare(r.currentDesktop, "b", "re-resolves when the source is injected");
    }

    // A desktop add/remove re-resolves (a screen's current may have been removed).
    function test_recomputesOnDesktopIdsChanged() {
        const vdi = makeVdi({ desktopIds: ["a", "b"], currentDesktop: "a", perScreenCurrent: { "DP-1": "a" } });
        const r = makeResolver({ virtualDesktopInfo: vdi, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "initial");
        vdi.perScreenCurrent = { "DP-1": "b" };
        vdi.desktopIds = ["b"];   // auto-emits desktopIdsChanged
        compare(r.currentDesktop, "b", "recomputes on desktopIdsChanged");
    }

    // Older Plasma without the per-screen API: degrades to the global current (the typeof guard).
    function test_degradesWhenApiAbsent() {
        const legacy = createTemporaryObject(legacyVdiComponent, testCase, { desktopIds: ["a", "b"], currentDesktop: "a" });
        const r = makeResolver({ virtualDesktopInfo: legacy, screenName: "DP-1" });
        compare(r.currentDesktop, "a", "no currentDesktopByScreenName → global current (degraded)");
    }
}
