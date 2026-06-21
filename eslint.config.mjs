/*
 * Strict ESLint for the plasmoid's pure-JS tier:
 *   package/contents/ui/{logic,coordinator}.js  (the real logic + cross-instance coordination)
 *   tests/shared/{treewalk,elements}.js          (shared headless-test helpers)
 *
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Mirrors the strict core rules used in the FitnessMain project, adapted to plain JS (no
 * typescript-eslint): it drops the TS-only @typescript-eslint/no-explicit-any and keeps the
 * ESLint-core strict rules. The .qml files are NOT linted here -- qmllint (`make lint`) covers them.
 *
 * Stylistic rules (no-var, prefer-const, curly) are deliberately NOT enabled: this codebase's
 * house style is `var` + braceless single-statement ifs (the QML/.pragma library convention), so
 * the rule set is correctness-only (recommended + the strict signature rules), matching the
 * reference project's approach.
 *
 * These are QML ".pragma library" modules whose leading ".pragma library" / ".import ... as X"
 * directives are NOT valid JavaScript, so a thin custom parser (tools/eslint-qml-js-parser.mjs)
 * rewrites them to line-preserving comments before espree parses. Their top-level function/var
 * declarations are implicit QML exports (consumed by the .qml importers), so no-unused-vars uses
 * vars:"local" to treat top-level decls as exports while still strictly checking params and
 * in-function locals.
 */
import js from '@eslint/js';
import globals from 'globals';
import qmlJsParser from './tools/eslint-qml-js-parser.mjs';

export default [
    {
        ignores: [
            // node_modules is also ignored by ESLint's flat-config default; listed explicitly for clarity.
            'node_modules/**',
            'dist/**',
            'build/**',
            'package/contents/locale/**',
            // This config and the custom parser are ESM tooling (real `import`s) — NOT ".pragma library"
            // QML modules — so they are not part of the linted JS tier; the script-mode block below would
            // mis-parse them. (The parser is still exercised every run, by linting the JS tier through it.)
            'eslint.config.mjs',
            'tools/**',
        ],
    },
    {
        files: ['package/contents/ui/*.js', 'tests/shared/*.js'],
        languageOptions: {
            ecmaVersion: 2021,
            sourceType: 'script', // QML .pragma library modules are script-like, not ESM
            parser: qmlJsParser,
            globals: { ...globals.es2021 }, // Object, Math, JSON, String, Number, Array, globalThis
        },
        rules: {
            ...js.configs.recommended.rules,
            'no-unused-vars': [
                'error',
                {
                    vars: 'local', // top-level decls in a .pragma library are QML exports
                    args: 'after-used',
                    argsIgnorePattern: '^_',
                    varsIgnorePattern: '^_',
                    caughtErrors: 'all',
                    caughtErrorsIgnorePattern: '^_',
                },
            ],
            // These three are already in js.configs.recommended as of ESLint 10; listed explicitly
            // to pin the strict intent (mirrors FitnessMain) and stay strict if recommended changes.
            'no-unassigned-vars': 'error',
            'no-useless-assignment': 'error',
            'preserve-caught-error': 'error',
        },
    },
];
