import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
    cpSync,
    existsSync,
    mkdirSync,
    mkdtempSync,
    readFileSync,
    rmSync,
    symlinkSync,
    writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

const script = join(import.meta.dirname, "check.mjs");
const env = {
    PATH: process.env.PATH,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_AUTHOR_NAME: "test",
    GIT_AUTHOR_EMAIL: "test@example.com",
    GIT_COMMITTER_NAME: "test",
    GIT_COMMITTER_EMAIL: "test@example.com",
};

const scan = (
    t,
    base,
    change,
    {
        commit: committed = true,
        gitlink,
        symlink,
        ci = false,
        workflow = false,
        directory = ".",
    } = {},
) => {
    const repo = mkdtempSync(join(tmpdir(), "change-approval-"));
    t.after(() => rmSync(repo, { recursive: true }));
    const git = (...args) =>
        execFileSync("git", args, { cwd: repo, env, encoding: "utf8" });
    const write = (files) => {
        for (const [file, content] of Object.entries(files)) {
            if (content === null) {
                rmSync(join(repo, file));
            } else {
                mkdirSync(join(repo, dirname(file)), { recursive: true });
                writeFileSync(join(repo, file), content);
            }
        }
    };
    const commit = (revision) => {
        git("add", "-A");
        if (gitlink)
            git(
                "update-index",
                "--add",
                "--cacheinfo",
                `160000,${String(revision).repeat(40)},${gitlink}`,
            );
        git("commit", "-q", "--allow-empty", "-m", "change");
        return git("rev-parse", "HEAD").trim();
    };
    git("init", "-q", "-b", "main");
    const checkerDir = ".github/checks/change-approval";
    if (workflow)
        cpSync(import.meta.dirname, join(repo, checkerDir), {
            recursive: true,
        });
    write(base);
    const sha = commit(1);
    if (workflow) {
        git("remote", "add", "origin", repo);
        git("checkout", "-qb", "pr");
    }
    write(change);
    if (symlink) symlinkSync("missing-target", join(repo, symlink));
    if (committed) commit(2);
    let command = process.execPath;
    let args = [script, sha];
    const runner = {};
    if (workflow) {
        git("checkout", "-q", "--detach", sha);
        git("merge", "--no-ff", "--no-edit", "pr");
        runner.RUNNER_TEMP = mkdtempSync(
            join(tmpdir(), "change-approval-trusted-"),
        );
        t.after(() => rmSync(runner.RUNNER_TEMP, { recursive: true }));
        const step = execFileSync(
            "ruby",
            [
                "-ryaml",
                "-e",
                'puts YAML.safe_load(File.read(ARGV[0]), aliases: true).fetch("jobs").fetch("detect").fetch("steps").find { |step| step["id"] == "scan" }.fetch("run")',
                join(
                    import.meta.dirname,
                    "../../workflows/change-approval.yml",
                ),
            ],
            { encoding: "utf8" },
        );
        command = "bash";
        args = ["-e", "-c", step];
    }
    const outputs = ci
        ? {
              GITHUB_OUTPUT: join(repo, ".output"),
              GITHUB_STEP_SUMMARY: join(repo, ".summary"),
          }
        : {};
    const stdout = execFileSync(command, args, {
        cwd: join(repo, directory),
        env: { ...env, ...outputs, ...runner },
        encoding: "utf8",
    });
    const read = (file) => (existsSync(file) ? readFileSync(file, "utf8") : "");
    return ci
        ? {
              stdout,
              output: read(outputs.GITHUB_OUTPUT),
              summary: read(outputs.GITHUB_STEP_SUMMARY),
          }
        : stdout;
};

const registry = "registry+https://github.com/rust-lang/crates.io-index";
const cargo = (packages) =>
    packages
        .map(
            ([name, version, source = registry]) =>
                `[[package]]\nname = "${name}"\nversion = "${version}"\n${source ? `source = "${source}"\n` : ""}`,
        )
        .join("\n");

const npm = (packages) => JSON.stringify({ packages: { "": {}, ...packages } });
const tarball = (name, version, host = "registry.npmjs.org") => ({
    version,
    resolved: `https://${host}/${name}/-/${name}-${version}.tgz`,
});
const pub = (packages) =>
    `packages:\n${packages
        .map(
            ([name, version, source = "hosted"]) =>
                `  ${name}:\n    dependency: transitive\n    description:\n${
                    source === "path"
                        ? `      path: "../${name}"\n      relative: true\n`
                        : `      name: ${name}\n      url: "https://pub.dev"\n`
                }    source: ${source}\n    version: "${version}"\n`,
        )
        .join("")}sdks:\n  dart: ">=3.0.0 <4.0.0"\n`;
const gosum = (modules) =>
    modules
        .map(
            ([name, version]) =>
                `${name} ${version} h1:x=\n${name} ${version}/go.mod h1:y=\n`,
        )
        .join("");
const pins = (entries) =>
    JSON.stringify({
        pins: entries.map(([identity, version]) => ({
            identity,
            location: `https://github.com/x/${identity}.git`,
            state: { version },
        })),
    });
const podfile = ({ pods, repos = {}, external = {} }) =>
    `PODS:\n${pods.map((spec) => `  - ${spec}\n`).join("")}\nSPEC REPOS:\n${Object.entries(
        repos,
    )
        .map(
            ([repo, names]) =>
                `  ${repo}:\n${names.map((name) => `    - ${name}\n`).join("")}`,
        )
        .join("")}\nEXTERNAL SOURCES:\n${Object.entries(external)
        .map(
            ([name, props]) =>
                `  ${name}:\n${Object.entries(props)
                    .map(([key, value]) => `    :${key}: ${value}\n`)
                    .join("")}`,
        )
        .join("")}\nCOCOAPODS: 1.17.0\n`;
const uv = (entries) =>
    entries
        .map(
            ([
                name,
                version,
                source = '{ registry = "https://pypi.org/simple" }',
            ]) =>
                `[[package]]\nname = "${name}"\nversion = "${version}"\nsource = ${source}\n`,
        )
        .join("\n");

test("binary added", (t) => {
    const output = scan(t, {}, { "a.bin": Buffer.alloc(16) });
    assert.equal(
        output,
        "1 binary file\n\n## Binary files\n\n- `a.bin` (16 bytes)\n\n",
    );
});

test("binary modified", (t) => {
    const output = scan(
        t,
        { "a.bin": Buffer.alloc(16) },
        { "a.bin": Buffer.alloc(32) },
    );
    assert.match(output, /^1 binary file\n/);
    assert.match(output, /`a.bin` \(32 bytes\)/);
});

test("binary deleted is ignored", (t) => {
    assert.equal(scan(t, { "a.bin": Buffer.alloc(16) }, { "a.bin": null }), "");
});

test("CI preserves tabs and newlines in binary and large filenames", (t) => {
    const binary = "image.png\tpayload.jar";
    const large = "large\nfile.txt";
    const size = 1024 * 1024 + 1;
    const { output, summary } = scan(
        t,
        {},
        { [binary]: Buffer.alloc(16), [large]: "a".repeat(size) },
        { ci: true },
    );
    assert.equal(output, 'categories=["binary files","large files"]\n');
    assert.equal(
        summary,
        `1 binary file, 1 large file\n\n## Binary files\n\n- \`${binary}\` (16 bytes)\n\n## Large files\n\n- \`${large}\` (${size} bytes)\n`,
    );
});

test("routine image, font, and xcassets binaries are ignored", (t) => {
    const output = scan(
        t,
        {},
        {
            "src/logo.PNG": Buffer.alloc(16),
            "web/fonts/a.woff2": Buffer.alloc(16),
            "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents":
                Buffer.alloc(16),
        },
    );
    assert.equal(output, "");
});

test("large files added, binary or text, not grown", (t) => {
    const size = 1024 * 1024 + 1;
    const output = scan(
        t,
        { "big.txt": "a" },
        {
            "big.txt": "a".repeat(size),
            "big.bin": Buffer.alloc(size),
            "new.txt": "b".repeat(size),
        },
    );
    assert.equal(
        output,
        `1 binary file, 2 large files\n\n## Binary files\n\n- \`big.bin\` (${size} bytes)\n\n## Large files\n\n- \`big.bin\` (${size} bytes)\n- \`new.txt\` (${size} bytes)\n\n`,
    );
});

test("Cargo.lock new package, not version bump", (t) => {
    const output = scan(
        t,
        {
            "rust/Cargo.lock": cargo([
                ["a", "1.0.0"],
                ["b", "1.0.0"],
            ]),
        },
        {
            "rust/Cargo.lock": cargo([
                ["a", "1.1.0"],
                ["b", "1.0.0"],
                ["c", "2.0.0"],
            ]),
        },
    );
    assert.equal(
        output,
        "1 new dependency\n\n## New dependencies\n\n`rust/Cargo.lock`\n\n- c 2.0.0\n\n",
    );
});

test("workspace-local packages are not dependencies", (t) => {
    const output = scan(
        t,
        {
            "Cargo.lock": cargo([["a", "1.0.0"]]),
            "pubspec.lock": pub([["a", "1.0.0"]]),
            "package-lock.json": npm({}),
        },
        {
            "Cargo.lock": cargo([
                ["a", "1.0.0"],
                ["member", "0.0.0", ""],
            ]),
            "pubspec.lock": pub([
                ["a", "1.0.0"],
                ["local", "0.0.1", "path"],
            ]),
            "package-lock.json": npm({
                "node_modules/w": { resolved: "apps/w", link: true },
            }),
        },
    );
    assert.equal(output, "");
});

test("dependency source change, even beside the original version", (t) => {
    const fork = "git+https://github.com/x/a";
    const output = scan(
        t,
        {
            "package-lock.json": npm({
                "node_modules/y": tarball("y", "1.0.0"),
            }),
            "rust/Cargo.lock": cargo([["a", "1.0.0"]]),
        },
        {
            "package-lock.json": npm({
                "node_modules/y": tarball("y", "1.0.0", "npm.example.com"),
            }),
            "rust/Cargo.lock": cargo([
                ["a", "1.0.0"],
                ["a", "1.1.0", fork],
            ]),
        },
    );
    assert.equal(
        output,
        `2 dependency source changes\n\n## New dependencies\n\n\`package-lock.json\`\n\n- y: https://registry.npmjs.org/y -> https://npm.example.com/y\n\n\`rust/Cargo.lock\`\n\n- a: ${registry} -> ${fork}\n\n`,
    );
});

test("git rev bump keeps the source, repository change does not", (t) => {
    const at = (repo, rev) => `git+${repo}?rev=${rev}#${rev}`;
    const output = scan(
        t,
        {
            "rust/Cargo.lock": cargo([
                [
                    "h",
                    "0.2.0",
                    at("https://github.com/ente/heic-decoder.git", "aaa"),
                ],
                ["r", "1.0.0", at("https://github.com/a/r.git", "x")],
            ]),
            "uv.lock": uv([
                ["u", "1.0.0", '{ git = "https://github.com/x/u?rev=1#1" }'],
            ]),
        },
        {
            "rust/Cargo.lock": cargo([
                [
                    "h",
                    "0.2.0",
                    at("https://github.com/ente/heic-decoder.git", "bbb"),
                ],
                ["r", "1.0.0", at("https://github.com/b/r.git", "x")],
            ]),
            "uv.lock": uv([
                ["u", "1.0.0", '{ git = "https://github.com/x/u?rev=2#2" }'],
            ]),
        },
    );
    assert.equal(
        output,
        "1 dependency source change\n\n## New dependencies\n\n`rust/Cargo.lock`\n\n- r: git+https://github.com/a/r.git -> git+https://github.com/b/r.git\n\n",
    );
});

test("package-lock.json new nested package", (t) => {
    const output = scan(
        t,
        {
            "package-lock.json": npm({
                "node_modules/x": tarball("x", "1.0.0"),
            }),
        },
        {
            "package-lock.json": npm({
                "node_modules/x": tarball("x", "1.0.1"),
                "node_modules/x/node_modules/@s/y": tarball("y", "2.0.0"),
            }),
        },
    );
    assert.match(output, /^1 new dependency\n/);
    assert.match(output, /- @s\/y 2\.0\.0\n/);
});

test("pubspec.lock new package", (t) => {
    const output = scan(
        t,
        { "pubspec.lock": pub([["a", "1.0.0"]]) },
        {
            "pubspec.lock": pub([
                ["a", "1.0.0"],
                ["b", "3.1.4"],
            ]),
        },
    );
    assert.match(output, /^1 new dependency\n/);
    assert.match(output, /- b 3\.1\.4\n/);
});

test("Package.resolved, Podfile.lock, and uv.lock new packages", (t) => {
    const output = scan(
        t,
        {
            "Package.resolved": pins([["a", "1.0.0"]]),
            "Podfile.lock": podfile({
                pods: ["A/Core (1.0.0)"],
                repos: { trunk: ["A"] },
            }),
            "uv.lock": uv([["a", "1.0.0"]]),
        },
        {
            "Package.resolved": pins([
                ["a", "1.0.0"],
                ["b", "2.0.0"],
            ]),
            "Podfile.lock": podfile({
                pods: [
                    "A/Core (1.0.0)",
                    "A/Extra (1.0.0)",
                    '"B/Sub+x (3.0.0)"',
                ],
                repos: { trunk: ["A", "B"] },
            }),
            "uv.lock": uv([
                ["a", "1.0.0"],
                ["c", "4.0.0"],
                ["me", "0.0.0", '{ virtual = "." }'],
            ]),
        },
    );
    assert.equal(
        output,
        "3 new dependencies\n\n## New dependencies\n\n`Package.resolved`\n\n- b 2.0.0\n\n`Podfile.lock`\n\n- B 3.0.0\n\n`uv.lock`\n\n- c 4.0.0\n\n",
    );
});

test("Podfile.lock pod moving from a spec repo to git is a source change", (t) => {
    const output = scan(
        t,
        {
            "ios/Podfile.lock": podfile({
                pods: ["Sentry (8.0.0)"],
                repos: { trunk: ["Sentry"] },
            }),
        },
        {
            "ios/Podfile.lock": podfile({
                pods: ["Sentry (8.0.0)"],
                external: {
                    Sentry: {
                        branch: "main",
                        git: "https://github.com/x/sentry-cocoa.git",
                    },
                },
            }),
        },
    );
    assert.equal(
        output,
        "1 dependency source change\n\n## New dependencies\n\n`ios/Podfile.lock`\n\n- Sentry: trunk -> https://github.com/x/sentry-cocoa.git\n\n",
    );
});

test("local path packages are not dependencies until they leave the tree", (t) => {
    const output = scan(
        t,
        {
            "ios/Podfile.lock": podfile({
                pods: ["A (1.0.0)"],
                repos: { trunk: ["A"] },
            }),
            "uv.lock": uv([["b", "1.0.0", '{ directory = "../b" }']]),
        },
        {
            "ios/Podfile.lock": podfile({
                pods: ["A (1.0.0)", "Local (1.0.0)"],
                repos: { trunk: ["A"] },
                external: { Local: { path: '"../Local"' } },
            }),
            "uv.lock": uv([
                ["b", "1.0.0"],
                ["c", "2.0.0", '{ directory = "../c" }'],
                ["d", "3.0.0", '{ editable = "." }'],
            ]),
        },
    );
    assert.equal(
        output,
        '1 dependency source change\n\n## New dependencies\n\n`uv.lock`\n\n- b: { directory = "../b" } -> { registry = "https://pypi.org/simple" }\n\n',
    );
});

test("npm alias of a present package is not new", (t) => {
    const output = scan(
        t,
        {
            "package-lock.json": npm({
                "node_modules/react": tarball("react", "18.3.1"),
            }),
        },
        {
            "package-lock.json": npm({
                "node_modules/react": tarball("react", "18.3.1"),
                "node_modules/react-alias": {
                    name: "react",
                    ...tarball("react", "18.3.1"),
                },
            }),
        },
    );
    assert.equal(output, "");
});

test("bundled npm entry without resolved is new by name only", (t) => {
    const output = scan(
        t,
        {
            "package-lock.json": npm({
                "node_modules/x": tarball("x", "1.0.0"),
            }),
        },
        {
            "package-lock.json": npm({
                "node_modules/x": tarball("x", "1.0.1"),
                "node_modules/x/node_modules/y": {
                    version: "1.0.0",
                    inBundle: true,
                },
            }),
        },
    );
    assert.equal(
        output,
        "1 new dependency\n\n## New dependencies\n\n`package-lock.json`\n\n- y 1.0.0\n\n",
    );
});

test("npm file: entry is local until it moves to the registry", (t) => {
    const output = scan(
        t,
        {
            "package-lock.json": npm({
                "node_modules/x": {
                    version: "1.0.0",
                    resolved: "file:vendor/x-1.0.0.tgz",
                },
            }),
        },
        {
            "package-lock.json": npm({
                "node_modules/x": tarball("x", "1.0.0"),
                "node_modules/z": {
                    version: "2.0.0",
                    resolved: "file:vendor/z-2.0.0.tgz",
                },
            }),
        },
    );
    assert.equal(
        output,
        "1 dependency source change\n\n## New dependencies\n\n`package-lock.json`\n\n- x: file:vendor/x-1.0.0.tgz -> https://registry.npmjs.org/x\n\n",
    );
});

test("go.sum new module", (t) => {
    const output = scan(
        t,
        { "go.sum": gosum([["a.com/x", "v1.0.0"]]) },
        {
            "go.sum": gosum([
                ["a.com/x", "v1.2.0"],
                ["b.org/y/v2", "v2.0.1"],
            ]),
        },
    );
    assert.match(output, /^1 new dependency\n/);
    assert.match(output, /- b\.org\/y\/v2 v2\.0\.1\n/);
});

test("existing guardrails modified or deleted", (t) => {
    const output = scan(
        t,
        {
            ".github/scripts/x.mjs": "",
            ".github/workflows/x.yml": "on: push\n",
            "mobile/checks/x/check.rb": "",
            "rust/checks/x/check.py": "",
            "web/apps/x/eslint.config.mjs": "",
            "web/checks/x/check.mjs": "",
        },
        {
            ".github/scripts/x.mjs": "export {};\n",
            ".github/workflows/x.yml": "on: pull_request\n",
            "mobile/checks/x/check.rb": "\n",
            "rust/checks/x/check.py": "\n",
            "web/apps/x/eslint.config.mjs": null,
            "web/checks/x/check.mjs": "\n",
            "web/checks/new.mjs": "",
        },
    );
    assert.equal(
        output,
        "6 guardrail files\n\n## Guardrail changes\n\n- `.github/scripts/x.mjs`\n- `.github/workflows/x.yml`\n- `mobile/checks/x/check.rb`\n- `rust/checks/x/check.py`\n- `web/apps/x/eslint.config.mjs`\n- `web/checks/x/check.mjs`\n\n",
    );
});

test("new GitHub workflows, actions and policies need approval", (t) => {
    const files = {
        ".github/workflows/new.yml": "on: push\n",
        ".github/actions/new/action.yml": "name: new\n",
        ".github/checks/new/check.mjs": "export {};\n",
    };
    const { output, summary } = scan(t, {}, files, { ci: true });
    assert.equal(output, 'categories=["guardrail files"]\n');
    assert.match(summary, /3 guardrail files/);
    for (const file of Object.keys(files))
        assert.ok(summary.includes(`\`${file}\``));
    assert.match(scan(t, {}, files, { commit: false }), /^3 guardrail files\n/);
});

test("toolchain and registry config added, modified, or deleted", (t) => {
    const output = scan(
        t,
        { "web/.npmrc": "", "rust/.cargo/config.toml": "" },
        {
            "web/.npmrc": "registry=https://example.com\n",
            "rust/.cargo/config.toml": null,
            ".nvmrc": "24\n",
        },
    );
    assert.equal(
        output,
        "3 config files\n\n## Toolchain and registry config\n\n- `.nvmrc`\n- `rust/.cargo/config.toml`\n- `web/.npmrc`\n\n",
    );
});

test("new root .cargo/config.toml is a config file, even untracked", (t) => {
    const expected =
        "1 config file\n\n## Toolchain and registry config\n\n- `.cargo/config.toml`\n\n";
    assert.equal(
        scan(t, { "a.txt": "a\n" }, { ".cargo/config.toml": "[registries]\n" }),
        expected,
    );
    assert.equal(
        scan(
            t,
            { "a.txt": "a\n" },
            { ".cargo/config.toml": "[registries]\n" },
            { commit: false },
        ),
        expected,
    );
});

test("Git attributes require config approval even when they hide binary changes", (t) => {
    const { output, summary } = scan(
        t,
        {
            "modified/.gitattributes": "",
            "deleted/.gitattributes": "",
            "a.jar": Buffer.alloc(16),
        },
        {
            ".gitattributes": "*.jar diff\n",
            "added/.gitattributes": "*.jar diff\n",
            "modified/.gitattributes": "*.jar diff\n",
            "deleted/.gitattributes": null,
            "a.jar": Buffer.alloc(32),
        },
        { ci: true },
    );
    assert.equal(output, 'categories=["config files"]\n');
    assert.equal(
        summary,
        "4 config files\n\n## Toolchain and registry config\n\n- `.gitattributes`\n- `added/.gitattributes`\n- `deleted/.gitattributes`\n- `modified/.gitattributes`\n",
    );
});

test("uncommitted and untracked changes are scanned locally", (t) => {
    const output = scan(
        t,
        { "a.bin": Buffer.alloc(16) },
        {
            "a.bin": Buffer.alloc(32),
            "rust/Cargo.lock": cargo([["a", "1.0.0"]]),
        },
        { commit: false },
    );
    assert.equal(
        output,
        "1 binary file, 1 new dependency\n\n## Binary files\n\n- `a.bin` (32 bytes)\n\n## New dependencies\n\n`rust/Cargo.lock`\n\n- a 1.0.0\n\n",
    );
});

test("CI mode writes categories and the step summary, and tolerates gitlinks", (t) => {
    const { stdout, output, summary } = scan(
        t,
        { "a.txt": "a\n" },
        { "a.bin": Buffer.alloc(16) },
        { gitlink: "sub", ci: true },
    );
    assert.equal(
        stdout,
        "::warning title=Change approval needed::1 binary file\n",
    );
    assert.equal(output, 'categories=["binary files"]\n');
    assert.equal(
        summary,
        "1 binary file\n\n## Binary files\n\n- `a.bin` (16 bytes)\n",
    );
});

test("untracked dangling symlink is skipped locally", (t) => {
    const output = scan(
        t,
        { "a.txt": "a\n" },
        { "a.bin": Buffer.alloc(16) },
        { commit: false, symlink: "link" },
    );
    assert.equal(
        output,
        "1 binary file\n\n## Binary files\n\n- `a.bin` (16 bytes)\n\n",
    );
});

test("CI mode with nothing flagged", (t) => {
    const { stdout, output, summary } = scan(
        t,
        { "a.txt": "a\n" },
        { "a.txt": "b\n" },
        { ci: true },
    );
    assert.equal(stdout, "");
    assert.equal(output, "categories=[]\n");
    assert.equal(summary, "No approval needed.\n");
});

test("ordinary change is silent", (t) => {
    assert.equal(
        scan(
            t,
            { "src/a.txt": "a\n" },
            { "src/a.txt": "b\n", "src/b.txt": "c\n" },
        ),
        "",
    );
});

test("Cargo lint changes need approval across TOML layouts", (t) => {
    for (const [before, after] of [
        ["", '[workspace.lints.rust]\nunsafe_code = "deny"\n'],
        [
            '[workspace.lints.rust]\nunsafe_code = "deny"\n',
            '[workspace.lints.rust]\nunsafe_code = "warn"\n',
        ],
        ['[workspace.lints.rust]\nunsafe_code = "deny"\n', ""],
        [
            "[lints]\nworkspace = true\n",
            '[lints.rust]\nunsafe_code = "allow"\n',
        ],
        ["", 'workspace.lints = { rust = { unsafe_code = "allow" } }\n'],
        [
            '[workspace]\nmembers = ["a", "b"]\n',
            '[workspace]\nmembers = ["a", "b"]\ndefault-members = ["a"]\n',
        ],
        [
            '[workspace]\nmembers = ["a", "b"]\n',
            '[workspace]\nmembers = ["a"]\nexclude = ["b"]\n',
        ],
    ]) {
        const { output, summary } = scan(
            t,
            { "rust/Cargo.toml": before },
            { "rust/Cargo.toml": after },
            { ci: true },
        );
        assert.equal(output, 'categories=["Rust lint policy files"]\n');
        assert.match(
            summary,
            /## Rust lint declarations and files containing unsafe\n\n- `rust\/Cargo.toml`/,
        );
    }
});

test("Cargo dependency edits and equivalent lint layouts need no lint approval", (t) => {
    assert.equal(
        scan(
            t,
            {
                "rust/Cargo.toml":
                    '[workspace.lints.rust]\nunsafe_code = "deny"\ndead_code = "warn"\n[workspace.dependencies]\nserde = "1"\n',
            },
            {
                "rust/Cargo.toml":
                    'workspace.lints.rust = { dead_code = "warn", unsafe_code = "deny" }\n[workspace.dependencies]\nserde = "2"\n',
            },
        ),
        "",
    );
});

test("reordering Cargo workspace selection lists needs no approval", (t) => {
    for (const key of ["members", "exclude", "default-members"]) {
        assert.equal(
            scan(
                t,
                { "rust/Cargo.toml": `[workspace]\n${key} = ["a", "b"]\n` },
                { "rust/Cargo.toml": `[workspace]\n${key} = ["b", "a"]\n` },
            ),
            "",
        );
    }
});

test("Rust lint changes need approval except for removed suppressions", (t) => {
    const expect = '#[expect(dead_code, reason = "Shared helper")]';
    const body = "fn helper() {}";
    for (const [before, after, approval = true] of [
        [body, `${expect}\n${body}`],
        [`${expect}\n${body}`, body, false],
        [`${expect}\n${body}`, null, false],
        [`#[allow(dead_code)]\n${body}`, body, false],
        [
            `${expect}\n${body}`,
            `${expect.replace("Shared helper", "New reason")}\n${body}`,
        ],
        [
            `${expect}\n${body}`,
            `${expect.replace("dead_code", "unused_variables")}\n${body}`,
        ],
        [`#[cfg(unix)]\n${expect}\n${body}`, `${expect}\n${body}`],
        [
            `#[cfg_attr(unix, expect(dead_code))]\n${body}`,
            `#[cfg_attr(test, expect(dead_code))]\n${body}`,
        ],
        [
            `#[cfg_attr(unix, cfg_attr(test, expect(dead_code)))]\n${body}`,
            body,
            false,
        ],
        [
            `#[path = "a.rs"]\n${expect}\nmod support;`,
            `#[path = "b.rs"]\n${expect}\nmod support;`,
        ],
        [
            body,
            `#![allow(clippy::allow_attributes, clippy::allow_attributes_without_reason, dead_code)]\n${body}`,
        ],
        [body, `#[allow(dead_code, reason = "Shared helper")]\n${body}`],
        [`#[deny(dead_code)]\nmod guarded {}`, "mod guarded {}"],
        [`#[cfg_attr(unix, warn(dead_code))]\n${body}`, body],
        [`#![forbid(unsafe_code)]\n${body}`, body],
        [
            `${expect} ${body}`,
            `${expect} ${body} mod other { ${expect} ${body} }`,
        ],
        [body, `#[r#expect(dead_code, reason = "Shared helper")]\n${body}`],
        [
            `${expect}\nmod support {}`,
            `${expect.replace("#[", "#![")}\nmod support {}`,
        ],
        [
            `${expect}\n${body}\nfn other() {}`,
            `${body}\n${expect}\nfn other() {}`,
        ],
    ]) {
        const output = scan(
            t,
            { "src/lib.rs": before },
            { "src/lib.rs": after },
        );
        if (approval)
            assert.match(
                output,
                /^1 Rust lint policy file\n[\s\S]*(?:Added|Removed) or changed: #!?\[/,
            );
        else assert.equal(output, "");
    }
});

test("ordinary code under existing lint declarations needs no approval", (t) => {
    for (const before of [
        '#[expect(dead_code, reason = "Shared helper")] fn helper() { first(); }',
        '#![expect(dead_code, reason = "Shared helpers")] fn helper() { first(); }',
        "#![forbid(unsafe_code)] fn helper() { first(); }",
        'fn helper() { #[expect(unused_variables, reason = "Temporary binding")] let value = first(); }',
        '#[expect(clippy::expect_used, reason = "Valid catalog")] Asset::file(AssetFile { url: first() }).expect("valid")',
    ]) {
        assert.equal(
            scan(
                t,
                { "src/lib.rs": before },
                { "src/lib.rs": before.replace("first()", "second()") },
            ),
            "",
        );
    }
});

test("any edit in a file containing unsafe needs approval", (t) => {
    for (const before of [
        "fn call() { #[expect(unsafe_code)] if ready() {} else { unsafe { first(); } } }",
        "unsafe impl Send for Context {}\nfn unrelated() { first(); }",
        "unsafe fn ffi() {}\n// first",
    ]) {
        assert.match(
            scan(
                t,
                { "src/lib.rs": before },
                { "src/lib.rs": before.replace("first", "second") },
            ),
            /^1 Rust lint policy file\n/,
        );
    }
});

test("unsafe in either revision needs approval, including new and deleted files", (t) => {
    const source = "fn call() { unsafe { ffi(); } }";
    for (const [before, after] of [
        ["fn call() {}", source],
        [source, "fn call() {}"],
        [source, null],
    ]) {
        assert.match(
            scan(t, { "src/lib.rs": before }, { "src/lib.rs": after }),
            /^1 Rust lint policy file\n/,
        );
    }
    assert.match(
        scan(t, {}, { "src/lib.rs": source }, { commit: false }),
        /^1 Rust lint policy file\n/,
    );
});

test("external module edits need approval only when the edited file contains unsafe", (t) => {
    for (const [before, needsApproval] of [
        ["pub fn call() { unsafe {\n    first();\n} }", true],
        ["fn helper() { first(); }", false],
    ]) {
        const { output } = scan(
            t,
            {
                "src/lib.rs":
                    '#[expect(dead_code, unsafe_code, reason = "Shared helpers")] #[path = "support/mod.rs"] mod support;',
                "src/support/mod.rs": "mod nested;",
                "src/support/nested.rs": before,
            },
            { "src/support/nested.rs": before.replace("first()", "second()") },
            { ci: true },
        );
        assert.equal(
            output,
            needsApproval
                ? 'categories=["Rust lint policy files"]\n'
                : "categories=[]\n",
        );
    }
});

test("Rust comments, literals and raw identifiers do not count as unsafe or declarations", (t) => {
    const before = String.raw`
// unsafe { #[allow(dead_code)]
/* nested /* unsafe #[allow(dead_code)] */ comment */
const EXAMPLE: &str = r##"unsafe #[expect(dead_code)]"##;
fn example() {
    let r#unsafe = "unsafe #[allow(dead_code)]";
    let _ = (b"unsafe", c"unsafe", br"unsafe", cr#"unsafe"#, ']');
}
#[expect(dead_code, reason = "brackets: ] [ escaped: \")]")]
fn helper() {}
`;
    const after = before
        .replaceAll("unsafe", "example")
        .replace(
            "expect(dead_code, reason",
            "expect(\n dead_code, /* comment */\n reason",
        )
        .replace("fn helper() {}", "fn helper() { let c = '['; }");
    assert.equal(
        scan(t, { "src/lib.rs": before }, { "src/lib.rs": after }),
        "",
    );
});

test("ESLint directives in added lines need approval", (t) => {
    const body = "first();\n";
    for (const directive of [
        "// eslint-disable-next-line no-console\n",
        "/* eslint-disable no-console */\n",
        '/* eslint "no-console": "off" */\n',
        'const example = "eslint-disable-next-line no-console";\n',
    ])
        assert.match(
            scan(
                t,
                { "web/example.ts": body },
                { "web/example.ts": directive + body },
            ),
            /^1 Web lint policy file\n/,
        );
    assert.match(
        scan(
            t,
            {
                "web/example.ts":
                    "// eslint-disable-next-line no-console\n" + body,
            },
            {
                "web/example.ts":
                    "// eslint-disable-next-line no-alert\n" + body,
            },
        ),
        /^1 Web lint policy file\n/,
    );
});

test("unchanged and removed ESLint directives need no approval", (t) => {
    const before = "// eslint-disable-next-line no-console\nfirst();\n";
    for (const after of [before.replace("first", "second"), "first();\n", null])
        assert.equal(
            scan(t, { "web/example.ts": before }, { "web/example.ts": after }),
            "",
        );
});

test("new Web directives are checked in uncommitted and untracked files", (t) => {
    const source = "// eslint-disable-next-line no-console\nfirst();\n";
    for (const base of [{}, { "web/example.ts": "first();\n" }])
        assert.match(
            scan(t, base, { "web/example.ts": source }, { commit: false }),
            /^1 Web lint policy file\n/,
        );
});

test("checks started in a subdirectory inspect repository-wide changes", (t) => {
    const summary =
        "1 binary file, 1 new dependency\n\n## Binary files\n\n- `new.bin` (16 bytes)\n\n## New dependencies\n\n`rust/Cargo.lock`\n\n- b 2.0.0\n";
    for (const ci of [false, true]) {
        const result = scan(
            t,
            {
                "nested/a.txt": "a\n",
                "rust/Cargo.lock": cargo([["a", "1.0.0"]]),
            },
            {
                "new.bin": Buffer.alloc(16),
                "rust/Cargo.lock": cargo([
                    ["a", "1.0.0"],
                    ["b", "2.0.0"],
                ]),
            },
            { ci, commit: ci, directory: "nested" },
        );
        if (ci) {
            assert.deepEqual(result, {
                stdout: "::warning title=Change approval needed::1 binary file, 1 new dependency\n",
                output: 'categories=["binary files","new dependencies"]\n',
                summary,
            });
        } else {
            assert.equal(result, `${summary}\n`);
        }
    }
});

test("workflow scans PR changes with the complete checker from main", (t) => {
    const checkerDir = ".github/checks/change-approval";
    const { output, summary } = scan(
        t,
        {
            "rust/Cargo.toml": '[lints.rust]\nunsafe_code = "deny"\n',
            [`${checkerDir}/rust.mjs`]:
                'export { checkRust } from "./additional-rule.mjs";',
            [`${checkerDir}/additional-rule.mjs`]: readFileSync(
                join(import.meta.dirname, "rust.mjs"),
                "utf8",
            ),
        },
        {
            "rust/Cargo.toml": '[lints.rust]\nunsafe_code = "allow"\n',
            "tomllib.py": "def loads(source):\n    return {}\n",
            [`${checkerDir}/additional-rule.mjs`]:
                "export function checkRust() { return []; }",
            [`${checkerDir}/web.mjs`]:
                'throw new Error("loaded an untrusted rule");',
            "src/lib.rs": "pub unsafe fn call() {}",
            "web/example.ts":
                "// eslint-disable-next-line no-console\nfirst();\n",
        },
        { ci: true, workflow: true },
    );
    assert.equal(
        output,
        'categories=["guardrail files","Rust lint policy files","Web lint policy files"]\n',
    );
    assert.match(summary, /- `src\/lib.rs`/);
    assert.match(summary, /- `web\/example.ts`/);
    assert.match(summary, /- `rust\/Cargo.toml`/);
});
