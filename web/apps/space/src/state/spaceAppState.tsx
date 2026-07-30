import type { FriendProfile } from "data/friends";
import React, { createContext, useContext } from "react";
import type { SpaceLoginCredentials } from "screens/LoginScreen";
import type {
    SetupProfile,
    SetupProfileDetails,
} from "screens/SetupProfileScreen";
import type { SpacePost } from "services/space";
import type { PendingSpacePasskeyVerification } from "services/spacePasskeyVerification";
import type { CreateProfileSource } from "utils/spaceRoutes";

export type OnboardingEntrySource = "direct" | "add-friend-link";
export type SpaceProfileLoadStatus = "error" | "loading" | "ready";
export type PendingCreateProfile = SetupProfileDetails & {
    source: CreateProfileSource;
};

export interface RefreshSpaceProfileOptions {
    throwOnError?: boolean;
}

export interface PendingSpaceFeedPost {
    avatarUrl?: string | null;
    caption?: string;
    friendID: string;
    height?: number;
    id: string;
    imageUrl: string;
    name: string;
    spaceId: string;
    status: "pending";
    timestampMs: number;
    width?: number;
}

export type FailedSpaceFeedPost = Omit<PendingSpaceFeedPost, "status"> & {
    reason?: "post-limit";
    status: "failed";
};

export interface PostedSpaceFeedPost {
    id: string;
    post: SpacePost;
    status: "posted";
}

export interface ReadySpaceFeedPost {
    id: string;
    post: SpacePost;
    status: "ready";
}

export type LocalSpaceFeedPost =
    | FailedSpaceFeedPost
    | PendingSpaceFeedPost
    | PostedSpaceFeedPost
    | ReadySpaceFeedPost;

export interface SpaceAppState {
    friends: FriendProfile[];
    isLiveSignupVerification: boolean;
    localFeedPosts: LocalSpaceFeedPost[];
    onboardingEntrySource: OnboardingEntrySource;
    pendingLoginCredentials: SpaceLoginCredentials | null;
    pendingPasskeyVerification: PendingSpacePasskeyVerification | null;
    pendingProfileAvatarFile: File | null;
    pendingProfileCoverFile: File | null;
    pendingCreateProfile: PendingCreateProfile | null;
    profile: SetupProfile | null;
    profileLoadError?: string;
    profileLoadStatus: SpaceProfileLoadStatus;
    skipNextHomeFeedSkeleton: boolean;
    signupEmail: string;
    refreshProfile: (
        options?: RefreshSpaceProfileOptions,
    ) => Promise<SetupProfile | null>;
    resetAfterLogout: () => void;
    setFriends: React.Dispatch<React.SetStateAction<FriendProfile[]>>;
    setIsLiveSignupVerification: React.Dispatch<React.SetStateAction<boolean>>;
    setLocalFeedPosts: React.Dispatch<
        React.SetStateAction<LocalSpaceFeedPost[]>
    >;
    setOnboardingEntrySource: React.Dispatch<
        React.SetStateAction<OnboardingEntrySource>
    >;
    setPendingLoginCredentials: React.Dispatch<
        React.SetStateAction<SpaceLoginCredentials | null>
    >;
    setPendingPasskeyVerification: React.Dispatch<
        React.SetStateAction<PendingSpacePasskeyVerification | null>
    >;
    setPendingProfileAvatarFile: React.Dispatch<
        React.SetStateAction<File | null>
    >;
    setPendingProfileCoverFile: React.Dispatch<
        React.SetStateAction<File | null>
    >;
    setPendingCreateProfile: React.Dispatch<
        React.SetStateAction<PendingCreateProfile | null>
    >;
    setProfile: (profile: SetupProfile | null) => void;
    setSkipNextHomeFeedSkeleton: React.Dispatch<React.SetStateAction<boolean>>;
    setSignupEmail: React.Dispatch<React.SetStateAction<string>>;
}

export const initialFriends = (): FriendProfile[] => [];

export const SpaceAppStateContext = createContext<SpaceAppState | null>(null);

export const useSpaceAppState = () => {
    const context = useContext(SpaceAppStateContext);
    if (!context) {
        throw new Error(
            "useSpaceAppState must be used within SpaceAppStateProvider",
        );
    }
    return context;
};
