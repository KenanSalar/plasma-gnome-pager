/*
 * Plasma Gnome Pager — tst_coordinator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Smoke test for coordinator.js — the shared GLOBAL setting-sync + single-writer election that make
 * dynamic workspaces one global behaviour across panel instances. The cross-instance SHARING (one
 * .pragma library per plasmashell engine) can only be proven in-shell; here we exercise the module's
 * API/state machine (which also catches load/syntax errors, since coordinator.js is not qmllint-checked
 * and main.qml is not headless-testable). State is shared per .pragma library, so this runs ONE ordered
 * scenario and cleans up its tokens at the end.
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
        verify(!Coordinator.isWriter(a), "no writer before anything is enabled");

        // publish() establishes the global AND pushes it to every instance (true global sync).
        Coordinator.publish(true, "Foo");
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

        Coordinator.leave(b);
    }
}
