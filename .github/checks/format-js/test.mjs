import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
    copyFileSync,
    mkdirSync,
    mkdtempSync,
    readFileSync,
    rmSync,
    writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";

test("JS checks share web formatting across repository directories", (t) => {
    const root = mkdtempSync(join(tmpdir(), "ente-format-js-"));
    t.after(() => rmSync(root, { recursive: true }));
    const repository = resolve(import.meta.dirname, "../../..");
    const script = ".github/checks/format-js/check.mjs";
    for (const path of [
        script,
        "web/package-lock.json",
        "web/.prettierrc.json",
    ]) {
        mkdirSync(dirname(join(root, path)), { recursive: true });
        copyFileSync(join(repository, path), join(root, path));
    }
    const checked = [
        ".github/checks/example/check.mjs",
        ".github/scripts/nested/example.cjs",
        "rust/checks/example/check.js",
        "nested/project/checks/example/test.mjs",
        "rust/apps/example/scripts/nested/build.mjs",
        "nested/project/scripts/example/test.mjs",
    ];
    const ignored = [
        "node_modules/example/checks/test.js",
        "web/apps/example.js",
        "rust/checks/example/test.py",
        "infra/ml/test/tools/parity.js",
    ];
    const source = "function example(){return true}\n";
    for (const path of [...checked, ...ignored]) {
        mkdirSync(dirname(join(root, path)), { recursive: true });
        writeFileSync(join(root, path), source);
    }
    const run = (...args) =>
        spawnSync(process.execPath, [join(root, script), ...args], {
            cwd: join(root, "nested"),
            encoding: "utf8",
        });

    let result = run();
    assert.equal(result.status, 1, result.stdout + result.stderr);
    for (const path of checked) {
        assert.ok((result.stdout + result.stderr).includes(path), path);
        assert.equal(readFileSync(join(root, path), "utf8"), source);
    }
    result = run("--write");
    assert.equal(result.status, 0, result.stdout + result.stderr);
    for (const path of checked) {
        assert.equal(
            readFileSync(join(root, path), "utf8"),
            "function example() {\n    return true;\n}\n",
        );
    }
    for (const path of ignored) {
        assert.equal(readFileSync(join(root, path), "utf8"), source);
    }
    result = run();
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /All matched files use Prettier code style!/);
});
