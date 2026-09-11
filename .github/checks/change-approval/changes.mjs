import { execFileSync } from "node:child_process";
import {
    closeSync,
    lstatSync,
    openSync,
    readFileSync,
    readSync,
} from "node:fs";
import { resolve } from "node:path";

export function readChanges(base, local) {
    const root = execFileSync("git", ["rev-parse", "--show-toplevel"], {
        encoding: "utf8",
    }).trim();
    const git = (...args) =>
        execFileSync("git", args, {
            cwd: root,
            encoding: "utf8",
            maxBuffer: 64 * 1024 * 1024,
        });
    const mergeBase = git("merge-base", base, "HEAD").trim();
    const numstat = (...filter) =>
        git(
            "diff",
            "--numstat",
            "--no-renames",
            "-z",
            ...filter,
            mergeBase,
            ...(local ? [] : ["HEAD"]),
        )
            .split("\0")
            .filter(Boolean)
            .map((row) => {
                const [, added, , path] = row.match(
                    /^([^\t]+)\t([^\t]+)\t(.*)$/s,
                );
                return { path, binary: added === "-" };
            });
    const untracked = local
        ? git("ls-files", "--others", "--exclude-standard", "-z")
              .split("\0")
              .filter(
                  (path) =>
                      path && !lstatSync(resolve(root, path)).isSymbolicLink(),
              )
              .map((path) => ({ path, binary: isBinary(resolve(root, path)) }))
        : [];
    const changed = [...numstat(), ...untracked];
    const pathsBefore = new Set(
        numstat("--diff-filter=a").map(({ path }) => path),
    );
    const pathsAfter = new Set(
        [...numstat("--diff-filter=d"), ...untracked].map(({ path }) => path),
    );
    const sizes = new Map();
    if (local) {
        for (const path of pathsAfter) {
            const stat = lstatSync(resolve(root, path));
            if (stat.isFile()) sizes.set(path, stat.size);
        }
    } else if (pathsAfter.size) {
        const tree = git(
            "--literal-pathspecs",
            "ls-tree",
            "-l",
            "-z",
            "HEAD",
            "--",
            ...pathsAfter,
        );
        for (const entry of tree.split("\0")) {
            const blob = entry.match(/ blob \S+ +(\d+)\t(.*)$/s);
            if (blob) {
                const [, size, path] = blob;
                sizes.set(path, Number(size));
            }
        }
    }
    const readBefore = (path) => git("show", `${mergeBase}:${path}`);
    const readAfter = (path) =>
        local
            ? readFileSync(resolve(root, path), "utf8")
            : git("show", `HEAD:${path}`);

    return {
        files: changed.map(({ path, binary }) => ({
            path,
            binary,
            added: !pathsBefore.has(path),
            deleted: !pathsAfter.has(path),
            size: sizes.get(path),
        })),
        baseFiles: () =>
            git("ls-tree", "-r", "--name-only", "-z", mergeBase)
                .split("\0")
                .filter(Boolean),
        readBefore,
        readAfter,
        readAddedLines: (path) => {
            if (!sizes.has(path)) return "";
            if (!pathsBefore.has(path)) return readAfter(path);
            return git(
                "--literal-pathspecs",
                "diff",
                "--no-ext-diff",
                "--no-textconv",
                "--unified=0",
                "--output-indicator-new=>",
                mergeBase,
                ...(local ? [] : ["HEAD"]),
                "--",
                path,
            )
                .split("\n")
                .filter((line) => line.startsWith(">"))
                .map((line) => line.slice(1))
                .join("\n");
        },
        readVersions: (path) => ({
            before: pathsBefore.has(path) ? readBefore(path) : "",
            after: sizes.has(path) ? readAfter(path) : "",
        }),
    };
}

function isBinary(path) {
    const fd = openSync(path, "r");
    const buffer = Buffer.alloc(8000);
    const length = readSync(fd, buffer);
    closeSync(fd);
    return buffer.subarray(0, length).includes(0);
}
