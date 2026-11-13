import log from "ente-base/log";
import {
    updateChecksumProtectedUploadsEnabled,
    updateShouldDisableCFUploadProxy,
} from "ente-gallery/services/upload";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";
import {
    fetchFeatureFlags,
    updateRemoteFlag,
    updateRemoteValue,
} from "./remote-store";

export interface Settings {
    isInternalUser: boolean;
    deferredMultipartChecksumsEnabled: boolean;
    previewUploadV2Enabled: boolean;
    mapEnabled: boolean;
    cfUploadProxyDisabled: boolean;
    castURL: string;
    embedURL: string;
    customDomain?: string;
    customDomainCNAME: string;
}

const createDefaultSettings = (): Settings => ({
    isInternalUser: false,
    deferredMultipartChecksumsEnabled: false,
    previewUploadV2Enabled: false,
    mapEnabled: false,
    cfUploadProxyDisabled: false,
    castURL: "https://cast.ente.com",
    embedURL: "https://embed.ente.com",
    customDomainCNAME: "my.ente.com",
});

class SettingsState {
    constructor() {
        this.settingsSnapshot = createDefaultSettings();
    }

    settingsListeners: (() => void)[] = [];
    settingsSnapshot: Settings;
}

let _state = new SettingsState();

export const initSettings = () => {
    void updateShouldDisableCFUploadProxy(savedCFProxyDisabled());
    syncSettingsSnapshotWithLocalStorage();
};

export const logoutSettings = () => {
    _state = new SettingsState();
    updateChecksumProtectedUploadsEnabled(false);
};

export const pullSettings = async () => {
    const jsonString = await fetchFeatureFlags().then((res) => res.text());
    FeatureFlags.parse(JSON.parse(jsonString));
    saveRemoteFeatureFlagsJSONString(jsonString);
    syncSettingsSnapshotWithLocalStorage();
};

const saveRemoteFeatureFlagsJSONString = (s: string) =>
    localStorage.setItem("remoteFeatureFlags", s);

const savedRemoteFeatureFlags = () => {
    const s = localStorage.getItem("remoteFeatureFlags");
    if (!s) return undefined;
    try {
        return FeatureFlags.parse(JSON.parse(s));
    } catch (e) {
        log.warn("Ignoring unparseable saved remoteFeatureFlags", e);
        return undefined;
    }
};

const FeatureFlags = z.object({
    internalUser: z.boolean().nullish().transform(nullToUndefined),
    betaUser: z.boolean().nullish().transform(nullToUndefined),
    mapEnabled: z.boolean().nullish().transform(nullToUndefined),
    serverApiFlag: z.number().nullish().transform(nullToUndefined),
    castUrl: z.string().nullish().transform(nullToUndefined),
    embedUrl: z.string().nullish().transform(nullToUndefined),
    customDomain: z.string().nullish().transform(nullToUndefined),
    customDomainCNAME: z.string().nullish().transform(nullToUndefined),
});

type FeatureFlags = z.infer<typeof FeatureFlags>;

const deferredMultipartChecksumsFlag = 1 << 6;
const previewUploadV2Flag = 1 << 8;

const syncSettingsSnapshotWithLocalStorage = () => {
    const flags = savedRemoteFeatureFlags();
    const settings = createDefaultSettings();
    settings.isInternalUser = flags?.internalUser || false;
    settings.deferredMultipartChecksumsEnabled = !!(
        (flags?.serverApiFlag ?? 0) & deferredMultipartChecksumsFlag
    );
    settings.previewUploadV2Enabled = !!(
        (flags?.serverApiFlag ?? 0) & previewUploadV2Flag
    );
    settings.mapEnabled = flags?.mapEnabled || false;
    settings.cfUploadProxyDisabled = savedCFProxyDisabled();
    if (flags?.castUrl) settings.castURL = flags.castUrl;
    if (flags?.embedUrl) settings.embedURL = flags.embedUrl;
    if (flags?.customDomain) settings.customDomain = flags.customDomain;
    if (flags?.customDomainCNAME)
        settings.customDomainCNAME = flags.customDomainCNAME;
    updateChecksumProtectedUploadsEnabled(true);
    setSettingsSnapshot(settings);
};

export const settingsSubscribe = (onChange: () => void): (() => void) => {
    _state.settingsListeners.push(onChange);
    return () => {
        _state.settingsListeners = _state.settingsListeners.filter(
            (l) => l != onChange,
        );
    };
};

export const settingsSnapshot = () => _state.settingsSnapshot;

const setSettingsSnapshot = (snapshot: Settings) => {
    _state.settingsSnapshot = snapshot;
    _state.settingsListeners.forEach((l) => l());
};

export const updateCustomDomain = async (customDomain: string) => {
    await updateRemoteValue("customDomain", customDomain);
    return pullSettings();
};

export const updateMapEnabled = async (isEnabled: boolean) => {
    const previousSnapshot = _state.settingsSnapshot;

    setSettingsSnapshot({ ...previousSnapshot, mapEnabled: isEnabled });

    try {
        await updateRemoteFlag("mapEnabled", isEnabled);
        await pullSettings();
    } catch (e) {
        log.error("Failed to update map setting", e);
        setSettingsSnapshot(previousSnapshot);
        throw e;
    }
};

const cfProxyDisabledKey = "cfProxyDisabled";

const saveCFProxyDisabled = (v: boolean) =>
    v
        ? localStorage.setItem(cfProxyDisabledKey, "1")
        : localStorage.removeItem(cfProxyDisabledKey);

const savedCFProxyDisabled = () => {
    const v = localStorage.getItem(cfProxyDisabledKey);
    if (!v) return false;
    if (v == "1") return true;

    // Migrate the legacy { value: boolean } encoding.
    try {
        const value = z
            .object({ value: z.boolean() })
            .parse(JSON.parse(v)).value;
        saveCFProxyDisabled(value);
        return value;
    } catch (e) {
        log.warn(`Ignoring ${cfProxyDisabledKey} value: ${v}`, e);
        localStorage.removeItem(cfProxyDisabledKey);
        return false;
    }
};

export const updateCFProxyDisabledPreference = async (value: boolean) => {
    saveCFProxyDisabled(value);
    await updateShouldDisableCFUploadProxy(value);
    syncSettingsSnapshotWithLocalStorage();
};
