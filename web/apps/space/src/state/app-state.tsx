import type { FriendProfile } from "data/friends";
import React, { createContext, useContext } from "react";
import type { SpaceLoginCredentials } from "screens/LoginScreen";
import type {
    SetupProfile,
    SetupProfileDetails,
} from "screens/SetupProfileScreen";
import type { PendingSpacePasskeyVerification } from "services/passkey-verification";
import type { SpacePost } from "services/space";
import type { SpaceDraftPostImage } from "utils/post-image";
import type { CreateProfileSource } from "utils/routes";

export type OnboardingEntrySource = "direct" | "add-friend-link";
export type SpaceProfileLoadStatus = "error" | "loading" | "ready";
export type SpacePostPublishPhase = "failed" | "posted" | "posting";
export interface SpacePostPublication {
    phase: SpacePostPublishPhase;
    post: SpacePost;
    previewUrl: string;
}
export type PendingCreateProfile = SetupProfileDetails & {
    source: CreateProfileSource;
};

export interface RefreshSpaceProfileOptions {
    throwOnError?: boolean;
}

export interface SpaceAppState {
    cachedProfileAvatarUrl?: string;
    friends: FriendProfile[];
    isLiveSignupVerification: boolean;
    onboardingEntrySource: OnboardingEntrySource;
    pendingLoginCredentials: SpaceLoginCredentials | null;
    pendingPasskeyVerification: PendingSpacePasskeyVerification | null;
    pendingPostPhotoFile: File | null;
    pendingProfileAvatarFile: File | null;
    pendingProfileCoverFile: File | null;
    pendingCreateProfile: PendingCreateProfile | null;
    profile: SetupProfile | null;
    profileLoadError?: string;
    profileLoadStatus: SpaceProfileLoadStatus;
    postPublication: SpacePostPublication | null;
    signupEmail: string;
    setPostPublication: React.Dispatch<
        React.SetStateAction<SpacePostPublication | null>
    >;
    publishPost: (
        image: SpaceDraftPostImage,
        caption: string,
    ) => Promise<SpacePost>;
    refreshProfile: (
        options?: RefreshSpaceProfileOptions,
    ) => Promise<SetupProfile | null>;
    resetAfterLogout: () => void;
    setFriends: React.Dispatch<React.SetStateAction<FriendProfile[]>>;
    setIsLiveSignupVerification: React.Dispatch<React.SetStateAction<boolean>>;
    setOnboardingEntrySource: React.Dispatch<
        React.SetStateAction<OnboardingEntrySource>
    >;
    setPendingLoginCredentials: React.Dispatch<
        React.SetStateAction<SpaceLoginCredentials | null>
    >;
    setPendingPasskeyVerification: React.Dispatch<
        React.SetStateAction<PendingSpacePasskeyVerification | null>
    >;
    setPendingPostPhotoFile: React.Dispatch<React.SetStateAction<File | null>>;
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
