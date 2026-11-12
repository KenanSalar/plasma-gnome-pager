/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * coordinator.js imported directly. Its state outlives any one test, so this is one ordered scenario
 * that leaves every token it joins. The sharing between real panels is checked only in the shell.
 */
import QtTest
import "../../package/contents/ui/coordinator.js" as Coordinator

TestCase {
    id: testCase
    name: "Coordinator"

    function test_globalSyncAndSingleWriter() {
        var aLast = null;
        var bLast = null;
        var a = Coordinator.join(function (en, pf) { aLast = { enabled: en, prefix: pf }; });
        var b = Coordinator.join(function (en, pf) { bLast = { enabled: en, prefix: pf }; });
        verify(a !== b, "join() hands out unique tokens");
        verify(!Coordinator.haveGlobal(), "no global before the first publish");
        // Observable only before the first publish, so only here.
        compare(Coordinator.globalEnabled(), false, "global disabled before the first publish");
        compare(Coordinator.globalPrefix(), "", "global prefix empty before the first publish");
        verify(!Coordinator.isWriter(a), "no writer before anything is enabled");

        // A double leave or a stale token.
        Coordinator.leave(999999);
        verify(!Coordinator.haveGlobal(), "leave(unknown) does not establish a global");
        verify(a !== b, "leave(unknown) leaves the present instances intact");

        // An instance torn down mid-loop throws from its callback.
        var throwingToken = Coordinator.join(function () { throw new Error("torn down"); });

        Coordinator.publish(true, "Foo");
        compare(JSON.stringify(aLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "throwing peer did not block sync to a");
        compare(JSON.stringify(bLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "throwing peer did not block sync to b");
        Coordinator.leave(throwingToken);
        verify(Coordinator.haveGlobal(), "publish establishes the global");
        compare(Coordinator.globalEnabled(), true, "global enabled is recorded");
        compare(Coordinator.globalPrefix(), "Foo", "global prefix is recorded");
        compare(JSON.stringify(aLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "instance a was synced");
        compare(JSON.stringify(bLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "instance b was synced");

        verify(Coordinator.isWriter(a), "lowest-token instance is the writer");
        verify(!Coordinator.isWriter(b), "the other instance defers");

        Coordinator.publish(false, "Foo");
        verify(!Coordinator.isWriter(a), "no writer when globally disabled (a)");
        verify(!Coordinator.isWriter(b), "no writer when globally disabled (b)");
        compare(JSON.stringify(aLast), JSON.stringify({ enabled: false, prefix: "Foo" }), "disable pushed to a");
        compare(JSON.stringify(bLast), JSON.stringify({ enabled: false, prefix: "Foo" }), "disable pushed to b");

        Coordinator.publish(true, "Bar");
        compare(Coordinator.globalPrefix(), "Bar", "a later publish updates the global prefix");
        verify(Coordinator.isWriter(a), "a writes again once re-enabled");
        Coordinator.leave(a);
        verify(Coordinator.isWriter(b), "b takes over once a leaves");
        verify(!Coordinator.isWriter(a), "a no longer writes after leaving");

        // Three panels, b still joined from above, handing over as each leaves.
        var c = Coordinator.join(function () {});
        var d = Coordinator.join(function () {});
        verify(b < c && c < d, "tokens are handed out monotonically (first-joined is lowest)");
        verify(Coordinator.isWriter(b), "lowest of three present instances writes");
        verify(!Coordinator.isWriter(c), "a higher-token instance defers (c)");
        verify(!Coordinator.isWriter(d), "a higher-token instance defers (d)");
        Coordinator.leave(b);
        verify(Coordinator.isWriter(c), "c is promoted once b leaves");
        verify(!Coordinator.isWriter(d), "d still defers to c");
        Coordinator.leave(c);
        verify(Coordinator.isWriter(d), "d is promoted once c leaves — last instance standing writes");
        Coordinator.leave(d);
        verify(!Coordinator.isWriter(d), "nobody writes once every instance has left");
    }
}
