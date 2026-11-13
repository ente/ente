import type {
    ContactLookup,
    ContactsDisplaySnapshot,
    ResolvedContactDisplay,
} from "./types";

export const normalizeEmail = (email?: string | null) =>
    email?.trim().toLowerCase();

export const knownEmailOrUndefined = (email?: string | null) => {
    const trimmed = email?.trim();
    return trimmed ? trimmed : undefined;
};

const contactRecordForLookup = (
    snapshot: ContactsDisplaySnapshot,
    lookup: ContactLookup,
) => {
    if (lookup.userID !== undefined) {
        const byUserID = snapshot.recordsByUserID.get(lookup.userID);
        if (byUserID) return byUserID;
    }

    const normalizedEmail = normalizeEmail(lookup.email);
    return normalizedEmail
        ? snapshot.recordsByEmail.get(normalizedEmail)
        : undefined;
};

export const resolveContactDisplayFromSnapshot = (
    snapshot: ContactsDisplaySnapshot,
    lookup: ContactLookup,
): ResolvedContactDisplay => {
    const matched = contactRecordForLookup(snapshot, lookup);
    const actualEmail =
        matched?.resolvedEmail ?? knownEmailOrUndefined(lookup.email);
    const primaryLabel = matched?.displayName ?? actualEmail ?? "";
    const initialSource = primaryLabel || actualEmail || "?";

    return {
        contactId: matched?.contactId,
        profilePictureAttachmentID: matched?.profilePictureAttachmentID,
        primaryLabel,
        actualEmail,
        initial: initialSource[0]?.toUpperCase() ?? "?",
        source: matched ? "contact" : "fallback",
    };
};
