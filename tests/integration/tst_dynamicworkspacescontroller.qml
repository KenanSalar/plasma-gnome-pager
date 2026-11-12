/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * DynamicWorkspacesController on VdiMock and the real coordinator.js, its writes caught off its signals.
 * The coordinator's state is shared by every test here, so each publishes the global setting it needs;
 * tst_coordinator.qml runs in another qmltestrunner process and shares none of it.
 */
import QtQuick
import QtTest
import "../../package/contents/ui" as Pager
import "../../package/contents/ui/coordinator.js" as Coordinator
import "../shared"

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

    // Destroyed after its test, which leaves the coordinator, so no instance lingers in the election.
    function makeController(props) {
        return createTemporaryObject(controllerComponent, testCase, props || {});
    }

    // Without numberOfDesktops, so the controller counts desktopIds instead.
    function makeMock(ids) {
        return createTemporaryObject(vdiMockComponent, testCase, { desktopIds: ids });
    }

    function makeSpy(target, signalName) {
        return createTemporaryObject(spyComponent, testCase, { target: target, signalName: signalName });
    }

    function test_addsTrailingDesktopWhenLastOccupied() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi, namePrefix: "", defaultPrefix: "Desktop" });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");            // on globally, so this lone instance writes
        c.desktopOccupancy = [true];

        tryCompare(spy, "count", 1);
        const spec = spy.signalArguments[0][0];
        compare(spec.member, "createDesktop");
        compare(spec.args.length, 2);
        compare(spec.args[0].t, "u");
        compare(spec.args[0].v, 1, "appends at position == current count (ids.length)");
        compare(spec.args[1].t, "s");
        compare(spec.args[1].v, "Desktop 2", "default base name + the new desktop's number");
    }

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

    function test_removesSurplusTrailingEmpty() {
        const vdi = makeMock(["uuid-a", "uuid-b", "uuid-c"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false, false];

        tryCompare(spy, "count", 1);
        const spec = spy.signalArguments[0][0];
        compare(spec.member, "removeDesktop");
        compare(spec.args.length, 1);
        compare(spec.args[0].t, "s");
        compare(spec.args[0].v, "uuid-c", "removes the last desktop");
    }

    function test_noOpWhenExactlyOneTrailingEmpty() {
        const vdi = makeMock(["uuid-a", "uuid-b"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false];

        wait(100);
        compare(spy.count, 0);
    }

    function test_noOpWhenDisabled() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: false, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");               // on globally, but not on this controller
        c.desktopOccupancy = [true];

        wait(100);
        compare(spy.count, 0);
    }

    // For a frame after the set changes, occupancy still has the old length.
    function test_occupancyLengthMismatchIsNoOp() {
        const vdi = makeMock(["uuid-a", "uuid-b", "uuid-c"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false];

        wait(100);
        compare(spy.count, 0);
    }

    // Until our own write lands, another evaluation mustn't send a second one.
    function test_busyLockSuppressesReentrantDispatch() {
        const vdi = makeMock(["uuid-a"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true];
        tryCompare(spy, "count", 1);

        c.desktopOccupancy = [true];                 // a new array, so the change handler runs
        wait(100);
        compare(spy.count, 1, "busy-lock suppresses the re-entrant dispatch");

        vdi.desktopIds = ["uuid-a", "uuid-b"];       // the add landed
        c.desktopOccupancy = [true, false];
        wait(100);
        compare(spy.count, 1, "converged after the add: one trailing empty, no further dispatch");
    }

    function test_convergesByTrimmingAcrossReevaluations() {
        const vdi = makeMock(["uuid-a", "uuid-b", "uuid-c", "uuid-d"]);
        const c = makeController({ dynamicEnabled: true, virtualDesktopInfo: vdi });
        const spy = makeSpy(c, "dispatchRequested");
        Coordinator.publish(true, "");
        c.desktopOccupancy = [true, false, false, false];
        tryCompare(spy, "count", 1);
        compare(spy.signalArguments[0][0].member, "removeDesktop");
        compare(spy.signalArguments[0][0].args[0].v, "uuid-d");

        vdi.desktopIds = ["uuid-a", "uuid-b", "uuid-c"];    // KWin removed d
        c.desktopOccupancy = [true, false, false];
        tryCompare(spy, "count", 2);
        compare(spy.signalArguments[1][0].member, "removeDesktop");
        compare(spy.signalArguments[1][0].args[0].v, "uuid-c");

        vdi.desktopIds = ["uuid-a", "uuid-b"];
        c.desktopOccupancy = [true, false];
        wait(100);
        compare(spy.count, 2, "stops once exactly one trailing empty remains");
    }

    // Two panels both adding a desktop when the last one fills was a visible flash.
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

    function test_publishingGlobalEmitsSyncConfigRequested() {
        const c = makeController({ dynamicEnabled: false, virtualDesktopInfo: makeMock(["uuid-a"]) });
        const syncSpy = makeSpy(c, "syncConfigRequested");
        Coordinator.publish(true, "Synced");         // as another panel would

        tryVerify(() => syncSpy.count >= 1);
        const args = syncSpy.signalArguments[syncSpy.count - 1];
        compare(args[0], true, "the new enabled flag is pushed");
        compare(args[1], "Synced", "the new prefix is pushed");
    }

    function test_localEnablePublishesToCoordinator() {
        const c = makeController({ dynamicEnabled: false, namePrefix: "", virtualDesktopInfo: makeMock(["uuid-a"]) });
        Coordinator.publish(false, "");              // off globally, so turning it on is a change
        c.dynamicEnabled = true;

        tryVerify(() => Coordinator.globalEnabled() === true);
        verify(Coordinator.isWriter(c.dynToken), "the now-enabled lone instance becomes the writer");
    }
}
