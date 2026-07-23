export interface PendingSpaceInvite {
    spaceId?: string;
    spaceUsername: string;
}

export interface SpaceInviteFriendSummary {
    fullName: string;
    username: string;
}

const pendingSpaceInviteFriendKey = "spacePendingInviteFriend";
const pendingSpaceInviteKey = "spacePendingInvite";
let sentSpaceInviteFriend: SpaceInviteFriendSummary | undefined;

const isPendingSpaceInvite = (value: unknown): value is PendingSpaceInvite => {
    if (!value || typeof value != "object") return false;
    const candidate = value as Record<string, unknown>;
    if (
        typeof candidate.spaceUsername != "string" ||
        candidate.spaceUsername.trim().length == 0
    ) {
        return false;
    }
    return (
        candidate.spaceId == undefined || typeof candidate.spaceId == "string"
    );
};

const isSpaceInviteFriendSummary = (
    value: unknown,
): value is SpaceInviteFriendSummary => {
    if (!value || typeof value != "object") return false;
    const candidate = value as Record<string, unknown>;
    return (
        typeof candidate.fullName == "string" &&
        typeof candidate.username == "string" &&
        (candidate.fullName.trim().length > 0 ||
            candidate.username.trim().length > 0)
    );
};

const savedSpaceInviteFriendSummary = (key: string) => {
    const saved = sessionStorage.getItem(key);
    if (!saved) return undefined;

    try {
        const parsed: unknown = JSON.parse(saved);
        return isSpaceInviteFriendSummary(parsed) ? parsed : undefined;
    } catch {
        return undefined;
    }
};

const saveSpaceInviteFriendSummary = (
    key: string,
    friend: SpaceInviteFriendSummary,
) => {
    sessionStorage.setItem(key, JSON.stringify(friend));
};

export const savePendingSpaceInvite = (invite: PendingSpaceInvite) => {
    sessionStorage.setItem(pendingSpaceInviteKey, JSON.stringify(invite));
};

export const savedPendingSpaceInvite = () => {
    const saved = sessionStorage.getItem(pendingSpaceInviteKey);
    if (!saved) return undefined;

    try {
        const parsed: unknown = JSON.parse(saved);
        return isPendingSpaceInvite(parsed) ? parsed : undefined;
    } catch {
        return undefined;
    }
};

export const clearPendingSpaceInvite = () => {
    sessionStorage.removeItem(pendingSpaceInviteKey);
};

export const savePendingSpaceInviteFriend = (
    friend: SpaceInviteFriendSummary,
) => saveSpaceInviteFriendSummary(pendingSpaceInviteFriendKey, friend);

export const savedPendingSpaceInviteFriend = () =>
    savedSpaceInviteFriendSummary(pendingSpaceInviteFriendKey);

export const clearPendingSpaceInviteFriend = () => {
    sessionStorage.removeItem(pendingSpaceInviteFriendKey);
};

export const saveSentSpaceInviteFriend = (friend: SpaceInviteFriendSummary) => {
    sentSpaceInviteFriend = friend;
};

export const consumeSentSpaceInviteFriend = () => {
    const friend = sentSpaceInviteFriend;
    sentSpaceInviteFriend = undefined;
    return friend;
};

export const spaceInviteFromLocation = (): PendingSpaceInvite | null => {
    const match = /^\/([^/]+)\/?$/.exec(window.location.pathname);
    if (!match || window.location.hash.trim()) return null;

    try {
        const spaceUsername = decodeURIComponent(match[1] ?? "").trim();
        return spaceUsername ? { spaceUsername } : null;
    } catch {
        return null;
    }
};

export const spaceInviteURL = ({ spaceUsername }: PendingSpaceInvite) =>
    `${window.location.origin}/${encodeURIComponent(spaceUsername)}`;
