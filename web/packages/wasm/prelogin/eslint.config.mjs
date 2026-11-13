import config from "ente-build-config/eslintrc-base.mjs";

export default [...config, { ignores: ["pkg/"] }];
