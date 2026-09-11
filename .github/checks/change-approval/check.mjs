import { readChanges } from "./changes.mjs";
import { checkDependencies } from "./dependencies.mjs";
import { checkFiles } from "./files.mjs";
import { writeReport } from "./report.mjs";
import { checkRust } from "./rust.mjs";
import { checkWeb } from "./web.mjs";

const [base = "origin/main"] = process.argv.slice(2);
const changes = readChanges(base, !process.env.GITHUB_OUTPUT);

writeReport({
    files: checkFiles(changes),
    dependencies: checkDependencies(changes),
    rust: checkRust(changes),
    web: checkWeb(changes),
});
