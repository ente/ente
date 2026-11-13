export interface FriendProfile {
    avatarKeyVersion?: number;
    avatarObjectID?: string;
    avatarSize?: number;
    avatarUpdatedAt?: string;
    avatarUrl?: string | null;
    coverUrl?: string | null;
    friendsCount: number;
    fullName: string;
    id: string;
    username: string;
    coverKeyVersion?: number;
    coverObjectID?: string;
    coverUpdatedAt?: string;
    spaceId?: string;
    spaceSlug?: string;
}
