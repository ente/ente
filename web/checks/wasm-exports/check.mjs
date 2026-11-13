import { execFileSync } from "node:child_process";
import { existsSync, globSync, readFileSync } from "node:fs";
import { basename, dirname, relative, resolve } from "node:path";
import ts from "typescript";
import { rustExports, unusedExports } from "./exports.mjs";

const cwd = resolve(import.meta.dirname, "../..");
const rustDirectory = resolve(cwd, "../rust/bindings/wasm");
const crateExports = (crate) =>
    rustExports(
        globSync(`${crate}/src/**/*.rs`, { cwd: rustDirectory }).map((file) =>
            resolve(rustDirectory, file),
        ),
    );
const sharedExports = crateExports("lib");
const rustOrigins = new Map();
const files = [];
for (const manifestPath of globSync("packages/wasm/*/package.json", { cwd })) {
    const manifest = JSON.parse(
        readFileSync(resolve(cwd, manifestPath), "utf8"),
    );
    if (!manifest.scripts?.build) continue;
    const directory = resolve(cwd, dirname(manifestPath));
    const bindings = resolve(
        directory,
        "pkg",
        `${manifest.name.replaceAll("-", "_")}.d.ts`,
    );
    if (!existsSync(bindings))
        throw new Error(`Build WASM before checking exports: ${bindings}`);
    rustOrigins.set(
        bindings,
        new Map([...sharedExports, ...crateExports(basename(directory))]),
    );
    files.push(
        bindings,
        ...globSync("**/*.ts", {
            cwd: directory,
            exclude: [
                "pkg/**",
                "tests/**",
                "**/*.test.ts",
                "**/*.config.ts",
                "**/*.d.ts",
            ],
        }).map((file) => resolve(directory, file)),
    );
}

const projects = globSync("apps/*/tsconfig.json", { cwd }).map((file) => {
    const parsed = ts.getParsedCommandLineOfConfigFile(
        resolve(cwd, file),
        {},
        {
            ...ts.sys,
            onUnRecoverableConfigFileDiagnostic: (error) => {
                throw new Error(
                    ts.flattenDiagnosticMessageText(error.messageText, "\n"),
                );
            },
        },
    );
    if (parsed.errors.length)
        throw new Error(
            ts.formatDiagnostics(parsed.errors, {
                getCanonicalFileName: (file) => file,
                getCurrentDirectory: () => cwd,
                getNewLine: () => "\n",
            }),
        );
    const entryFiles = parsed.fileNames.filter(
        (file) =>
            /\/src\/pages\/.*\.tsx?$|\/src\/main\.tsx?$/.test(file) &&
            !/\.test\./.test(file),
    );
    if (!entryFiles.length)
        throw new Error(`No production entrypoints found for ${file}`);
    return { entryFiles, options: parsed.options };
});

for (const { file, line, name } of unusedExports(
    files,
    projects,
    rustOrigins,
)) {
    console.error(
        `${relative(cwd, file)}:${line}: ${name} has no production reference`,
    );
    process.exitCode = 1;
}
execFileSync(process.execPath, ["--test", "checks/wasm-exports/test.mjs"], {
    cwd,
    stdio: "inherit",
});
