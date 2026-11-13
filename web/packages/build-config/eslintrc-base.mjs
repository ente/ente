// @ts-check

import eslint from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
    eslint.configs.recommended,
    tseslint.configs.strictTypeChecked,
    tseslint.configs.stylisticTypeChecked,
    {
        languageOptions: { parserOptions: { projectService: true } },
        linterOptions: { reportUnusedDisableDirectives: "error" },
    },
    { ignores: ["eslint.config.mjs"] },
    {
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
            // Promise-returning callbacks are allowed where a void callback is
            // expected. Global handlers report any unhandled rejection.
            "@typescript-eslint/no-misused-promises": [
                "error",
                { checksVoidReturn: { arguments: false, attributes: false } },
            ],
            // Non-null assertions are allowed when surrounding logic guarantees
            // the value. If that assumption breaks, the native error carries
            // more context than an error from a custom unwrap helper.
            "@typescript-eslint/no-non-null-assertion": "off",
            "@typescript-eslint/no-unnecessary-condition": [
                "error",
                { allowConstantLoopConditions: true },
            ],
            "@typescript-eslint/no-unused-vars": [
                "error",
                { ignoreRestSiblings: true },
            ],
            // We use `||` where a blank string should select the default.
            "@typescript-eslint/prefer-nullish-coalescing": "off",
        },
    },
);
