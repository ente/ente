export const spaceMessageTextMaxLength = 1000;

export const clampSpaceMessageText = (text: string) =>
    Array.from(text).slice(0, spaceMessageTextMaxLength).join("");

export const normalizeSpaceMessageText = (text: string) => {
    const trimmed = text.trim();
    if (Array.from(trimmed).length > spaceMessageTextMaxLength) {
        throw new Error(
            `Message must be ${spaceMessageTextMaxLength} characters or less.`,
        );
    }
    return trimmed;
};
