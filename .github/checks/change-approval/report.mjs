import { appendFileSync } from "node:fs";

export function writeReport({
    files: { binaries, large, guardrails, configs },
    dependencies,
    rust,
    web,
}) {
    const categories = [
        {
            singular: "binary file",
            plural: "binary files",
            count: binaries.length,
        },
        { singular: "large file", plural: "large files", count: large.length },
        {
            singular: "new dependency",
            plural: "new dependencies",
            count: dependencies.reduce(
                (count, { added }) => count + added.length,
                0,
            ),
        },
        {
            singular: "dependency source change",
            plural: "dependency source changes",
            count: dependencies.reduce(
                (count, { moved }) => count + moved.length,
                0,
            ),
        },
        {
            singular: "guardrail file",
            plural: "guardrail files",
            count: guardrails.length,
        },
        {
            singular: "config file",
            plural: "config files",
            count: configs.length,
        },
        {
            singular: "Rust lint policy file",
            plural: "Rust lint policy files",
            count: rust.length,
        },
        {
            singular: "Web lint policy file",
            plural: "Web lint policy files",
            count: web.length,
        },
    ].filter(({ count }) => count);
    const summary = categories
        .map(
            ({ singular, plural, count }) =>
                `${count} ${count === 1 ? singular : plural}`,
        )
        .join(", ");
    const sections = [];
    if (binaries.length)
        sections.push(`## Binary files\n\n${list(binaries.map(withSize))}`);
    if (large.length)
        sections.push(`## Large files\n\n${list(large.map(withSize))}`);
    if (dependencies.length) {
        const entries = dependencies.map(
            ({ file, added, moved }) =>
                `${code(file)}\n\n${list([
                    ...added.map(({ name, version }) => `${name} ${version}`),
                    ...moved.map(
                        ({ name, sourcesBefore, sourceAfter }) =>
                            `${name}: ${sourcesBefore.join(", ")} -> ${sourceAfter}`,
                    ),
                ])}`,
        );
        sections.push(`## New dependencies\n\n${entries.join("\n\n")}`);
    }
    if (guardrails.length)
        sections.push(`## Guardrail changes\n\n${list(guardrails.map(code))}`);
    if (configs.length)
        sections.push(
            `## Toolchain and registry config\n\n${list(configs.map(code))}`,
        );
    if (rust.length)
        sections.push(
            `## Rust lint declarations and files containing unsafe\n\n${list(rust.map(({ path, reasons }) => `${code(path)}: ${reasons.map(code).join("; ")}`))}`,
        );
    if (web.length)
        sections.push(`## Web lint directives\n\n${list(web.map(code))}`);
    const detail = sections.join("\n\n");

    const { GITHUB_OUTPUT, GITHUB_STEP_SUMMARY } = process.env;
    if (!GITHUB_OUTPUT) {
        if (summary) console.log(`${summary}\n\n${detail}\n`);
        return;
    }
    appendFileSync(
        GITHUB_OUTPUT,
        `categories=${JSON.stringify(categories.map(({ plural }) => plural))}\n`,
    );
    if (summary)
        console.log(`::warning title=Change approval needed::${summary}`);
    appendFileSync(
        GITHUB_STEP_SUMMARY,
        summary ? `${summary}\n\n${detail}\n` : "No approval needed.\n",
    );
}

function list(items) {
    return items.map((item) => `- ${item}`).join("\n");
}

function code(path) {
    const fence = "`".repeat(
        Math.max(0, ...(path.match(/`+/g) ?? []).map((run) => run.length)) + 1,
    );
    return `${fence}${path.startsWith("`") || path.endsWith("`") ? ` ${path} ` : path}${fence}`;
}

function withSize({ path, size }) {
    return `${code(path)} (${size} bytes)`;
}
