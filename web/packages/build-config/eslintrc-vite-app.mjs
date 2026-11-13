// @ts-check

import config from "./eslintrc-react.mjs";

export default [...config, { ignores: ["dist", ".env*"] }];
