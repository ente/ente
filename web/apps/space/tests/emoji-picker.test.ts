import { describe, expect, test } from "vitest";
import {
    emojiName,
    emojiWithSkinTone,
    quickReactionEmojis,
    searchEmojis,
    spaceEmojis,
} from "../src/data/emojis";

describe("quick reactions", () => {
    test("keeps the defaults when no reaction is selected", () => {
        expect(quickReactionEmojis()).toEqual([
            "❤️",
            "😂",
            "😮",
            "😢",
            "🙏",
            "👍",
        ]);
    });

    test.each(["❤️", "😂", "😮", "😢", "🙏", "👍"])(
        "keeps selected default %s in its usual slot",
        (selected) => {
            expect(quickReactionEmojis(selected)).toEqual([
                "❤️",
                "😂",
                "😮",
                "😢",
                "🙏",
                "👍",
            ]);
        },
    );

    test.each(["🔥", "🪿"])(
        "includes a selected %s outside the defaults",
        (selected) => {
            expect(quickReactionEmojis(selected)).toEqual([
                "❤️",
                "😂",
                "😮",
                "😢",
                "🙏",
                selected,
            ]);
        },
    );

    test("preserves skin tones and the selected variant's usual slot", () => {
        expect(quickReactionEmojis("🙏🏽")).toEqual([
            "❤️",
            "😂",
            "😮",
            "😢",
            "🙏🏽",
            "👍🏽",
        ]);
    });
});

describe("emoji search", () => {
    test("finds aliases, multiple words and literal toned emoji", () => {
        expect(
            searchEmojis(spaceEmojis, " LOL ").map((item) => item.emoji),
        ).toContain("😂");
        expect(
            searchEmojis(spaceEmojis, "blue heart").map((item) => item.emoji),
        ).toEqual(["💙", "🩵"]);
        expect(
            searchEmojis(spaceEmojis, "👍🏽").map((item) => item.emoji),
        ).toEqual(["👍"]);
        expect(searchEmojis(spaceEmojis, "no-such-emoji")).toEqual([]);
    });

    test("inserts tones before joined professions and drops the text selector", () => {
        const peace = spaceEmojis.find((entry) => entry.emoji == "✌️")!;
        const developer = spaceEmojis.find((entry) => entry.emoji == "🧑‍💻")!;
        expect(emojiWithSkinTone(peace, "🏽")).toBe("✌🏽");
        expect(emojiWithSkinTone(developer, "🏿")).toBe("🧑🏿‍💻");
        expect(emojiName("🧑🏿‍💻")).toBe("Developer");
        expect(
            emojiWithSkinTone(
                spaceEmojis.find((entry) => entry.emoji == "❤️")!,
                "🏽",
            ),
        ).toBe("❤️");
    });

    test("catalog entries and all tone variants contain a single grapheme", () => {
        const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
        expect(new Set(spaceEmojis.map((entry) => entry.emoji)).size).toBe(
            spaceEmojis.length,
        );
        for (const entry of spaceEmojis) {
            for (const tone of ["", "🏻", "🏼", "🏽", "🏾", "🏿"]) {
                expect(
                    [...segmenter.segment(emojiWithSkinTone(entry, tone))],
                    entry.name,
                ).toHaveLength(1);
            }
        }
    });
});
