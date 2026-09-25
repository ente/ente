import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import assets from "../src/data/emoji-assets.json";
import catalog from "../src/data/emoji-catalog.json";
import {
    emojiForTone,
    emojiKey,
    findEmoji,
    sameEmoji,
} from "../src/utils/emoji";

describe("emoji catalog interoperability", () => {
    it("covers every picker variant in Rust validation and local artwork", () => {
        const rustCatalog = new Set(
            readFileSync(
                new URL(
                    "../../../../rust/crates/space/data/reaction-emoji.txt",
                    import.meta.url,
                ),
                "utf8",
            )
                .trim()
                .split("\n"),
        );
        const entries = catalog.flatMap((entry) => [
            entry,
            ...(entry.skins ?? []),
        ]);
        expect(entries).toHaveLength(3944);
        expect(rustCatalog.size).toBe(entries.length);
        const indices: Record<string, number> = assets.indices;
        for (const { emoji } of entries) {
            expect(rustCatalog.has(emoji), emoji).toBe(true);
            expect(indices[emojiKey(emoji)], emoji).toBeTypeOf("number");
        }
    });

    it("treats optional emoji presentation selectors as the same reaction", () => {
        expect(sameEmoji("❤", "❤️")).toBe(true);
        expect(sameEmoji("👍️", "👍")).toBe(true);
        expect(sameEmoji("👍", "👍🏽")).toBe(false);
        expect(sameEmoji("👩‍💻", "👨‍💻")).toBe(false);
    });
});

describe("emoji picker search and tones", () => {
    it("searches names and keywords across categories", () => {
        expect(
            findEmoji(catalog, "  ROCKET ", 0, 0).map((entry) => entry.emoji),
        ).toContain("🚀");
        expect(
            findEmoji(catalog, "+1", 0, 0).map((entry) => entry.emoji),
        ).toContain("👍");
        expect(
            findEmoji(catalog, "red heart", 0, 0).map((entry) => entry.emoji),
        ).toContain("❤️");
        expect(findEmoji(catalog, "not-an-emoji-name", 0, 0)).toEqual([]);
    });

    it("selects supported tones without modifying unrelated emoji", () => {
        expect(
            findEmoji(catalog, "👍", 0, 3).map((entry) => entry.emoji),
        ).toContain("👍🏽");
        expect(
            emojiForTone(catalog.find((entry) => entry.emoji === "👍")!, 3)
                .emoji,
        ).toBe("👍🏽");
        expect(
            emojiForTone(catalog.find((entry) => entry.emoji === "❤️")!, 3)
                .emoji,
        ).toBe("❤️");
        expect(
            findEmoji(catalog, "", 4, 3).every((entry) =>
                catalog.some(
                    (base) => base.emoji === entry.emoji && base.group === 4,
                ),
            ),
        ).toBe(true);
    });

    it("finds mixed tones and complete ZWJ, flag and keycap sequences", () => {
        for (const emoji of ["🫱🏻‍🫲🏿", "👩🏽‍💻", "🇮🇳", "1️⃣", "👨‍👩‍👧‍👦"]) {
            expect(
                findEmoji(catalog, emoji, 0, 0).some(
                    (entry) => entry.emoji === emoji,
                ),
                emoji,
            ).toBe(true);
        }
        expect(
            findEmoji(catalog, "handshake", 0, -1).some(
                (entry) => entry.emoji === "🫱🏻‍🫲🏿",
            ),
        ).toBe(true);
        expect(
            findEmoji(catalog, "medium skin tone", 0, 0).some(
                (entry) => entry.emoji === "👍🏽",
            ),
        ).toBe(true);
    });
});
