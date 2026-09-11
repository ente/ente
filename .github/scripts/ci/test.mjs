import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const script = join(import.meta.dirname, "check.mjs");
const paths = JSON.parse(
    readFileSync(new URL("paths.json", import.meta.url), "utf8"),
);

test("docs changes do not wait for unrelated workflows", (t) => {
    const selected = select(t, ["docs/docs/photos/faq.md"]);
    assert.deepEqual(selected, ["docs-verify-build", "repo-lint"]);
    checkResult(results(selected));
});

test("shared build inputs select their consumers", (t) => {
    assert.deepEqual(select(t, [".github/actions/setup-flutter/action.yml"]), [
        "mobile-lint",
        "mobile-podfile-lock",
        "repo-lint",
    ]);
    assert.deepEqual(select(t, ["rust/crates/core/src/lib.rs"]), [
        "ensu-android-build",
        "ensu-ios-build",
        "mobile-lint",
        "repo-lint",
        "rust-lint",
        "rust-test",
        "web-lint",
    ]);
    assert.ok(select(t, ["server/pkg/api.go"]).includes("rust-test"));
    assert.deepEqual(select(t, ["rust/apps/cli-next/src/main.rs"]), [
        "repo-lint",
        "rust-cli-test",
        "rust-lint",
        "rust-test",
    ]);
    assert.ok(
        select(t, ["rust/bindings/napi/src/lib.rs"]).includes("desktop-lint"),
    );
});

test("path filters cover root files, nested files, and dotfiles", (t) => {
    for (const file of [
        "Cargo.lock",
        "rust/Cargo.lock",
        "rust/.config/Cargo.lock",
    ]) {
        assert.ok(select(t, [file]).includes("dependency-review"), file);
    }
    for (const file of [
        "mobile/Podfile",
        "mobile/apps/photos/Podfile",
        "mobile/apps/photos/test.podspec",
    ]) {
        assert.ok(select(t, [file]).includes("mobile-podfile-lock"), file);
    }
    for (const file of [
        "web/.prettierrc.json",
        "web/.config/deep/file.js",
        "web/apps/file\nname.js",
    ]) {
        assert.ok(select(t, [file]).includes("web-lint"), file);
    }
    assert.deepEqual(
        select(t, ["README.md", "website/page.js", "CargoXlock"]),
        ["repo-lint"],
    );
    assert.deepEqual(select(t, []), ["repo-lint"]);
    assert.ok(
        select(t, [".github/workflows/mobile-lint.yml"]).includes(
            "mobile-lint",
        ),
    );
});

test("deletions and moves select every affected area", (t) => {
    const before = ["web/shared.txt"];
    assert.deepEqual(select(t, [], before), ["repo-lint", "web-lint"]);
    assert.deepEqual(select(t, ["desktop/shared.txt"], before), [
        "desktop-lint",
        "repo-lint",
        "web-lint",
    ]);
});

test("changes to CI selection or wiring run every workflow", (t) => {
    for (const file of [
        ".github/scripts/ci/paths.json",
        ".github/scripts/ci/check.mjs",
        ".github/workflows/ci.yml",
    ]) {
        assert.deepEqual(select(t, [file]), Object.keys(paths));
    }
});

test("selected failures, cancellations, and skips block merging", () => {
    for (const result of ["failure", "cancelled", "skipped"]) {
        const needs = results(["repo-lint", "web-lint"]);
        needs["web-lint"].result = result;
        checkResult(
            needs,
            new RegExp(`web-lint: expected success, got ${result}`),
        );
    }
});

test("failed selection and missing results cannot report success", () => {
    const needs = results(["repo-lint"]);
    needs.select.result = "failure";
    checkResult(needs, /CI selection did not succeed/);
    needs.select.result = "success";
    delete needs["repo-lint"];
    checkResult(needs, /repo-lint: expected success, got no result/);
    needs.select.outputs.jobs = "[]";
    checkResult(needs, /Invalid CI selection/);
});

test("Git errors stop selection", (t) => {
    const cwd = mkdtempSync(join(tmpdir(), "ente-ci-"));
    t.after(() => rmSync(cwd, { recursive: true }));
    const output = join(cwd, "output");
    const result = run(["select", "not-a-revision", "HEAD"], {
        env: { ...process.env, GITHUB_OUTPUT: output },
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /bad revision/);
    assert.equal(result.stdout, "");
    assert.equal(existsSync(output), false);
});

test("invalid arguments report usage", () => {
    for (const args of [[], ["select", "HEAD"], ["result", "extra"]]) {
        const result = run(args);
        assert.equal(result.status, 1);
        assert.match(
            result.stderr,
            /Usage: check.mjs select BASE HEAD \| result/,
        );
        assert.equal(result.stdout, "");
    }
});

function select(t, files, before = []) {
    const cwd = mkdtempSync(join(tmpdir(), "ente-ci-"));
    t.after(() => rmSync(cwd, { recursive: true }));
    const git = (...args) =>
        execFileSync("git", args, {
            cwd,
            encoding: "utf8",
            input: "fixture\n",
        }).trim();
    git("init", "-q");
    const blob = git("hash-object", "-w", "--stdin");
    const tree = (files) => {
        git("read-tree", "--empty");
        for (const file of files)
            git(
                "update-index",
                "--add",
                "--cacheinfo",
                `100644,${blob},${file}`,
            );
        return git("write-tree");
    };
    const output = join(cwd, "output");
    const result = run(["select", tree(before), tree(files)], {
        cwd,
        env: { ...process.env, GITHUB_OUTPUT: output },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, "");
    const data = readFileSync(output, "utf8");
    assert.match(data, /^jobs=\[.*\]\n$/);
    const selected = JSON.parse(data.slice(5));
    assert.equal(result.stdout, `Selected CI: ${selected.join(", ")}\n`);
    return selected;
}

function results(selected) {
    return {
        ...Object.fromEntries(
            Object.keys(paths).map((job) => [
                job,
                { result: selected.includes(job) ? "success" : "skipped" },
            ]),
        ),
        select: {
            result: "success",
            outputs: { jobs: JSON.stringify(selected) },
        },
    };
}

function checkResult(needs, error) {
    const result = run(["result"], {
        env: { ...process.env, NEEDS: JSON.stringify(needs) },
    });
    assert.equal(result.status, error ? 1 : 0, result.stderr);
    assert.equal(
        result.stdout,
        error ? "" : "All selected CI workflows passed.\n",
    );
    if (error) assert.match(result.stderr, error);
    else assert.equal(result.stderr, "");
}

function run(args, options = {}) {
    return spawnSync(process.execPath, [script, ...args], {
        encoding: "utf8",
        ...options,
    });
}
