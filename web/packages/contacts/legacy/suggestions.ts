import type { LegacySuggestedUser } from "./types";

export const mergeLegacySuggestedUsers = (
    ...groups: (LegacySuggestedUser[] | undefined)[]
): LegacySuggestedUser[] => {
    const byEmail = new Map<string, LegacySuggestedUser>();

    for (const group of groups) {
        for (const user of group ?? []) {
            const email = user.email.trim();
            if (!email) {
                continue;
            }
            byEmail.set(email.toLowerCase(), { id: user.id, email });
        }
    }

    return [...byEmail.values()].sort((a, b) =>
        a.email.localeCompare(b.email, undefined, { sensitivity: "base" }),
    );
};
