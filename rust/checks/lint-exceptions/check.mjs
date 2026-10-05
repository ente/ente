import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { relative, resolve, sep } from "node:path";

const root = resolve(process.argv[2]);
const listPath = "rust/checks/lint-exceptions/suppressions.json";
const allowed = JSON.parse(readFileSync(resolve(root, listPath), "utf8"));
const unused = new Map(
    Object.entries(allowed).map(([path, rules]) => [path, new Set(rules)]),
);

for (const path of files()) {
    const source = readFileSync(resolve(root, path), "utf8");
    for (const attribute of attributes(source)) {
        for (const lint of suppressedLints(attribute.tokens)) {
            unused.get(path)?.delete(lint);
            if (!allowed[path]?.includes(lint)) {
                const line = source
                    .slice(0, attribute.start)
                    .split("\n").length;
                console.error(
                    `${path}:${line}: ${lint} is not listed in ${listPath}`,
                );
                process.exitCode = 1;
            }
        }
        if (!attribute.tokens.some((token) => /^(?:r#)?expect$/.test(token)))
            continue;
        const lints = expectedLints(attribute.text);
        if (attribute.inner) {
            if (
                path !== "rust/crates/vecdb/examples/vecdb_bench.rs" ||
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

for (const [path, rules] of unused) {
    for (const rule of rules) {
        console.error(
            `${path}: ${rule} has no suppression; remove it from ${listPath}`,
        );
        process.exitCode = 1;
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
    const tokens = tokenize(source);
    for (let i = 0; i < tokens.length; i++) {
        if (tokens[i].text !== "#") continue;
        const inner = tokens[i + 1]?.text === "!";
        const open = i + (inner ? 2 : 1);
        if (tokens[open]?.text !== "[") continue;
        let end = open + 1;
        for (let depth = 1; end < tokens.length; end++) {
            if (tokens[end].text === "[") depth++;
            if (tokens[end].text === "]" && --depth === 0) break;
        }
        const start = tokens[i].start;
        const offset = tokens[end].start + 1;
        yield {
            inner,
            start,
            end: offset,
            text: source.slice(start, offset),
            tokens: tokens.slice(i, end + 1).map(({ text }) => text),
        };
        i = end;
    }
}

function* suppressedLints(tokens) {
    for (let i = 0; i < tokens.length; i++) {
        if (
            !/^(?:r#)?(?:allow|expect)$/.test(tokens[i]) ||
            tokens[i + 1] !== "("
        )
            continue;
        let lint = "";
        for (let j = i + 2; j < tokens.length; j++) {
            const token = tokens[j];
            if ([",", ")", "reason"].includes(token)) {
                if (lint) yield lint;
                lint = "";
                if (token !== ",") break;
            } else {
                lint += token.replace(/^r#/, "");
            }
        }
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

function tokenize(source) {
    const lexer =
        /\/\/[^\n]*|\/\*|[bc]?r(#+)?"[\s\S]*?"\1|[bc]?"(?:\\[\s\S]|[^"\\])*"|b?'(?:\\(?:u\{[\da-fA-F_]+\}|x[\da-fA-F]{2}|[\s\S])|[^'\\\r\n])'|(?:r#)?[a-zA-Z_]\w*|[^\s]/gu;
    const tokens = [];
    let match;
    while ((match = lexer.exec(source))) {
        const text = match[0];
        if (text.startsWith("//")) continue;
        if (text === "/*") {
            const comments = /\/\*|\*\//g;
            comments.lastIndex = lexer.lastIndex;
            for (let depth = 1; depth; ) {
                const comment = comments.exec(source);
                if (!comment) throw new Error("Unclosed Rust comment");
                depth += comment[0] === "/*" ? 1 : -1;
            }
            lexer.lastIndex = comments.lastIndex;
        } else {
            tokens.push({ text, start: match.index });
        }
    }
    return tokens;
}
