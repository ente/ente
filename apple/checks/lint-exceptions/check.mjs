import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const listPath = "apple/checks/lint-exceptions/suppressions.json";

export function parse(sources) {
    const swift = execFileSync("xcrun", ["--find", "swift"], {
        encoding: "utf8",
    }).trim();
    const libraries = resolve(dirname(swift), "../lib/swift/host");
    return JSON.parse(
        execFileSync(
            swift,
            [
                "-module-cache-path",
                resolve(import.meta.dirname, "../../.build/lint-exceptions"),
                "-I",
                libraries,
                "-L",
                libraries,
                resolve(import.meta.dirname, "parse.swift"),
            ],
            { input: JSON.stringify(sources), encoding: "utf8" },
        ),
    );
}

export function check(comments, allowed) {
    const unused = new Map(
        Object.entries(allowed).map(([path, rules]) => [path, new Set(rules)]),
    );
    const errors = [];
    for (const { path, text, line: startLine } of comments) {
        const directives =
            /\bswiftlint\s*:\s*disable(?::(?:next|previous|this))?\b([^\r\n]*)|\bswift-format-ignore(-file)?\b([^\r\n]*)/g;
        for (const match of text.matchAll(directives)) {
            const line =
                startLine + text.slice(0, match.index).split("\n").length - 1;
            const value = (match[1] ?? match[3]).split(/\/\/|\*\//)[0].trim();
            const rules = value
                .replace(/^:\s*/, "")
                .split(/[\s,]+/)
                .filter(Boolean);
            if (match[2] || !rules.length || rules.includes("all")) {
                errors.push(`${path}:${line}: Name the rules being suppressed`);
                continue;
            }
            for (const rule of rules) {
                unused.get(path)?.delete(rule);
                if (!allowed[path]?.includes(rule)) {
                    errors.push(
                        `${path}:${line}: ${rule} is not listed in ${listPath}`,
                    );
                }
            }
        }
    }
    for (const [path, rules] of unused) {
        for (const rule of rules)
            errors.push(
                `${path}: ${rule} has no suppression; remove it from ${listPath}`,
            );
    }
    return errors;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    const root = resolve(
        process.argv[2] ?? resolve(import.meta.dirname, "../../.."),
    );
    const files = execFileSync(
        "git",
        [
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
            "--",
            "apple",
        ],
        { cwd: root, encoding: "utf8" },
    ).split("\0");
    const sources = [...new Set(files)]
        .filter(
            (path) =>
                path.endsWith(".swift") && existsSync(resolve(root, path)),
        )
        .map((path) => ({
            path,
            source: readFileSync(resolve(root, path), "utf8"),
        }));
    const errors = check(
        parse(sources),
        JSON.parse(readFileSync(resolve(root, listPath), "utf8")),
    );
    for (const error of errors) console.error(error);
    process.exitCode = errors.length ? 1 : 0;
}
