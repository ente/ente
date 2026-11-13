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
            "react/jsx-no-target-blank": ["warn", { allowReferrer: true }],
            "react/display-name": "off",
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
            // eslint-plugin-react-hooks v7's preset also enables React Compiler
            // rules. Keep the existing policy until that change is reviewed.
            "react-hooks/rules-of-hooks": "error",
            "react-hooks/exhaustive-deps": "warn",
            "react-refresh/only-export-components": [
                "warn",
                { allowConstantExport: true, extraHOCs: ["styled"] },
            ],
        },
    },
];
