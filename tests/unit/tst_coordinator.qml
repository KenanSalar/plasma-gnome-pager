/*
 * Plasma Gnome Pager — tst_coordinator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Smoke test for coordinator.js — the GLOBAL setting-sync + single-writer election. State is shared per
 * .pragma library, so this runs ONE ordered scenario and cleans up its tokens at the end. The actual
 * cross-instance SHARING (one library per plasmashell engine) is e2e-only.
 */
import QtTest
import "../../package/contents/ui/coordinator.js" as Coordinator

TestCase {
    id: testCase
    name: "Coordinator"

    function test_globalSyncAndSingleWriter() {
        // Capture what each instance is told via its onSync callback (how the global is pushed to it).
        var aLast = null;
        var bLast = null;
        var a = Coordinator.join(function (en, pf) { aLast = { enabled: en, prefix: pf }; });
        var b = Coordinator.join(function (en, pf) { bLast = { enabled: en, prefix: pf }; });
        verify(a !== b, "join() hands out unique tokens");
        verify(!Coordinator.haveGlobal(), "no global before the first publish");
        // Pristine pre-publish state (only observable here): global off, prefix empty.
        compare(Coordinator.globalEnabled(), false, "global disabled before the first publish");
        compare(Coordinator.globalPrefix(), "", "global prefix empty before the first publish");
        verify(!Coordinator.isWriter(a), "no writer before anything is enabled");

        // leave() with an unknown token is a harmless no-op (guards double-leave / stale ids).
        Coordinator.leave(999999);
        verify(!Coordinator.haveGlobal(), "leave(unknown) does not establish a global");
        verify(a !== b, "leave(unknown) leaves the present instances intact");

        // A throwing onSync callback (torn down mid-iteration) must not abort the push loop (publish try/catch).
        var throwingToken = Coordinator.join(function () { throw new Error("torn down"); });

        // publish() establishes the global AND pushes it to every instance (true global sync).
        Coordinator.publish(true, "Foo");
        compare(JSON.stringify(aLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "throwing peer did not block sync to a");
        compare(JSON.stringify(bLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "throwing peer did not block sync to b");
        Coordinator.leave(throwingToken);   // drop the throwing instance before the rest of the scenario
        verify(Coordinator.haveGlobal(), "publish establishes the global");
        compare(Coordinator.globalEnabled(), true, "global enabled is recorded");
        compare(Coordinator.globalPrefix(), "Foo", "global prefix is recorded");
        compare(JSON.stringify(aLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "instance a was synced");
        compare(JSON.stringify(bLast), JSON.stringify({ enabled: true, prefix: "Foo" }), "instance b was synced");

        // The single writer is the lowest-token present instance while globally enabled.
        verify(Coordinator.isWriter(a), "lowest-token instance is the writer");
        verify(!Coordinator.isWriter(b), "the other instance defers");

        // Disabling globally → NOBODY writes (true global off), and the off-state is pushed everywhere.
        Coordinator.publish(false, "Foo");
        verify(!Coordinator.isWriter(a), "no writer when globally disabled (a)");
        verify(!Coordinator.isWriter(b), "no writer when globally disabled (b)");
        compare(JSON.stringify(aLast), JSON.stringify({ enabled: false, prefix: "Foo" }), "disable pushed to a");
        compare(JSON.stringify(bLast), JSON.stringify({ enabled: false, prefix: "Foo" }), "disable pushed to b");

        // Re-enable, then the writer leaving promotes the next present instance.
        Coordinator.publish(true, "Bar");
        compare(Coordinator.globalPrefix(), "Bar", "a later publish updates the global prefix");
        verify(Coordinator.isWriter(a), "a writes again once re-enabled");
        Coordinator.leave(a);
        verify(Coordinator.isWriter(b), "b takes over once a leaves");
        verify(!Coordinator.isWriter(a), "a no longer writes after leaving");

        // Multi-instance election + handoff: the writer is always the lowest-token PRESENT instance, and
        // the next-lowest is promoted as each leaves (the multi-monitor case). (Present: b; enabled, "Bar".)
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
