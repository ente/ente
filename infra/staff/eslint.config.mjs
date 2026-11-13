// @ts-check

import eslint from "@eslint/js";
import reactPlugin from "eslint-plugin-react";
import hooksPlugin from "eslint-plugin-react-hooks";
import reactRefreshPlugin from "eslint-plugin-react-refresh";
import { defineConfig, globalIgnores } from "eslint/config";
import tseslint from "typescript-eslint";

export default defineConfig(
    eslint.configs.recommended,
    ...tseslint.configs.strictTypeChecked,
    ...tseslint.configs.stylisticTypeChecked,
    {
        languageOptions: { parserOptions: { projectService: true } },
        linterOptions: { reportUnusedDisableDirectives: "error" },
    },
    globalIgnores(["dist", ".env*", "eslint.config.mjs"]),
    {
        rules: {
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
            "@typescript-eslint/prefer-nullish-coalescing": "off",
        },
    },
    { files: ["**/*.{jsx,tsx}"], ...reactPlugin.configs.flat.recommended },
    { files: ["**/*.{jsx,tsx}"], ...reactPlugin.configs.flat["jsx-runtime"] },
    {
        files: ["**/*.{jsx,tsx}"],
        settings: { react: { version: "detect" } },
        rules: {
            "react/jsx-no-target-blank": ["warn", { allowReferrer: true }],
            "react/display-name": "off",
            "react/prop-types": "off",
        },
    },
    {
        files: ["**/*.{jsx,tsx}"],
        plugins: {
            "react-hooks": { rules: hooksPlugin.rules },
            "react-refresh": { rules: reactRefreshPlugin.rules },
        },
        rules: {
            ...hooksPlugin.configs.recommended.rules,
            "react-refresh/only-export-components": [
                "warn",
                { allowConstantExport: true },
            ],
        },
    },
);
