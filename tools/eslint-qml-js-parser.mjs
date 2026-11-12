/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Lets ESLint read QML's JavaScript libraries, whose `.pragma library` and `.import "x.js" as X`
 * lines aren't JavaScript. Each becomes a comment on the same line, so every reported position stays
 * true, and an import becomes a `global X` directive, so no-undef knows the binding QML injects.
 *
 * A parser rather than a flat-config processor: a processor's virtual filename (`logic.js/0_qml.js`)
 * matches none of the config's `files` globs, so its rules would never run.
 */
import { parse as espreeParse } from 'espree';

const PRAGMA_RE = /^\s*\.pragma\b.*$/;
const IMPORT_RE = /^\s*\.import\s+(?:"[^"]+"|'[^']+'|[\w.]+)(?:\s+[\d.]+)?\s+as\s+([A-Za-z_$][\w$]*)\s*$/;

function transform(code) {
    return code
        .split('\n')
        .map((line) => {
            if (PRAGMA_RE.test(line)) {
                return '/* qml directive: ' + line.trim() + ' */';
            }
            const m = IMPORT_RE.exec(line);
            if (m) {
                return '/* global ' + m[1] + ' */';
            }
            return line;
        })
        .join('\n');
}

function parseForESLint(code, options) {
    return {
        ast: espreeParse(transform(code), options),
        scopeManager: null,
        visitorKeys: null,
    };
}

export default { parseForESLint };
