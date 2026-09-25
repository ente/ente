import type { ReactionEmoji } from "ente-space-wasm";

export const emojiKey = (emoji: string) =>
    Array.from(emoji)
        .filter((part) => part !== "\uFE0F")
        .map((part) => part.codePointAt(0)!.toString(16).padStart(4, "0"))
        .join("-");

export const sameEmoji = (first: string | undefined, second: string) =>
    first !== undefined && emojiKey(first) === emojiKey(second);

export type EmojiEntry = ReactionEmoji;

const emojiForTone = (entry: EmojiEntry, tone: number) =>
    entry.skins.find((skin) => skin.tone.every((value) => value === tone)) ??
    entry;

const searchText = (text: string) =>
    text.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();

export const findEmoji = (
    catalog: EmojiEntry[],
    query: string,
    group: number,
    tone: number,
) => {
    const terms = searchText(query.trim()).split(/\s+/u).filter(Boolean);
    return catalog.flatMap((entry) => {
        const choices =
            tone === -1 ? [entry, ...entry.skins] : [emojiForTone(entry, tone)];
        if (!terms.length) return entry.group === group ? choices : [];
        if (sameEmoji(entry.emoji, query.trim())) return choices;
        const matches = (variant: { emoji: string; name: string }) => {
            const haystack = searchText(
                [variant.name, ...entry.tags].join(" "),
            );
            return (
                sameEmoji(variant.emoji, query.trim()) ||
                terms.every((term) => haystack.includes(term))
            );
        };
        const selected = choices.filter(matches);
        return selected.length ? selected : entry.skins.filter(matches);
    });
};
