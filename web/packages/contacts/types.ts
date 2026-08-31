export interface WrappedRootContactKey {
    encryptedKey: string;
    header: string;
}

export interface ContactDisplayRecord {
    contactId: string;
    contactUserId: number;
    resolvedEmail: string | undefined;
    displayName: string | undefined;
    profilePictureAttachmentID: string | undefined;
    updatedAt: number;
}

export interface ContactLookup {
    userID?: number;
    email?: string;
}

export interface ContactsDisplaySnapshot {
    isHydrated: boolean;
    recordsByUserID: ReadonlyMap<number, ContactDisplayRecord>;
    recordsByEmail: ReadonlyMap<string, ContactDisplayRecord>;
    avatarURLsByContactID: ReadonlyMap<string, string>;
}

export interface ResolvedContactDisplay {
    contactId: string | undefined;
    profilePictureAttachmentID: string | undefined;
    primaryLabel: string;
    actualEmail: string | undefined;
    initial: string;
    source: "contact" | "fallback";
}

export interface ResolvedContactAvatar extends ResolvedContactDisplay {
    avatarURL: string | undefined;
}
