export interface PendingSpacePasskeyVerification {
    hasTwoFactorFallback: boolean;
    passkeySessionID: string;
    url: string;
}

const pendingSpacePasskeyVerificationKey = "spacePendingPasskeyVerification";
const autoOpenedSpacePasskeyPrefix = "spacePasskeyAutoOpened:";

const isPendingSpacePasskeyVerification = (
    value: unknown,
): value is PendingSpacePasskeyVerification => {
    if (!value || typeof value != "object") return false;
    const candidate = value as Record<string, unknown>;
    return (
        typeof candidate.hasTwoFactorFallback == "boolean" &&
        typeof candidate.passkeySessionID == "string" &&
        typeof candidate.url == "string"
    );
};

export const savePendingSpacePasskeyVerification = (
    verification: PendingSpacePasskeyVerification,
) => {
    sessionStorage.setItem(
        pendingSpacePasskeyVerificationKey,
        JSON.stringify(verification),
    );
};

export const savedPendingSpacePasskeyVerification = () => {
    const saved = sessionStorage.getItem(pendingSpacePasskeyVerificationKey);
    if (!saved) return undefined;

    try {
        const parsed: unknown = JSON.parse(saved);
        return isPendingSpacePasskeyVerification(parsed) ? parsed : undefined;
    } catch {
        return undefined;
    }
};

export const clearPendingSpacePasskeyVerification = () => {
    sessionStorage.removeItem(pendingSpacePasskeyVerificationKey);
};

const autoOpenedSpacePasskeyKey = (passkeySessionID: string) =>
    `${autoOpenedSpacePasskeyPrefix}${passkeySessionID}`;

export const hasAutoOpenedSpacePasskeyVerification = (
    passkeySessionID: string,
) => sessionStorage.getItem(autoOpenedSpacePasskeyKey(passkeySessionID)) == "1";

export const markAutoOpenedSpacePasskeyVerification = (
    passkeySessionID: string,
) => {
    sessionStorage.setItem(autoOpenedSpacePasskeyKey(passkeySessionID), "1");
};
