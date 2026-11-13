import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");

let result = run(
    'let home = std::env::var_os("ENTE_CLI_HOME");\nlet key = env::var("ENTE_CLI_VAULT_KEY");\nfor (name, value) in env::vars() {}\n',
);
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run(
    'let other = env::var("ENTE_CLI_OTHER");\nlet value = env::var_os(name);\n',
);
assert.equal(result.status, 1, result.stderr);
assert.equal(
    result.stderr,
    "rust/apps/cli/src/fixture.rs:1: ENTE_CLI_OTHER is not a documented environment variable\nrust/apps/cli/src/fixture.rs:2: env::var takes a string literal\n",
);

result = run(
    'let other = env::var("ENTE_CLI_OTHER");\n',
    "rust/apps/cli/tests/cli/fixture.rs",
);
assert.equal(result.status, 0, result.stderr);

function run(source, path = "rust/apps/cli/src/fixture.rs") {
    const root = mkdtempSync(join(tmpdir(), "ente-cli-env-vars-"));
    try {
        spawnSync("git", ["init", "-q"], { cwd: root });
        mkdirSync(join(root, dirname(path)), { recursive: true });
        writeFileSync(join(root, path), source);
        return spawnSync(process.execPath, [check, root], { encoding: "utf8" });
    } finally {
        rmSync(root, { recursive: true });
    }
}
