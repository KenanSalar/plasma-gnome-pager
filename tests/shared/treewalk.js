// Plasma Gnome Pager — tests/shared/treewalk.js
//
// SPDX-FileCopyrightText: 2026 Kenan Salar
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared test helper: depth-first collect of descendants matching a predicate (the circle/tooltip/dot
// delegates are nested inside per-dot ToolTipAreas/Repeaters, so a flat children scan won't do).
// `.pragma library` mirrors logic.js.
.pragma library

// Return every descendant of `item` (any depth) for which pred(child) is true.
function collect(item, pred) {
    var acc = [];
    _walk(item, pred, acc);
    return acc;
}

function _walk(item, pred, acc) {
    var kids = item.children;
    for (var i = 0; i < kids.length; i++) {
        var c = kids[i];
        if (pred(c))
            acc.push(c);
        _walk(c, pred, acc);
    }
}
