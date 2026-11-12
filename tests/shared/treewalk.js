/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A depth-first search of the visual tree, as a dot's parts sit inside its tooltip and the positioners.
 */
.pragma library

/** Every descendant of `item`, at any depth, for which `pred` is true. */
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
