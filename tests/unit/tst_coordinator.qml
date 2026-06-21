/*
 * Plasma Gnome Pager — tst_coordinator.qml
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Smoke test for coordinator.js — the shared single-writer election + prefix sync used to make dynamic
 * workspaces a single GLOBAL behaviour across panel instances. The cross-instance SHARING (one .pragma
 * library per plasmashell engine) can only be proven in-shell; here we exercise the API/state machine of
 * the module itself (which also catches syntax/load errors, since coordinator.js is not qmllint-checked
 * and main.qml is not headless-testable). State is shared per .pragma library, so this runs ONE ordered
 * scenario and cleans up its tokens at the end.
 */
import QtTest
import "../../package/contents/ui/coordinator.js" as Coordinator

TestCase {
    id: testCase
    name: "Coordinator"

    function test_singleWriterAndSharedPrefix() {
        var a = Coordinator.join();
        var b = Coordinator.join();
        verify(a !== b, "join() hands out unique tokens");

        // Nobody enabled yet → no writer.
        verify(!Coordinator.isWriter(a), "no writer before any instance enables (a)");
        verify(!Coordinator.isWriter(b), "no writer before any instance enables (b)");

        // Enable the lower-token instance → it is the single writer; an enabled instance sets the prefix.
        Coordinator.configure(a, true, "Foo");
        verify(Coordinator.isWriter(a), "lowest-token enabled instance is the writer");
        verify(!Coordinator.isWriter(b), "the other instance defers");
        compare(Coordinator.prefix(), "Foo", "an enabled instance sets the shared prefix");

        // Enable the higher-token instance too → still the lower one writes; prefix syncs to the last enabled.
        Coordinator.configure(b, true, "Bar");
        verify(Coordinator.isWriter(a), "lowest-token enabled stays the writer");
        verify(!Coordinator.isWriter(b), "higher-token instance still defers");
        compare(Coordinator.prefix(), "Bar", "the last enabled configure wins the shared prefix");

        // A DISABLED instance must not override the shared prefix...
        Coordinator.configure(a, false, "Ignored");
        compare(Coordinator.prefix(), "Bar", "a disabled configure leaves the shared prefix unchanged");
        // ...and disabling the writer promotes the next enabled instance.
        verify(!Coordinator.isWriter(a), "a disabled instance is never the writer");
        verify(Coordinator.isWriter(b), "the next enabled instance takes over");

        // Leaving removes from the registry → no writer once all enabled instances are gone.
        Coordinator.leave(b);
        verify(!Coordinator.isWriter(b), "a departed instance is not the writer");
        Coordinator.leave(a);
    }
}
