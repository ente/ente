import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { extname, resolve } from "node:path";

const root = resolve(process.argv[2] ?? ".");
const extensions = new Set([
    ".c",
    ".cc",
    ".cjs",
    ".cpp",
    ".css",
    ".dart",
    ".gradle",
    ".h",
    ".java",
    ".js",
    ".jsx",
    ".kt",
    ".kts",
    ".less",
    ".mjs",
    ".rs",
    ".sass",
    ".scss",
    ".swift",
    ".ts",
    ".tsx",
]);
const paths = git(
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "-z",
)
    .split("\0")
    .filter(
        (path) =>
            path &&
            extensions.has(extname(path)) &&
            existsSync(resolve(root, path)),
    );

if (!paths.length) throw new Error(`${root}: found no source files`);

for (const path of paths) {
    const source = readFileSync(resolve(root, path), "utf8");
    if (isGenerated(source)) continue;
    const comments = documentationComments(source);
    const clap = path.endsWith(".rs") ? clapRanges(source, comments) : [];
    for (const comment of comments) {
        if (isToolInput(path, comment.text)) continue;
        if (
            clap.some(
                ([start, end]) => comment.line >= start && comment.line <= end,
            )
        )
            continue;
        console.error(
            `${path}:${comment.line}: documentation comment; use an ordinary comment if needed`,
        );
        process.exitCode = 1;
    }
}

function git(...args) {
    return execFileSync("git", args, {
        cwd: root,
        encoding: "utf8",
        maxBuffer: 10 * 1024 * 1024,
    });
}

function documentationComments(source) {
    const comments = [];
    const lines = source.split("\n");
    for (let i = 0; i < lines.length; i++) {
        if (/^\s*(?:\/\/\/|\/\/!)/.test(lines[i])) {
            const start = i;
            while (
                i < lines.length - 1 &&
                /^\s*(?:\/\/\/|\/\/!)/.test(lines[i + 1])
            )
                i++;
            comments.push({
                line: start + 1,
                endLine: i + 1,
                text: lines.slice(start, i + 1).join("\n"),
            });
            continue;
        }
        if (!/^\s*\/\*(?:\*|!)/.test(lines[i])) continue;
        const start = i;
        while (i < lines.length && !lines[i].includes("*/")) i++;
        comments.push({
            line: start + 1,
            endLine: i + 1,
            text: lines.slice(start, i + 1).join("\n"),
        });
    }
    return comments;
}

function isToolInput(path, comment) {
    const extension = extname(path);
    if (![".cjs", ".js", ".jsx", ".mjs", ".ts", ".tsx"].includes(extension))
        return false;
    if (
        comment
            .split("\n")
            .every((line) =>
                /^\s*\/\/\/\s*<(?:reference|amd-(?:module|dependency))\b[^>]*\/>\s*$/.test(
                    line,
                ),
            )
    ) {
        return true;
    }
    if ([".ts", ".tsx"].includes(extension)) return false;
    const annotations = comment
        .replace(/^\s*\/\*\*/, "")
        .replace(/\*\/\s*$/, "")
        .split("\n")
        .map((line) => line.replace(/^\s*\*?\s?/, "").trim())
        .filter(Boolean);
    return (
        annotations.length > 0 &&
        annotations.every(
            (annotation) =>
                /^@(satisfies|type|returns?)\s+\{.+\}$/.test(annotation) ||
                /^@param\s+\{.+\}\s+\S+$/.test(annotation) ||
                /^@typedef\s+\{.+\}\s+\S+$/.test(annotation) ||
                /^@prop(?:erty)?\s+\{.+\}\s+\S+$/.test(annotation) ||
                /^@template(?:\s+\{.+\})?\s+\S+$/.test(annotation),
        )
    );
}

function isGenerated(source) {
    return /^\s*(?:\/\/+|\/\*+|\*)\s*(?:@generated\b|.*\bgenerated\b.*\bdo not (?:edit|modify)\b)/im.test(
        source.split("\n").slice(0, 12).join("\n"),
    );
}

function clapRanges(source, comments) {
    const lines = source.split("\n");
    const ranges = [];
    for (let i = 0; i < lines.length; i++) {
        if (!/#\s*\[\s*derive\s*\(/.test(lines[i])) continue;
        let start = i + 1;
        const help = comments.find((comment) => comment.endLine === start - 1);
        if (help) start = help.line;
        let derive = lines[i];
        while (i < lines.length - 1 && !derive.includes(")]"))
            derive += `\n${lines[++i]}`;
        if (!/\b(?:Args|Parser|Subcommand)\b/.test(derive)) continue;
        let declaration = i + 1;
        while (
            declaration < lines.length &&
            !/\b(?:struct|enum)\s+\w+/.test(lines[declaration])
        ) {
            declaration++;
        }
        let depth = 0;
        let opened = false;
        for (let end = declaration; end < lines.length; end++) {
            const code = lines[end].replace(/\/\/.*$/, "");
            depth += (code.match(/{/g) ?? []).length;
            if (depth) opened = true;
            depth -= (code.match(/}/g) ?? []).length;
            if (!opened && /;\s*$/.test(code)) {
                ranges.push([start, end + 1]);
                i = end;
                break;
            }
            if (!opened || depth) continue;
            ranges.push([start, end + 1]);
            i = end;
            break;
        }
    }
    return ranges;
}
