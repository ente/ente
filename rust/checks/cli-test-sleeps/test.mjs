import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const check = join(import.meta.dirname, "check.mjs");
const listPath = "rust/checks/cli-test-sleeps/allowed.json";

let result = run({
    "rust/apps/cli/tests/cli/wait.rs":
        "fn wait() {\n    while pending() {\n        std::thread::sleep(Duration::from_millis(10));\n    }\n}\nfn done() {}\n",
    [listPath]: '{"rust/apps/cli/tests/cli/wait.rs":["wait"]}',
});
assert.equal(result.status, 0, result.stderr);
assert.equal(result.stderr, "");

result = run({
    "rust/apps/cli/tests/cli/wait.rs":
        "async fn pace() {\n    tokio::time::sleep(Duration::from_millis(300)).await;\n}\nfn settle() {\n    let delay = || thread::sleep(Duration::from_millis(500));\n    sleep(Duration::from_millis(1));\n}\n",
    "rust/apps/cli/src/main.rs":
        "fn main() {\n    std::thread::sleep(Duration::from_secs(1));\n}\n",
    [listPath]: '{"rust/apps/cli/tests/cli/wait.rs":["settle","wait"]}',
});
assert.equal(result.status, 1, result.stderr);
assert.equal(
    result.stderr,
    "rust/apps/cli/tests/cli/wait.rs:2: sleep in pace; use the ObjectStoreControl barriers in ente-test-support\nrust/apps/cli/tests/cli/wait.rs:6: sleep in settle; use the ObjectStoreControl barriers in ente-test-support\nrust/apps/cli/tests/cli/wait.rs: wait no longer sleeps; remove it from rust/checks/cli-test-sleeps/allowed.json\n",
);

function run(files) {
    const root = mkdtempSync(join(tmpdir(), "ente-cli-test-sleeps-"));
    try {
        spawnSync("git", ["init", "-q"], { cwd: root });
        for (const [path, source] of Object.entries(files)) {
            mkdirSync(join(root, dirname(path)), { recursive: true });
            writeFileSync(join(root, path), source);
        }
        return spawnSync(process.execPath, [check, root], { encoding: "utf8" });
    } finally {
        rmSync(root, { recursive: true });
    }
}
