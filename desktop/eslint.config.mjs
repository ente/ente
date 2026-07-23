// @ts-check

import js from "@eslint/js";
import ts from "typescript-eslint";

export default ts.config(
    js.configs.recommended,
    ...ts.configs.strictTypeChecked,
    ...ts.configs.stylisticTypeChecked,
    {
        // typescript-eslint needs this enabling type checked rules.
        languageOptions: {
            parserOptions: {
                project: true,
                tsconfigRootDir: import.meta.dirname,
            },
        },
    },
    {
        // The list of (minimatch) globs to ignore. This needs to be the only
        // key in this configuration object.
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
        // Rule customizations.
        rules: {
            // Allow numbers to be used in template literals.
            "@typescript-eslint/restrict-template-expressions": [
                "error",
                { allowNumber: true },
            ],
            // Allow void expressions as the entire body of an arrow function.
            "@typescript-eslint/no-confusing-void-expression": [
                "error",
                { ignoreArrowShorthand: true },
            ],
            // Allow free standing ternary expressions.
            "@typescript-eslint/no-unused-expressions": [
                "error",
                { allowTernary: true },
            ],
            // Allow force unwrapping potentially optional values.
            //
            // See: [Note: non-null-assertions have better stack trace]
            "@typescript-eslint/no-non-null-assertion": "off",
            // Allow `while(true)` etc.
            "@typescript-eslint/no-unnecessary-condition": [
                "error",
                { allowConstantLoopConditions: true },
            ],
        },
    },
);
