// @ts-check

import js from "@eslint/js";
import ts from "typescript-eslint";

export default ts.config(
    js.configs.recommended,
    ...ts.configs.strictTypeChecked,
    ...ts.configs.stylisticTypeChecked,
    {
        languageOptions: {
            parserOptions: {
                project: true,
                tsconfigRootDir: import.meta.dirname,
            },
        },
    },
    {
        // ESLint ignores these paths globally only when this object has no other keys.
        ignores: [
            "eslint.config.mjs",
            "scripts/*.js",
            "scripts/*.mjs",
            "scripts/*.ts",
            "app/",
            "out/",
            "dist/",
        ],
    },
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
            "@typescript-eslint/no-unused-expressions": [
                "error",
                { allowTernary: true },
            ],
            // Prefer native undefined access errors to custom assertions.
            "@typescript-eslint/no-non-null-assertion": "off",
            "@typescript-eslint/no-unnecessary-condition": [
                "error",
                { allowConstantLoopConditions: true },
            ],
        },
    },
);
