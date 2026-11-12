/*
 * SPDX-FileCopyrightText: 2026 Kenan Salar
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ESLint for the `.pragma library` modules, correctness rules only: the house style is `var` and
 * braceless single-statement ifs, so no-var, prefer-const and curly stay off. qmllint covers the QML.
 */
import js from '@eslint/js';
import globals from 'globals';
import qmlJsParser from './tools/eslint-qml-js-parser.mjs';

export default [
    {
        ignores: [
            'node_modules/**',
            'dist/**',
            'build/**',
            'package/contents/locale/**',
            // ES modules, which the script-mode block below would misparse.
            'eslint.config.mjs',
            'tools/**',
        ],
    },
    {
        files: ['package/contents/ui/*.js', 'tests/shared/*.js'],
        languageOptions: {
            ecmaVersion: 2021,
            sourceType: 'script',
            parser: qmlJsParser,
            globals: { ...globals.es2021 },
        },
        rules: {
            ...js.configs.recommended.rules,
            'no-unused-vars': [
                'error',
                {
                    vars: 'local', // a library's top-level declarations are what the QML imports
                    args: 'after-used',
                    argsIgnorePattern: '^_',
                    varsIgnorePattern: '^_',
                    caughtErrors: 'all',
                    caughtErrorsIgnorePattern: '^_',
                },
            ],
            // In recommended already, and named so a change to recommended can't drop them.
            'no-unassigned-vars': 'error',
            'no-useless-assignment': 'error',
            'preserve-caught-error': 'error',
        },
    },
];
