import { basename } from "node:path";

const tomlPackages = (text) =>
    text
        .split("[[package]]\n")
        .slice(1)
        .map((block) => ({
            name: block.match(/^name = "(.+)"$/m)[1],
            version: block.match(/^version = "(.+)"$/m)[1],
            source: block
                .match(/^source = "?(.+?)"?$/m)?.[1]
                ?.replace(/[?#][^"]*/, ""),
        }));
const lockfiles = {
    "Cargo.lock": (text) =>
        tomlPackages(text).map((p) => ({
            ...p,
            source: p.source ?? "workspace",
            local: !p.source,
        })),
    "uv.lock": (text) =>
        tomlPackages(text).map((p) => ({
            ...p,
            local: !/^\{ (registry|git|url) = /.test(p.source),
        })),
    "package-lock.json": (text) =>
        Object.entries(JSON.parse(text).packages)
            .filter(([key]) => key.includes("node_modules/"))
            .map(([key, { name, version, resolved, link }]) => {
                const local =
                    link === true || resolved?.startsWith("file:") === true;
                return {
                    name:
                        name ??
                        key.slice(key.lastIndexOf("node_modules/") + 13),
                    version,
                    source:
                        local || !resolved
                            ? resolved
                            : resolved
                                  .replace(/#.*$/, "")
                                  .replace(/\/-\/[^/]+\.tgz$/, ""),
                    local,
                };
            }),
    "pubspec.lock": (text) =>
        [...text.matchAll(/^  (\S+):\n((?:    .*\n)+)/gm)].map(
            ([, name, body]) => {
                const source = [
                    body.match(/^    source: (.+)$/m)[1],
                    body.match(/^      url: "(.+)"$/m)?.[1],
                ]
                    .filter(Boolean)
                    .join(" ");
                return {
                    name,
                    version: body.match(/^    version: "(.+)"$/m)[1],
                    source,
                    local: source === "path",
                };
            },
        ),
    "go.sum": (text) =>
        [...text.matchAll(/^(\S+) (\S+?)(?:\/go\.mod)? h1:/gm)].map(
            ([, name, version]) => ({ name, version }),
        ),
    "Package.resolved": (text) =>
        JSON.parse(text).pins.map(({ identity, location, state }) => ({
            name: identity,
            version: state.version,
            source: location,
        })),
    "Podfile.lock": (text) => {
        const section = (title) =>
            text.match(new RegExp(`^${title}:\\n((?:  .*\\n)+)`, "m"))?.[1] ??
            "";
        const sources = new Map();
        for (const [, repo, pods] of section("SPEC REPOS").matchAll(
            /^  (\S+):\n((?:    - .*\n)+)/gm,
        )) {
            for (const [, pod] of pods.matchAll(/^    - (.+)$/gm))
                sources.set(pod, { source: repo });
        }
        for (const [, pod, body] of section("EXTERNAL SOURCES").matchAll(
            /^  (\S+):\n((?:    .*\n)+)/gm,
        )) {
            const props = Object.fromEntries(
                [...body.matchAll(/^    :(\w+): (.+)$/gm)].map(
                    ([, key, value]) => [key, value],
                ),
            );
            const source = props.git ?? props.podspec ?? props.path;
            sources.set(pod, {
                source,
                local: !props.git && !/^"?https?:\/\//.test(source),
            });
        }
        return [
            ...section("PODS").matchAll(/^  - "?([^/" ]+)\S* \(([^)]+)\)/gm),
        ].map(([, name, version]) => ({ name, version, ...sources.get(name) }));
    },
};

export function checkDependencies({ files, baseFiles, readBefore, readAfter }) {
    const known = new Map();
    for (const file of baseFiles()) {
        const kind = basename(file);
        if (!lockfiles[kind]) continue;
        if (!known.has(kind)) known.set(kind, new Map());
        const names = known.get(kind);
        for (const { name, source } of lockfiles[kind](readBefore(file))) {
            if (!names.has(name)) names.set(name, new Set());
            names.get(name).add(source);
        }
    }
    const dependencies = [];
    for (const { path: file, deleted } of files) {
        const kind = basename(file);
        if (deleted || !lockfiles[kind]) continue;
        const before = known.get(kind) ?? new Map();
        const added = new Map();
        const moved = new Map();
        for (const { name, version, source, local } of lockfiles[kind](
            readAfter(file),
        )) {
            if (local) continue;
            const sources = before.get(name);
            if (!sources) {
                added.set(JSON.stringify([name, version]), { name, version });
            } else if (source && !sources.has(source)) {
                moved.set(JSON.stringify([name, source]), {
                    name,
                    sourcesBefore: [...sources],
                    sourceAfter: source,
                });
            }
        }
        if (added.size || moved.size) {
            dependencies.push({
                file,
                added: [...added.values()],
                moved: [...moved.values()],
            });
        }
    }
    return dependencies;
}
