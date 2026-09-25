import { reactionEmojis } from "ente-space-wasm";
import { beforeAll, describe, expect, it } from "vitest";
import type { EmojiEntry } from "../src/utils/emoji";
import { emojiKey, findEmoji, sameEmoji } from "../src/utils/emoji";

let catalog: EmojiEntry[];
beforeAll(async () => {
    catalog = await reactionEmojis();
});

describe("emoji catalog interoperability", () => {
    it("includes the full emoji set and skin tone variants", () => {
        const entries = catalog.flatMap((entry) => [entry, ...entry.skins]);
        expect(entries).toHaveLength(3944);
        expect(new Set(entries.map(({ emoji }) => emojiKey(emoji))).size).toBe(
            entries.length,
        );
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
            findEmoji(catalog, "+1", 0, 0).some(({ emoji }) =>
                sameEmoji(emoji, "👍"),
            ),
        ).toBe(true);
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
            findEmoji(catalog, "❤️", 0, 3).map((entry) => entry.emoji),
        ).toContain("❤️");
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

    it("offers each tone pair for people with different skin tones", () => {
        for (const [emoji, variant] of [
            ["🤝", "🫱🏻‍🫲🏿"],
            ["👯", "🧑🏻‍🐰‍🧑🏿"],
            ["🤼", "🧑🏻‍🫯‍🧑🏿"],
        ]) {
            const entry = catalog.find((entry) => entry.emoji === emoji)!;
            expect(entry.skins).toHaveLength(25);
            expect(entry.skins.some((skin) => skin.emoji === variant)).toBe(
                true,
            );
        }
    });
});
