import config from "ente-build-config/eslintrc-next-app.mjs";

export default [
    ...config,
    { ignores: ["test-results/", "playwright-report/"] },
];
