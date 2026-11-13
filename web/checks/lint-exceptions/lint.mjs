import { SourceCode } from "eslint";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parser } from "typescript-eslint";

const root = resolve(
    process.argv[2] ?? resolve(import.meta.dirname, "../../.."),
);
const listPath = "web/checks/lint-exceptions/suppressions.json";
const allowed = JSON.parse(readFileSync(resolve(root, listPath), "utf8"));
const unused = new Map(
    Object.entries(allowed).map(([path, rules]) => [path, new Set(rules)]),
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
        "web",
    ],
    { cwd: root, encoding: "utf8" },
).split("\0");

for (const path of new Set(files)) {
    if (!/\.[cm]?[jt]sx?$/.test(path) || !existsSync(resolve(root, path)))
        continue;
    const text = readFileSync(resolve(root, path), "utf8");
    const parsed = parser.parseForESLint(text, {
        filePath: path,
        sourceType: "module",
        ecmaFeatures: { jsx: /x$/.test(path) },
    });
    const source = new SourceCode({ text, ...parsed });
    const { directives, problems } = source.getDisableDirectives();
    const inline = source.applyInlineConfig();
    for (const { message, loc } of [...problems, ...inline.problems]) {
        reject(path, loc.start.line, message);
    }
    for (const { type, value, node } of directives) {
        if (type === "enable") continue;
        const rules = value
            .split(",")
            .map((rule) => rule.trim().replace(/^(['"])(.*)\1$/, "$2"))
            .filter(Boolean);
        if (!rules.length)
            reject(
                path,
                node.loc.start.line,
                "Name the rules being suppressed",
            );
        for (const rule of rules) check(path, node.loc.start.line, rule);
    }
    for (const { config, loc } of inline.configs) {
        for (const rule of Object.keys(config.rules))
            check(path, loc.start.line, rule);
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

function check(path, line, rule) {
    unused.get(path)?.delete(rule);
    if (!allowed[path]?.includes(rule)) {
        reject(path, line, `${rule} is not listed in ${listPath}`);
    }
}

function reject(path, line, message) {
    console.error(`${path}:${line}: ${message}`);
    process.exitCode = 1;
}
