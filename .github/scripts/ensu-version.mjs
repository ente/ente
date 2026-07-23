#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const files = {
    packageJson: path.join(root, "rust/apps/ensu/package.json"),
    packageLock: path.join(root, "rust/apps/ensu/package-lock.json"),
    tauri: path.join(root, "rust/apps/ensu/src-tauri/tauri.conf.json"),
    cargoToml: path.join(root, "rust/apps/ensu/src-tauri/Cargo.toml"),
    cargoLock: path.join(root, "rust/Cargo.lock"),
    android: path.join(root, "mobile/native/android/apps/ensu/app/build.gradle.kts"),
    xcode: path.join(root, "mobile/native/apple/apps/ensu/Ensu.xcodeproj/project.pbxproj"),
    plist: path.join(root, "mobile/native/apple/apps/ensu/Ensu/Info.plist"),
};

function read(file) {
    return fs.readFileSync(file, "utf8");
}

function write(file, text) {
    fs.writeFileSync(file, text);
}

function trimVersion(version) {
    const match = /^(\d+\.\d+\.\d+)(-beta)?$/.exec(version);
    if (!match) throw new Error(`Invalid Ensu version: ${version}`);
    return match[1];
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

function sourceBuildNumber() {
    const buildNumber = value(files.android, /versionCode = .*\?: (\d+)/);
    if (!buildNumber) throw new Error("Android versionCode: no default found");
    return buildNumber;
}

function setBuildNumber(buildNumber) {
    replace(files.android, /(versionCode = .*\?: )\d+/, (_m, prefix) => `${prefix}${buildNumber}`);
    replace(files.xcode, /CURRENT_PROJECT_VERSION = [^;]+;/g, `CURRENT_PROJECT_VERSION = ${buildNumber};`);
}

function check() {
    const version = sourceVersion();
    const releaseVersion = trimVersion(version);
    const buildNumber = sourceBuildNumber();

    const xcodeBuildNumbers = [...read(files.xcode).matchAll(/CURRENT_PROJECT_VERSION = ([^;]+);/g)];
    if (!xcodeBuildNumbers.length) throw new Error("Xcode CURRENT_PROJECT_VERSION: no entries found");
    for (const match of xcodeBuildNumbers) {
        expect("Xcode CURRENT_PROJECT_VERSION", match[1], buildNumber);
    }

    expect("tauri.conf.json", value(files.tauri, /^\s*"version"\s*:\s*"([^"]+)"/m), version);
    expect("package-lock.json", value(files.packageLock, /"name": "ensu-desktop",\n\s+"version": "([^"]+)"/), version);
    expect("package-lock.json packages[\"\"]", value(files.packageLock, /"": \{\n\s+"name": "ensu-desktop",\n\s+"version": "([^"]+)"/), version);
    expect("Cargo.toml", value(files.cargoToml, /\[package\][\s\S]*?^version = "([^"]+)"/m), version);
    expect("Cargo.lock", value(files.cargoLock, /\[\[package\]\]\nname = "ensu-desktop"\nversion = "([^"]+)"/), version);
    expect("Android versionName", value(files.android, /versionName = "([^"]+)"/), releaseVersion);
    expect("Info.plist", value(files.plist, /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/), releaseVersion);

    const xcodeMarketingVersions = [...read(files.xcode).matchAll(/MARKETING_VERSION = ([^;]+);/g)];
    if (!xcodeMarketingVersions.length) throw new Error("Xcode MARKETING_VERSION: no entries found");
    for (const match of xcodeMarketingVersions) {
        expect("Xcode MARKETING_VERSION", match[1], releaseVersion);
    }
}

function setVersion(version) {
    const releaseVersion = trimVersion(version);

    replace(files.packageJson, /("name": "ensu-desktop",\n\s+"version": ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    replace(files.packageLock, /("name": "ensu-desktop",\n\s+"version": ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    replace(files.packageLock, /("": \{\n\s+"name": "ensu-desktop",\n\s+"version": ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    replace(files.tauri, /^(\s*"version"\s*:\s*")[^"]+(")/m, (_m, a, b) => `${a}${version}${b}`);
    replace(files.cargoToml, /(\[package\][\s\S]*?^version = ")[^"]+(")/m, (_m, a, b) => `${a}${version}${b}`);
    replace(files.cargoLock, /(\[\[package\]\]\nname = "ensu-desktop"\nversion = ")[^"]+(")/, (_m, a, b) => `${a}${version}${b}`);
    replace(files.android, /versionName = "[^"]+"/, `versionName = "${releaseVersion}"`);
    replace(files.xcode, /MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${releaseVersion};`);
    replace(files.plist, /(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]+(<\/string>)/, (_m, a, b) => `${a}${releaseVersion}${b}`);
}

function usage() {
    console.error(`Usage:
  node .github/scripts/ensu-version.mjs get
  node .github/scripts/ensu-version.mjs get-build-base
  node .github/scripts/ensu-version.mjs set 0.1.16-beta
  node .github/scripts/ensu-version.mjs set 0.1.16
  node .github/scripts/ensu-version.mjs set-build 0.1.16 34
  node .github/scripts/ensu-version.mjs bump-build`);
}

const [command = "get", ...args] = process.argv.slice(2);

try {
    if (command === "get") {
        check();
        console.log(sourceVersion());
    } else if (command === "get-build-base") {
        check();
        console.log(sourceBuildNumber());
    } else if (command === "set") {
        setVersion(args[0]);
        check();
    } else if (command === "set-build") {
        if (!/^\d+$/.test(args[1])) throw new Error(`Invalid Ensu build number: ${args[1]}`);
        setVersion(args[0]);
        setBuildNumber(args[1]);
        check();
    } else if (command === "bump-build") {
        setBuildNumber(Number(sourceBuildNumber()) + 1);
        check();
    } else {
        usage();
        process.exit(2);
    }
} catch (error) {
    console.error(error.message);
    process.exit(1);
}
