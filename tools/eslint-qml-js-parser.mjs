/*
 * ESLint custom parser: make QML ".pragma library" / ".import ... as X" JS files lintable.
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * QML's JS "library" modules begin with engine directives that are NOT valid JavaScript:
 *
 *     .pragma library
 *     .import "logic.js" as Logic
 *
 * espree (ESLint's default parser) rejects the leading ".". This is a thin wrapper around espree
 * that rewrites those two directive forms to equivalent JS comments BEFORE parsing, on the SAME
 * line (no lines added or removed), so every reported line/column still matches the real source:
 *
 *     .pragma library              ->  / * qml directive: .pragma library * /
 *     .import "logic.js" as Logic  ->  / * global Logic * /
 *
 * The ".import" rewrite emits an ESLint `/ * global NAME * /` directive, so no-undef sees the
 * cross-module binding the QML engine injects (Logic, TreeWalk) without a false positive. Only the
 * 1-2 directive lines change, so positions are exact everywhere else.
 *
 * A custom parser (languageOptions.parser) is used rather than a flat-config processor because a
 * processor emits a nested VIRTUAL filename (e.g. "logic.js/0_qml.js") that the config's `files`
 * globs do not match, so the rules silently never run on the extracted block. A parser transforms
 * the text in place, so `files`/`rules` apply directly to the real file. This is the mechanism
 * ESLint documents for custom parsing (parseForESLint -> { ast, scopeManager, visitorKeys }).
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
