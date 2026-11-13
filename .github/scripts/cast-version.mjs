#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "../..",
);
const xcode = path.join(root, "apple/apps/cast/Cast.xcodeproj/project.pbxproj");

function source() {
    return fs.readFileSync(xcode, "utf8");
}

function fieldPattern(name) {
    return new RegExp(`${name} = ([^;]+);`, "g");
}

function value(name) {
    const found = fieldPattern(name).exec(source())?.[1];
    if (!found) throw new Error(`${name}: no Cast entry found`);
    return found;
}

function set(name, next) {
    const text = source();
    const pattern = fieldPattern(name);
    if (!pattern.test(text)) throw new Error(`${name}: no Cast entry found`);
    fs.writeFileSync(xcode, text.replace(pattern, `${name} = ${next};`));
}

function checkVersion(version) {
    if (!/^\d+\.\d+\.\d+$/.test(version))
        throw new Error(`Invalid Cast version: ${version}`);
}

function checkBuild(build) {
    if (!/^\d+$/.test(build))
        throw new Error(`Invalid Cast build number: ${build}`);
}

function usage() {
    console.error(`Usage:
  node .github/scripts/cast-version.mjs get
  node .github/scripts/cast-version.mjs get-build-base
  node .github/scripts/cast-version.mjs set 1.2.0
  node .github/scripts/cast-version.mjs set-build 1.2.0 34
  node .github/scripts/cast-version.mjs bump-build`);
}

const [command = "get", ...args] = process.argv.slice(2);

try {
    if (command === "get") {
        const version = value("MARKETING_VERSION");
        checkVersion(version);
        console.log(version);
    } else if (command === "get-build-base") {
        const build = value("CURRENT_PROJECT_VERSION");
        checkBuild(build);
        console.log(build);
    } else if (command === "set") {
        checkVersion(args[0]);
        set("MARKETING_VERSION", args[0]);
    } else if (command === "set-build") {
        checkVersion(args[0]);
        checkBuild(args[1]);
        set("MARKETING_VERSION", args[0]);
        set("CURRENT_PROJECT_VERSION", args[1]);
    } else if (command === "bump-build") {
        const build = value("CURRENT_PROJECT_VERSION");
        checkBuild(build);
        set("CURRENT_PROJECT_VERSION", Number(build) + 1);
    } else {
        usage();
        process.exit(2);
    }
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
