import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";

const root = resolve(process.argv[2]);

for (const path of files()) {
    const source = readFileSync(resolve(root, path), "utf8");
    for (const attribute of attributes(source)) {
        if (!/\bexpect\s*\(/.test(attribute.text)) continue;
        const lints = expectedLints(attribute.text);
        if (attribute.inner) {
            if (
                path !== "rust/crates/ml/examples/vecdb_bench.rs" ||
                lints?.length !== 1 ||
                lints[0] !== "clippy::expect_used"
            ) {
                reject(path, source, attribute.start);
            }
            continue;
        }
        const module = followingModule(source, attribute.end);
        if (!module) continue;
        if (module === "frb_generated") continue;
        if (lints?.length === 1 && lints[0] === "dead_code") continue;
        reject(path, source, attribute.start);
    }
}

function expectedLints(attribute) {
    const match = attribute.match(/^#!?\[\s*expect\s*\(([\s\S]*)\)\s*\]$/);
    if (!match) return undefined;
    const reason = match[1].match(/\breason\s*=\s*"(?:\\.|[^"\\])+"\s*,?\s*$/);
    if (!reason) return undefined;
    const lints = match[1]
        .slice(0, reason.index)
        .split(",")
        .map((lint) => lint.trim())
        .filter(Boolean);
    return lints.every((lint) => /^[A-Za-z_][A-Za-z0-9_:]*$/.test(lint))
        ? lints
        : undefined;
}

function files() {
    return execFileSync(
        "git",
        [
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            "rust",
        ],
        { cwd: root, encoding: "utf8" },
    )
        .split("\0")
        .filter(
            (path) => path.endsWith(".rs") && existsSync(resolve(root, path)),
        )
        .map((path) =>
            relative(root, resolve(root, path)).split(sep).join("/"),
        );
}

function* attributes(source) {
    const pattern = /^[ \t]*#(!?)\[/gm;
    for (const match of source.matchAll(pattern)) {
        const start = match.index + match[0].indexOf("#");
        const end = attributeEnd(source, start);
        if (end === undefined) continue;
        yield {
            end,
            inner: match[1] === "!",
            start,
            text: source.slice(start, end),
        };
    }
}

function attributeEnd(source, start) {
    let quoted = false;
    let escaped = false;
    for (let i = source.indexOf("[", start) + 1; i < source.length; i++) {
        const character = source[i];
        if (quoted) {
            if (escaped) escaped = false;
            else if (character === "\\") escaped = true;
            else if (character === '"') quoted = false;
        } else if (character === '"') {
            quoted = true;
        } else if (character === "]") {
            return i + 1;
        }
    }
}

function followingModule(source, offset) {
    let position = skipTrivia(source, offset);
    while (source.startsWith("#[", position)) {
        const end = attributeEnd(source, position);
        if (end === undefined) return undefined;
        position = skipTrivia(source, end);
    }
    return source
        .slice(position)
        .match(
            /^(?:pub(?:\s*\([^)]*\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)\b/,
        )?.[1];
}

function skipTrivia(source, offset) {
    let position = offset;
    while (true) {
        const whitespace = source.slice(position).match(/^\s+/)?.[0];
        if (whitespace) {
            position += whitespace.length;
            continue;
        }
        const comment = source
            .slice(position)
            .match(/^\/\/[^\n]*(?:\n|$)/)?.[0];
        if (!comment) return position;
        position += comment.length;
    }
}

function reject(path, source, start) {
    const line = source.slice(0, start).split("\n").length;
    console.error(`${path}:${line}: unapproved crate or module lint exception`);
    process.exitCode = 1;
}
