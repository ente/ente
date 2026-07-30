export interface SpaceProfilePayload {
    displayName?: unknown;
    fullName?: unknown;
    username?: unknown;
}

export const parseSpaceProfilePayload = (
    profile: string,
): SpaceProfilePayload => {
    const trimmed = profile.trim();
    if (!trimmed) return {};
    try {
        const parsed: unknown = JSON.parse(trimmed);
        if (parsed && typeof parsed == "object" && !Array.isArray(parsed)) {
            return parsed;
        }
    } catch {
        // Fall through to the empty profile.
    }
    return {};
};

export const spaceProfileTextField = (value: unknown) =>
    typeof value == "string" ? value.trim() : "";

export const blobPartForBytes = (bytes: Uint8Array): ArrayBuffer => {
    const copy = new Uint8Array(bytes.byteLength);
    copy.set(bytes);
    return copy.buffer;
};
