#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const [app, command = "get", ...args] = process.argv.slice(2);

function usage() {
    console.error(`Usage:
  node .github/scripts/flutter-version.mjs auth get
  node .github/scripts/flutter-version.mjs auth get-build-base
  node .github/scripts/flutter-version.mjs auth set 4.4.23
  node .github/scripts/flutter-version.mjs auth set-build 4.4.23 1007
  node .github/scripts/flutter-version.mjs auth bump-build

Valid apps: photos, auth, locker`);
}

if (!app) {
    usage();
    process.exit(2);
}

const pubspec = path.join(root, "mobile/apps", app, "pubspec.yaml");

function read() {
    return fs.readFileSync(pubspec, "utf8");
}

function write(text) {
    fs.writeFileSync(pubspec, text);
}

function pubspecVersion() {
    const match = read().match(/^version:\s*(\d+\.\d+\.\d+)\+(\d+)$/m);
    if (!match) throw new Error(`Invalid ${app} pubspec version`);
    return { source: match[1], buildBase: match[2] };
}

function setPubspecVersion(version) {
    const text = read();
    let count = 0;
    const next = text.replace(/^version:\s*\S+/m, () => {
        count += 1;
        return `version: ${version}`;
    });
    if (!count) throw new Error(`No version field found in ${path.relative(root, pubspec)}`);
    write(next);
}

try {
    if (command === "get") {
        console.log(pubspecVersion().source);
    } else if (command === "get-build-base") {
        console.log(pubspecVersion().buildBase);
    } else if (command === "set") {
        if (!/^\d+\.\d+\.\d+$/.test(args[0])) throw new Error(`Invalid ${app} version: ${args[0]}`);
        setPubspecVersion(`${args[0]}+${pubspecVersion().buildBase}`);
    } else if (command === "set-build") {
        if (!/^\d+\.\d+\.\d+$/.test(args[0])) throw new Error(`Invalid ${app} release version: ${args[0]}`);
        if (!/^\d+$/.test(args[1])) throw new Error(`Invalid ${app} build number: ${args[1]}`);
        setPubspecVersion(`${args[0]}+${args[1]}`);
    } else if (command === "bump-build") {
        const { source, buildBase } = pubspecVersion();
        setPubspecVersion(`${source}+${Number(buildBase) + 1}`);
    } else {
        usage();
        process.exit(2);
    }
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
