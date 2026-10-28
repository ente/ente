import { fixupConfigRules } from "@eslint/compat";
import eslint from "@eslint/js";
import react from "eslint-plugin-react";
import hooks from "eslint-plugin-react-hooks";
import refresh from "eslint-plugin-react-refresh";
import tseslint from "typescript-eslint";

export default tseslint.config(
    {
        ignores: [
            ".next/**",
            ".next-dev/**",
            "out/**",
            "public/**",
            "src/vendor/ente-wasm/ente_wasm*",
            "next.config.js",
            "next-env.d.ts",
            "eslint.config.mjs",
        ],
    },
    eslint.configs.recommended,
    tseslint.configs.strictTypeChecked,
    tseslint.configs.stylisticTypeChecked,
    {
        languageOptions: { parserOptions: { projectService: true } },
        linterOptions: {
            reportUnusedDisableDirectives: "error",
            noInlineConfig: true,
        },
        rules: {
            "@typescript-eslint/ban-ts-comment": [
                "error",
                {
                    "ts-ignore": true,
                    "ts-expect-error": true,
                    "ts-nocheck": true,
                    "ts-check": false,
                },
            ],
            "@typescript-eslint/no-import-type-side-effects": "error",
            "@typescript-eslint/restrict-template-expressions": [
                "error",
                { allowNumber: true },
            ],
            "@typescript-eslint/no-confusing-void-expression": [
                "error",
                { ignoreArrowShorthand: true },
            ],
            "@typescript-eslint/no-misused-promises": [
                "error",
                { checksVoidReturn: { arguments: false, attributes: false } },
            ],
            "@typescript-eslint/no-non-null-assertion": "off",
            "@typescript-eslint/no-unnecessary-condition": [
                "error",
                { allowConstantLoopConditions: true },
            ],
            "@typescript-eslint/no-unused-vars": [
                "error",
                { ignoreRestSiblings: true },
            ],
            "@typescript-eslint/prefer-nullish-coalescing": "off",
        },
    },
    ...fixupConfigRules([
        { files: ["**/*.{jsx,tsx}"], ...react.configs.flat.recommended },
        { files: ["**/*.{jsx,tsx}"], ...react.configs.flat["jsx-runtime"] },
    ]),
    {
        files: ["**/*.{jsx,tsx}"],
        settings: { react: { version: "detect" } },
        plugins: { "react-hooks": hooks, "react-refresh": refresh },
        rules: {
            "react/jsx-no-target-blank": ["warn", { allowReferrer: true }],
            "react/display-name": "off",
            "react/prop-types": "off",
            "react-hooks/rules-of-hooks": "error",
            "react-hooks/exhaustive-deps": "warn",
            "react-refresh/only-export-components": [
                "warn",
                {
                    allowConstantExport: true,
                    extraHOCs: ["styled", "createIcon"],
                },
            ],
        },
    },
    {
        files: ["src/app/**/layout.tsx", "src/app/**/page.tsx"],
        rules: {
            "react-refresh/only-export-components": [
                "warn",
                { allowConstantExport: true, allowExportNames: ["metadata"] },
            ],
        },
    },
);
