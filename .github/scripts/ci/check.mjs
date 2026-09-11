import { execFileSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";

const paths = JSON.parse(
    readFileSync(new URL("paths.json", import.meta.url), "utf8"),
);
const jobs = Object.keys(paths);

const [command, ...args] = process.argv.slice(2);
if (command === "select" && args.length === 2) {
    const selected = select(...args);
    console.log(`Selected CI: ${selected.join(", ")}`);
    appendFileSync(
        process.env.GITHUB_OUTPUT,
        `jobs=${JSON.stringify(selected)}\n`,
    );
} else if (command === "result" && args.length === 0) {
    const failed = failures(JSON.parse(process.env.NEEDS));
    if (failed.length) {
        console.error(failed.join("\n"));
        process.exitCode = 1;
    } else {
        console.log("All selected CI workflows passed.");
    }
} else {
    throw new Error("Usage: check.mjs select BASE HEAD | result");
}

function select(base, head) {
    const changed = (patterns) =>
        execFileSync("git", [
            "diff",
            "--name-only",
            "--no-renames",
            "-z",
            base,
            head,
            "--",
            ...patterns.map((pattern) => `:(top,glob)${pattern}`),
        ]).length > 0;
    if (changed([".github/scripts/ci/**", ".github/workflows/ci.yml"]))
        return jobs;
    return Object.entries(paths)
        .filter(
            ([, patterns]) =>
                patterns === null || (patterns.length > 0 && changed(patterns)),
        )
        .map(([job]) => job);
}

function failures(needs) {
    if (needs.select?.result !== "success")
        return ["CI selection did not succeed"];
    const selected = JSON.parse(needs.select.outputs.jobs);
    if (
        !Array.isArray(selected) ||
        selected.some((job) => !jobs.includes(job)) ||
        !selected.includes("repo-lint")
    ) {
        throw new Error("Invalid CI selection");
    }
    return jobs.flatMap((job) => {
        const result = needs[job]?.result;
        const expected = selected.includes(job) ? "success" : "skipped";
        return result === expected
            ? []
            : [`${job}: expected ${expected}, got ${result ?? "no result"}`];
    });
}
