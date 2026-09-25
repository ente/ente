import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

interface SourceEmoji {
    hexcode: string;
    label: string;
    group?: number;
    tags?: string[];
    skins?: SourceEmoji[];
    tone?: number | number[];
}

const [dataDirectory, notoDirectory] = process.argv.slice(2);
if (!dataDirectory || !notoDirectory)
    throw new Error(
        "Usage: generate-emoji-assets.mts <emojibase-data> <noto-emoji>",
    );

const notoRevision = "8998f5dd683424a73e2314a8c1f1e359c19e8742";
if (
    execFileSync("git", ["rev-parse", "HEAD"], {
        cwd: notoDirectory,
        encoding: "utf8",
    }).trim() !== notoRevision
)
    throw new Error("Expected Noto Emoji v2.051");

const app = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = resolve(app, "public/emoji/17.0");
const dataOutput = resolve(app, "src/data");
const rustOutput = resolve(app, "../../../rust/crates/space/data");
await Promise.all(
    [output, dataOutput, rustOutput].map((path) =>
        mkdir(path, { recursive: true }),
    ),
);

const source = JSON.parse(
    await readFile(resolve(dataDirectory, "en-data.json"), "utf8"),
) as SourceEmoji[];
const key = (hexcode: string) =>
    hexcode
        .toLowerCase()
        .split("-")
        .filter((part) => part !== "fe0f")
        .map((part) => part.padStart(4, "0"))
        .join("-");
const unicodeData = await readFile(
    resolve(dataDirectory, "emoji-test.txt"),
    "utf8",
);
if (!unicodeData.includes("# Version: 17.0\n"))
    throw new Error("Expected Unicode Emoji 17.0");
const qualified = new Map(
    Array.from(
        unicodeData.matchAll(/^([0-9A-F ]+)\s*; fully-qualified\s*#/gm),
        (match) => {
            const codepoints = match[1]!.trim().split(/\s+/);
            return [
                key(codepoints.join("-")),
                String.fromCodePoint(
                    ...codepoints.map((part) => parseInt(part, 16)),
                ),
            ] as const;
        },
    ),
);
const unicode = (hexcode: string) => {
    const value = qualified.get(key(hexcode));
    if (!value) throw new Error(`Missing Unicode sequence: ${hexcode}`);
    return value;
};
const entries = source.filter(
    ({ group }) => group !== undefined && group !== 2,
);
const catalog = entries.map((entry) => ({
    emoji: unicode(entry.hexcode),
    name: entry.label,
    group: entry.group,
    tags: entry.tags ?? [],
    ...(entry.skins && {
        skins: entry.skins.map((skin) => ({
            emoji: unicode(skin.hexcode),
            name: skin.label,
            tone: skin.tone,
        })),
    }),
}));
const all = [...entries, ...entries.flatMap((entry) => entry.skins ?? [])];
const indices = Object.fromEntries(
    all.map((entry, index) => [key(entry.hexcode), index]),
);
if (Object.keys(indices).length !== all.length)
    throw new Error("Duplicate emoji asset key");
if (all.length !== qualified.size)
    throw new Error("Catalogs cover different Unicode sequences");
const columns = 16;
const tileSize = 64;
const perSheet = columns * columns;

for (let start = 0; start < all.length; start += perSheet) {
    const layers = await Promise.all(
        all.slice(start, start + perSheet).map(async (entry, index) => {
            const filename = `emoji_u${key(entry.hexcode).replaceAll("-", "_")}.svg`;
            const svg = await readFile(
                resolve(notoDirectory, "svg", filename),
            ).catch((error: unknown) => {
                if ((error as NodeJS.ErrnoException).code !== "ENOENT")
                    throw error;
                return readFile(
                    resolve(
                        notoDirectory,
                        "third_party/region-flags/waved-svg",
                        filename,
                    ),
                );
            });
            return {
                input: await sharp(svg)
                    .resize(tileSize, tileSize)
                    .png()
                    .toBuffer(),
                left: (index % columns) * tileSize,
                top: Math.floor(index / columns) * tileSize,
            };
        }),
    );
    await sharp({
        create: {
            width: columns * tileSize,
            height: columns * tileSize,
            channels: 4,
            background: "#00000000",
        },
    })
        .composite(layers)
        .webp({ lossless: true })
        .toFile(resolve(output, `${start / perSheet}.webp`));
}

await writeFile(
    resolve(dataOutput, "emoji-assets.json"),
    JSON.stringify({ version: "17.0", columns, indices }) + "\n",
);
await writeFile(
    resolve(dataOutput, "emoji-catalog.json"),
    JSON.stringify(catalog) + "\n",
);
await writeFile(
    resolve(rustOutput, "reaction-emoji.txt"),
    all
        .map((entry) => unicode(entry.hexcode))
        .sort()
        .join("\n") + "\n",
);
await copyFile(
    resolve(dataDirectory, "LICENSE"),
    resolve(output, "EMOJIBASE-LICENSE.txt"),
);
await copyFile(
    resolve(dataDirectory, "LICENSE"),
    resolve(rustOutput, "EMOJIBASE-LICENSE.txt"),
);
await copyFile(
    resolve(notoDirectory, "svg/LICENSE"),
    resolve(output, "NOTO-LICENSE.txt"),
);
await copyFile(
    resolve(dataDirectory, "APACHE-LICENSE.txt"),
    resolve(output, "APACHE-LICENSE.txt"),
);
await copyFile(
    resolve(dataDirectory, "UNICODE-LICENSE.txt"),
    resolve(output, "UNICODE-LICENSE.txt"),
);
await copyFile(
    resolve(dataDirectory, "UNICODE-LICENSE.txt"),
    resolve(rustOutput, "UNICODE-LICENSE.txt"),
);
await copyFile(
    resolve(notoDirectory, "third_party/region-flags/LICENSE"),
    resolve(output, "FLAGS-LICENSE.txt"),
);
await copyFile(
    resolve(notoDirectory, "third_party/region-flags/AUTHORS"),
    resolve(output, "FLAGS-AUTHORS.txt"),
);
console.log(
    `Generated ${all.length} emoji in ${Math.ceil(all.length / perSheet)} sprite sheets`,
);
