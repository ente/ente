// @ts-check

import config from "./eslintrc-react.mjs";

export default [
    ...config,
    {
        ignores: [
            "out",
            ".next",
            "public",
            ".env*",
            "next.config.js",
            "next-env.d.ts",
        ],
    },
];
