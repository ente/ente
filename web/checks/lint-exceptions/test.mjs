import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const check = join(import.meta.dirname, "lint.mjs");
const root = mkdtempSync(join(tmpdir(), "ente-web-lint-exceptions-"));
const file = "web/example.tsx";
try {
    assert.equal(spawnSync("git", ["init", "-q"], { cwd: root }).status, 0);
    mkdirSync(join(root, "web/checks/lint-exceptions"), { recursive: true });
    for (const source of [
        '// eslint-disable-next-line no-console -- Intentional diagnostic\nconsole.log("hello");',
        'console.log("hello"); // eslint-disable-line no-console',
        '/* eslint-disable "no-console" */\nconsole.log("hello");',
        '/* eslint no-console: "off" */\nconsole.log("hello");',
        '{/* eslint-disable-next-line no-console */}\nconsole.log("hello");',
    ]) {
        assert.equal(run(source).status, 1);
        const allowed = run(source, { [file]: ["no-console"] });
        assert.equal(allowed.status, 0, allowed.stderr);
        assert.equal(
            run(source, { "web/other.tsx": ["no-console"] }).status,
            1,
        );
    }
    assert.equal(
        run("/* eslint-disable */", { [file]: ["no-console"] }).status,
        1,
    );
    assert.equal(
        run("/* eslint-disable no-console, no-alert */", {
            [file]: ["no-console"],
        }).status,
        1,
    );
    assert.equal(run("/* eslint-enable no-console */").status, 0);
    assert.equal(
        run('const example = "/* eslint-disable no-console */";').status,
        0,
    );
    assert.equal(
        run("const example = <div>eslint-disable no-console</div>;").status,
        0,
    );
    const suppression =
        '// eslint-disable-next-line no-console\nconsole.log("hello");\n';
    for (const source of [suppression + suppression, suppression]) {
        const result = run(source, { [file]: ["no-console"] });
        assert.equal(result.status, 0, result.stderr);
    }
    for (const source of ['console.log("hello");', null]) {
        const result = run(source, { [file]: ["no-console"] });
        assert.equal(result.status, 1, result.stderr);
        assert.match(result.stderr, /no-console has no suppression/);
        const cleaned = run(source);
        assert.equal(cleaned.status, 0, cleaned.stderr);
    }
} finally {
    rmSync(root, { recursive: true });
}

function run(source, allowed = {}) {
    if (source === null) rmSync(join(root, file), { force: true });
    else writeFileSync(join(root, file), source);
    writeFileSync(
        join(root, "web/checks/lint-exceptions/suppressions.json"),
        JSON.stringify(allowed),
    );
    return spawnSync(process.execPath, [check, root], { encoding: "utf8" });
}
