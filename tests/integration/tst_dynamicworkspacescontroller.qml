/*
 * Plasma Gnome Pager — tst_dynamicworkspacescontroller.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Integration test for DynamicWorkspacesController — the GNOME-style "keep exactly one empty trailing
 * desktop" state machine, extracted out of the e2e-only main.qml precisely so it can be driven
 * headless. It depends only on QtQuick + the pure logic.js / coordinator.js tiers, reads desktop state
 * through a duck-typed `virtualDesktopInfo` (the shared VdiMock standing in for VirtualDesktopInfo),
 * takes occupancy as a plain injected bool[], and emits its side effects as signals — so a test can
 * feed it a state and assert the EXACT KWin call spec it would dispatch, plus the busy-lock,
 * convergence, single-writer election, and cross-instance setting sync that were previously verifiable
 * only in a live shell.
 *
 * coordinator.js is a `.pragma library` (one shared instance per engine), so the controller's election
 * + sync run against real shared state here. To stay order-independent each test publishes the global
 * it needs via Coordinator.publish(...); controllers are createTemporaryObject'd, so each leaves the
 * coordinator on destruction at the end of its test function. This file lives in the integration tier,
 * a SEPARATE qmltestrunner process from tst_coordinator.qml (which exercises coordinator.js directly),
 * so the two never share that state.
 *
 * Run with `make check` (sets QT_QPA_PLATFORM=offscreen so QtQuick initialises without a display).
 */
import QtQuick
import QtTest
import "../../package/contents/ui" as Pager
import "../../package/contents/ui/coordinator.js" as Coordinator
import "../shared"                          // VdiMock.qml (the shared VirtualDesktopInfo double)

TestCase {
    id: testCase
    name: "DynamicWorkspacesController"

    Component {
        id: controllerComponent
        Pager.DynamicWorkspacesController {}
    }
    Component {
        id: vdiMockComponent
        VdiMock {}
    }
    Component {
        id: spyComponent
        SignalSpy {}
    }

    // The controller under test, auto-cleaned (its Component.onDestruction leaves the coordinator, so
    // no instance lingers in the election between test functions). Extra props (dynamicEnabled,
    // namePrefix, virtualDesktopInfo, …) come in as `props`.
    function makeController(props) {
        return createTemporaryObject(controllerComponent, testCase, props || {});
    }

    // A duck-typed VirtualDesktopInfo with the given desktop ids (numberOfDesktops is intentionally
    // absent — the controller derives the count from desktopIds.length via `?? ids.length`, exactly as
    // the indicator does, so the position/count it sends are deterministic).
    function makeMock(ids) {
        return createTemporaryObject(vdiMockComponent, testCase, { desktopIds: ids });
    }

    function makeSpy(target, signalName) {
        return createTemporaryObject(spyComponent, testCase, { target: target, signalName: signalName });
    }

    // ── Add: the last desktop is occupied → append exactly one empty desktop. ───────────────────────
    function test_addsTrailingDesktopWhenLastOccupied() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi, namePrefix: "", defaultPrefix: "Desktop" });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");            // force the global enabled so this lone instance is the writer
        c.desktopOccupancy = [true];              // only desktop occupied → grow

        tryCompare(spy, "count", 1);
        const spec = spy.signalArguments[0][0];
        compare(spec.member, "createDesktop");
        compare(spec.args.length, 2);
        compare(spec.args[0].t, "u");
        compare(spec.args[0].v, 1, "appends at position == current count (ids.length)");
        compare(spec.args[1].t, "s");
        compare(spec.args[1].v, "Desktop 2", "default base name + the new desktop's number");
    }

    // The configured prefix is used for the auto-created desktop's name.
    function test_addNameUsesConfiguredPrefix() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi, namePrefix: "Workspace", defaultPrefix: "Desktop" });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "Workspace");
        c.desktopOccupancy = [true];

        tryCompare(spy, "count", 1);
        const spec = spy.signalArguments[0][0];
        compare(spec.member, "createDesktop");
        compare(spec.args[1].v, "Workspace 2");
    }

    // ── Remove: two trailing empties → trim the LAST one. ───────────────────────────────────────────
    function test_removesSurplusTrailingEmpty() {
        const vdi = makeMock(["uuid-a", "uuid-b", "uuid-c"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false, false];   // 2 trailing empties → trim the tail

        tryCompare(spy, "count", 1);
        const spec = spy.signalArguments[0][0];
        compare(spec.member, "removeDesktop");
        compare(spec.args.length, 1);
        compare(spec.args[0].t, "s");
        compare(spec.args[0].v, "uuid-c", "removes the last desktop");
    }

    // Exactly one trailing empty is the desired fixpoint → no action.
    function test_noOpWhenExactlyOneTrailingEmpty() {
        const vdi = makeMock(["uuid-a", "uuid-b"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false];          // one trailing empty → leave alone

        wait(100);
        compare(spy.count, 0);
    }

    // Disabled controller never acts, even when the global is enabled elsewhere and the state demands a grow.
    function test_noOpWhenDisabled() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: false, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");               // global enabled, but THIS controller is off
        c.desktopOccupancy = [true];                 // would add if enabled

        wait(100);
        compare(spy.count, 0);
    }

    // Occupancy lags the desktop set by a frame (lengths differ) → no action until it catches up.
    function test_occupancyLengthMismatchIsNoOp() {
        const vdi = makeMock(["uuid-a", "uuid-b", "uuid-c"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false];          // length 2 != ids length 3 (transient lag)

        wait(100);
        compare(spy.count, 0);
    }

    // The busy-lock stops a re-entrant dispatch before our own write reflects; the desktop SET changing
    // (our add landed) clears it, and the now-stable state (one trailing empty) is a no-op (convergence).
    function test_busyLockSuppressesReentrantDispatch() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true];                 // → add (spy 1), busy locked
        tryCompare(spy, "count", 1);

        c.desktopOccupancy = [true];                 // fresh reference → onChanged fires, but busy
        wait(100);
        compare(spy.count, 1, "busy-lock suppresses the re-entrant dispatch");

        vdi.desktopIds = ["uuid-a", "uuid-b"];       // our add landed → desktopIdsChanged clears the lock
        c.desktopOccupancy = [true, false];          // new state: one occupied + one empty
        wait(100);
        compare(spy.count, 1, "converged after the add: one trailing empty, no further dispatch");
    }

    // Several trailing empties are trimmed one per desktopIdsChanged cycle until exactly one remains.
    function test_convergesByTrimmingAcrossReevaluations() {
        const vdi = makeMock(["uuid-a", "uuid-b", "uuid-c", "uuid-d"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false, false, false];   // 3 trailing empties → remove the last (d)
        tryCompare(spy, "count", 1);
        compare(spy.signalArguments[0][0].member, "removeDesktop");
        compare(spy.signalArguments[0][0].args[0].v, "uuid-d");

        vdi.desktopIds = ["uuid-a", "uuid-b", "uuid-c"];    // KWin removed d → re-evaluate
        c.desktopOccupancy = [true, false, false];          // still 2 trailing empties → remove c
        tryCompare(spy, "count", 2);
        compare(spy.signalArguments[1][0].member, "removeDesktop");
        compare(spy.signalArguments[1][0].args[0].v, "uuid-c");

        vdi.desktopIds = ["uuid-a", "uuid-b"];              // one trailing empty remains → converged
        c.desktopOccupancy = [true, false];
        wait(100);
        compare(spy.count, 2, "stops once exactly one trailing empty remains");
    }

    // With two enabled instances present, only the elected (lowest-token) one dispatches — the
    // multi-monitor flash guard. The other defers entirely.
    function test_onlyElectedWriterDispatches() {
        const a = makeController({ dynamicEnabled: true, virtualDesktopInfo: makeMock(["uuid-a"]) });
        const b = makeController({ dynamicEnabled: true, virtualDesktopInfo: makeMock(["uuid-a"]) });
        const spyA = makeSpy(a, "dispatchRequested");
        const spyB = makeSpy(b, "dispatchRequested");
        Coordinator.publish(true, "");
        verify(a.dynToken < b.dynToken, "the first-created instance holds the lower token");

        a.desktopOccupancy = [true];
        b.desktopOccupancy = [true];
        tryCompare(spyA, "count", 1);
        wait(100);
        compare(spyA.count, 1, "the elected (lowest-token) writer dispatches");
        compare(spyB.count, 0, "the non-writer defers — no double add");
    }

    // A sibling toggling the global pushes the value to this instance as syncConfigRequested (so
    // main.qml can mirror it into this panel's persisted config).
    function test_publishingGlobalEmitsSyncConfigRequested() {
        const c = makeController({ dynamicEnabled: false, virtualDesktopInfo: makeMock(["uuid-a"]) });
        const syncSpy = makeSpy(c, "syncConfigRequested");
        Coordinator.publish(true, "Synced");         // another panel toggled the global

        tryVerify(() => syncSpy.count >= 1);
        const args = syncSpy.signalArguments[syncSpy.count - 1];
        compare(args[0], true, "the new enabled flag is pushed");
        compare(args[1], "Synced", "the new prefix is pushed");
    }

    // Toggling THIS instance on publishes the change to the coordinator (the other direction), making
    // it the global writer.
    function test_localEnablePublishesToCoordinator() {
        const c = makeController({ dynamicEnabled: false, namePrefix: "", virtualDesktopInfo: makeMock(["uuid-a"]) });
        Coordinator.publish(false, "");              // known disabled baseline so the toggle is a real change
        c.dynamicEnabled = true;                     // user toggled this panel on

        tryVerify(() => Coordinator.globalEnabled() === true);
        verify(Coordinator.isWriter(c.dynToken), "the now-enabled lone instance becomes the writer");
    }
}
