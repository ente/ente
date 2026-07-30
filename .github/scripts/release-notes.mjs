#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const [changesDir, previousRef] = process.argv.slice(2);

if (!changesDir) {
    console.error("Usage: node .github/scripts/release-notes.mjs <changes-dir> [previous-ref]");
    process.exit(2);
}

function git(args) {
    const result = spawnSync("git", args, { encoding: "utf8" });
    return result.status === 0 ? result.stdout : "";
}

function readMarkdown(file) {
    return fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n").replace(/\n?$/, "\n");
}

function changesetFiles(dir) {
    return fs
        .readdirSync(dir, { withFileTypes: true })
        .filter((entry) => entry.isFile())
        .map((entry) => entry.name)
        .filter((name) => name.endsWith(".md") && name !== "README.md")
        .sort()
        .map((name) => path.join(dir, name));
}

function changesetFilesAtRef(dir, ref) {
    const prefix = dir.replace(/^\.\//, "").replace(/\/$/, "");
    return git(["ls-tree", "-r", "--name-only", ref, "--", prefix])
        .split("\n")
        .filter((file) => path.dirname(file) === prefix)
        .filter((file) => file.endsWith(".md") && path.basename(file) !== "README.md")
        .sort();
}

function currentBody() {
    return changesetFiles(changesDir).map(readMarkdown).join("").trim();
}

function previousBody() {
    if (!previousRef) return "";
    return changesetFilesAtRef(changesDir, previousRef)
        .map((file) => git(["show", `${previousRef}:${file}`]).replace(/\r\n/g, "\n").replace(/\n?$/, "\n"))
        .join("")
        .trim();
}

function releaseNotes(body, previous) {
    const previousLines = new Set(previous.split("\n").filter(Boolean));
    const latest = [];
    const previousAgain = [];
    for (const line of body.split("\n").filter(Boolean)) {
        (previousLines.has(line) ? previousAgain : latest).push(line);
    }

    const groupedBody =
        previousAgain.length
            ? [latest.join("\n"), `Previous changes:\n${previousAgain.join("\n")}`].filter(Boolean).join("\n\n")
            : body;
    return { groupedBody, hasNewChanges: latest.length > 0 };
}

function playStoreBody(body) {
    return Array.from(body || "Bug fixes and improvements").slice(0, 500).join("");
}

function output(name, text) {
    let delimiter = "RELEASE_NOTES_EOF";
    while (text.includes(delimiter)) delimiter += "_";

    console.log(`${name}<<${delimiter}`);
    console.log(text);
    console.log(delimiter);
}

const body = currentBody();
const notes = releaseNotes(body, previousBody());

output("release_body", body);
output("release_body_grouped", notes.groupedBody);
output("play_store_release_notes", playStoreBody(body));
output("has_new_changes", notes.hasNewChanges ? "true" : "false");
