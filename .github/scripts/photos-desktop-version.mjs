#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const files = {
    packageJson: path.join(root, "desktop/package.json"),
    packageLock: path.join(root, "desktop/package-lock.json"),
};

function read(file) {
    return fs.readFileSync(file, "utf8");
}

function write(file, text) {
    fs.writeFileSync(file, text);
}

function validateVersion(version) {
    if (!/^\d+\.\d+\.\d+(-beta)?$/.test(version)) {
        throw new Error(`Invalid desktop version: ${version}`);
    }
    return version;
}

function sourceVersion() {
    return JSON.parse(read(files.packageJson)).version;
}

function value(file, regex) {
    return read(file).match(regex)?.[1];
}

function replace(file, regex, replacement) {
    const text = read(file);
    let count = 0;
    const next = text.replace(regex, (...args) => {
        count += 1;
        return typeof replacement === "function" ? replacement(...args) : replacement;
    });
    if (!count) throw new Error(`No match in ${path.relative(root, file)}`);
    write(file, next);
}

function expect(label, actual, wanted) {
    if (actual !== wanted) throw new Error(`${label}: expected ${wanted}, found ${actual}`);
}

function check() {
    const version = sourceVersion();
    expect("package-lock.json", value(files.packageLock, /"name": "ente",\n\s+"version": "([^"]+)"/), version);
    expect('package-lock.json packages[""]', value(files.packageLock, /"": \{\n\s+"name": "ente",\n\s+"version": "([^"]+)"/), version);
}

function setVersion(version) {
    validateVersion(version);
    replace(files.packageJson, /("name": "ente",\n\s+"version": ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    replace(files.packageLock, /("name": "ente",\n\s+"version": ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    replace(files.packageLock, /("": \{\n\s+"name": "ente",\n\s+"version": ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    check();
}

function usage() {
    console.error(`Usage:
  node .github/scripts/photos-desktop-version.mjs get
  node .github/scripts/photos-desktop-version.mjs set 1.7.25-beta
  node .github/scripts/photos-desktop-version.mjs set 1.7.25`);
}

const [command = "get", ...args] = process.argv.slice(2);

try {
    if (command === "get") {
        check();
        console.log(sourceVersion());
    } else if (command === "set") {
        setVersion(args[0]);
    } else {
        usage();
        process.exit(2);
    }
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
