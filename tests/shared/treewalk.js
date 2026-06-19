// Plasma Gnome Pager — tests/shared/treewalk.js
//
// SPDX-FileCopyrightText: 2026 Kenan Salar
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shared, stateless test helper: depth-first collect of descendants matching a predicate.
// The component tests can't do a flat `children` scan — the circle/tooltip/dot delegates are
// nested inside per-dot ToolTipAreas/Repeaters — so each tier walked the tree itself. This is
// that one walk, shared. `.pragma library` so it is parsed once and carries no QML context
// (mirrors package/contents/ui/logic.js).
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
