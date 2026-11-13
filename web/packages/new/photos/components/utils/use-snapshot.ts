import {
    hlsGenerationStatusSnapshot,
    hlsGenerationStatusSubscribe,
} from "ente-gallery/services/video";
import { useSyncExternalStore } from "react";
import { appLockSnapshot, appLockSubscribe } from "../../services/app-lock";
import {
    mlStatusSnapshot,
    mlStatusSubscribe,
    peopleStateSnapshot,
    peopleStateSubscribe,
} from "../../services/ml";
import { settingsSnapshot, settingsSubscribe } from "../../services/settings";
import {
    userDetailsSnapshot,
    userDetailsSubscribe,
} from "../../services/user-details";

export const useAppLockSnapshot = () =>
    useSyncExternalStore(appLockSubscribe, appLockSnapshot, appLockSnapshot);

export const useSettingsSnapshot = () =>
    useSyncExternalStore(settingsSubscribe, settingsSnapshot);

export const useUserDetailsSnapshot = () =>
    useSyncExternalStore(userDetailsSubscribe, userDetailsSnapshot);

export const useMLStatusSnapshot = () =>
    useSyncExternalStore(mlStatusSubscribe, mlStatusSnapshot);

export const usePeopleStateSnapshot = () =>
    useSyncExternalStore(peopleStateSubscribe, peopleStateSnapshot);

export const useHLSGenerationStatusSnapshot = () =>
    useSyncExternalStore(
        hlsGenerationStatusSubscribe,
        hlsGenerationStatusSnapshot,
    );
