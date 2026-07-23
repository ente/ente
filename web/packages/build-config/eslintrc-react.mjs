import { fixupConfigRules } from "@eslint/compat";
import reactPlugin from "eslint-plugin-react";
import hooksPlugin from "eslint-plugin-react-hooks";
import reactRefreshPlugin from "eslint-plugin-react-refresh";
import config from "./eslintrc-base.mjs";

export default [
    ...config,
    // eslint-plugin-react does not support ESLint 10 yet, so wrap its configs.
    ...fixupConfigRules([
        { files: ["**/*.{jsx,tsx}"], ...reactPlugin.configs.flat.recommended },
        {
            files: ["**/*.{jsx,tsx}"],
            ...reactPlugin.configs.flat["jsx-runtime"],
        },
    ]),
    {
        files: ["**/*.{jsx,tsx}"],
        settings: { react: { version: "detect" } },
        rules: {
            // The rule is misguided - only the opener should be omitted, not
            // the referrer.
            "react/jsx-no-target-blank": ["warn", { allowReferrer: true }],
            // Otherwise we need to do unnecessary boilerplating when using memo.
            "react/display-name": "off",
            // Without React in scope, this rule starts causing false positives
            // (We don't use prop types in our own code anyways).
            "react/prop-types": "off",
        },
    },
    {
        files: ["**/*.{jsx,tsx}"],
        plugins: {
            "react-hooks": hooksPlugin,
            "react-refresh": reactRefreshPlugin,
        },
        rules: {
            // The current eslint-plugin-react-hooks recommended preset is:
            //
            // ...hooksPlugin.configs.recommended.rules,
            //
            // Keep the old effective rule set for now. In v7, recommended also
            // enables React Compiler rules, which is a separate policy change.
            "react-hooks/rules-of-hooks": "error",
            "react-hooks/exhaustive-deps": "warn",
            // "react-hooks/static-components": "error",
            // "react-hooks/use-memo": "error",
            // "react-hooks/preserve-manual-memoization": "error",
            // "react-hooks/incompatible-library": "warn",
            // "react-hooks/immutability": "error",
            // "react-hooks/globals": "error",
            // "react-hooks/refs": "error",
            // "react-hooks/set-state-in-effect": "error",
            // "react-hooks/error-boundaries": "error",
            // "react-hooks/purity": "error",
            // "react-hooks/set-state-in-render": "error",
            // "react-hooks/unsupported-syntax": "warn",
            // "react-hooks/config": "error",
            // "react-hooks/gating": "error",
            //
            // Apparently Fast refresh only works if a file only exports
            // components, and this rule warns if we break that that.
            //
            // Constants are okay though practically (otherwise we'll need to
            // create unnecessary helper files).
            "react-refresh/only-export-components": [
                "warn",
                { allowConstantExport: true, extraHOCs: ["styled"] },
            ],
        },
    },
];
