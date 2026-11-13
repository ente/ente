import { execFileSync } from "node:child_process";
import {
    existsSync,
    mkdtempSync,
    readFileSync,
    rmSync,
    writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const listPath = "android/checks/lint-exceptions/suppressions.json";

export function parse(sources) {
    const temporary = mkdtempSync(join(tmpdir(), "ente-suppression-parser-"));
    try {
        writeFileSync(
            join(temporary, "settings.gradle"),
            'rootProject.name = "lint-exceptions"\n',
        );
        writeFileSync(join(temporary, "sources.json"), JSON.stringify(sources));
        execFileSync(
            resolve(import.meta.dirname, "../../gradlew"),
            [
                "--quiet",
                "--console=plain",
                "--project-dir",
                temporary,
                "--init-script",
                resolve(import.meta.dirname, "parse.gradle"),
                "parseLintSuppressions",
            ],
            { stdio: ["ignore", "pipe", "inherit"] },
        );
        return JSON.parse(
            readFileSync(join(temporary, "suppressions.json"), "utf8"),
        );
    } finally {
        rmSync(temporary, { recursive: true, force: true });
    }
}

export function check(records, allowed) {
    const unused = new Map(
        Object.entries(allowed).map(([path, rules]) => [path, new Set(rules)]),
    );
    const errors = [];
    for (const { path, line, rules, error } of records) {
        if (error) {
            errors.push(`${path}:${line}: ${error}`);
            continue;
        }
        if (
            !rules.length ||
            rules.some(
                (rule) =>
                    typeof rule !== "string" ||
                    !/^[\w.:-]+$/.test(rule) ||
                    rule.toLowerCase() === "all",
            )
        ) {
            errors.push(
                `${path}:${line}: Name the rules being suppressed using literal rule IDs`,
            );
            continue;
        }
        for (const rule of rules) {
            unused.get(path)?.delete(rule);
            if (!allowed[path]?.includes(rule))
                errors.push(
                    `${path}:${line}: ${rule} is not listed in ${listPath}`,
                );
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
            "android",
        ],
        { cwd: root, encoding: "utf8" },
    ).split("\0");
    const sources = [...new Set(files)]
        .filter(
            (path) =>
                /\.(?:kt|kts|java|xml)$/.test(path) &&
                existsSync(resolve(root, path)),
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
