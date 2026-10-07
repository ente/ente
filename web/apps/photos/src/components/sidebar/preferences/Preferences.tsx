import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { Divider, Link, Stack, TextField, useColorScheme } from "@mui/material";
import Typography from "@mui/material/Typography";
import { isDesktop } from "ente-base/app";
import {
    RowButton,
    RowButtonEndActivityIndicator,
    RowButtonGroup,
    RowButtonGroupHint,
    RowSwitch,
} from "ente-base/components/RowButton";
import { SpacedRow } from "ente-base/components/containers";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { isHTTPErrorWithStatus } from "ente-base/http";
import {
    getLocaleInUse,
    setLocaleInUse,
    supportedLocales,
    ut,
    type SupportedLocale,
} from "ente-base/i18n";
import log from "ente-base/log";
import {
    isHLSGenerationSupported,
    toggleHLSGeneration,
} from "ente-gallery/services/video";
import {
    useAppLockSnapshot,
    useHLSGenerationStatusSnapshot,
    useSettingsSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import { suppressAppLockRefreshFromSessionForTrustedReload } from "ente-new/photos/services/app-lock";
import { isMLSupported } from "ente-new/photos/services/ml";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import {
    pullSettings,
    updateCFProxyDisabledPreference,
    updateCustomDomain,
    updateMapEnabled,
} from "ente-new/photos/services/settings";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { Trans } from "react-i18next";
import { DropdownInput } from "../DropdownInput";
import { AppLockSettings } from "./AppLockSettings";
import { MLSettings } from "./MLSettings";

export type PreferencesAction = Extract<
    SidebarActionID,
    | "preferences.language"
    | "preferences.theme"
    | "preferences.customDomains"
    | "preferences.map"
    | "preferences.fasterUpload"
    | "preferences.openOnStartup"
    | "preferences.advanced"
    | "preferences.mlSearch"
    | "preferences.streamableVideos"
>;

const DesktopAppLockSettings: React.FC<
    { onAuthenticateUser: () => Promise<boolean> } & Pick<
        NestedSidebarDrawerVisibilityProps,
        "onRootClose"
    >
> = ({ onAuthenticateUser, onRootClose }) => {
    const appLock = useAppLockSnapshot();
    const { show, props } = useModalVisibility();

    const handleOpen = useCallback(async () => {
        try {
            if (!(await onAuthenticateUser())) return;
            show();
        } catch (error) {
            log.error("Failed to open app lock settings", error);
        }
    }, [onAuthenticateUser, show]);

    return (
        <>
            <RowButtonGroup>
                <RowButton
                    label={t("app_lock")}
                    caption={
                        !appLock.supported
                            ? t("app_lock_not_supported")
                            : undefined
                    }
                    disabled={!appLock.supported}
                    onClick={handleOpen}
                />
            </RowButtonGroup>
            <AppLockSettings {...props} onRootClose={onRootClose} />
        </>
    );
};

type PreferencesProps = NestedSidebarDrawerVisibilityProps & {
    onAuthenticateUser: () => Promise<boolean>;
} & {
    pendingAction?: PreferencesAction;
    onActionHandled?: (action?: PreferencesAction) => void;
};

export const Preferences: React.FC<PreferencesProps> = ({
    open,
    onClose,
    onRootClose,
    onAuthenticateUser,
    pendingAction,
    onActionHandled,
}) => {
    const { show: showDomainSettings, props: domainSettingsVisibilityProps } =
        useModalVisibility();
    const {
        show: showAdvancedSettings,
        props: advancedSettingsVisibilityProps,
    } = useModalVisibility();
    const { show: showMLSettings, props: mlSettingsVisibilityProps } =
        useModalVisibility();

    const { mapEnabled } = useSettingsSnapshot();
    const [mapErrorMessage, setMapErrorMessage] = useState<string>();
    const handleToggleMap = useCallback(() => {
        setMapErrorMessage(undefined);
        void updateMapEnabled(!mapEnabled).catch(() => {
            setMapErrorMessage(t("generic_error"));
        });
    }, [mapEnabled]);

    const hlsGenStatusSnapshot = useHLSGenerationStatusSnapshot();
    const isHLSGenerationEnabled = !!hlsGenStatusSnapshot?.enabled;
    const hlsProcessedFraction = hlsGenStatusSnapshot?.enabled
        ? hlsGenStatusSnapshot.processedFraction
        : undefined;

    useEffect(() => {
        if (open) void pullSettings();
    }, [open]);

    useEffect(() => {
        if (!open || !pendingAction) return;
        switch (pendingAction) {
            case "preferences.customDomains":
                showDomainSettings();
                break;
            case "preferences.advanced":
            case "preferences.fasterUpload":
            case "preferences.openOnStartup":
                showAdvancedSettings();
                break;
            case "preferences.mlSearch":
                showMLSettings();
                break;
            case "preferences.map":
            case "preferences.language":
            case "preferences.theme":
            case "preferences.streamableVideos":
                break;
        }
        onActionHandled?.();
    }, [
        open,
        onActionHandled,
        pendingAction,
        showAdvancedSettings,
        showDomainSettings,
        showMLSettings,
    ]);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("preferences")}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>
                <LanguageSelector />
                <ThemeSelector />
                <Divider sx={{ my: "2px", opacity: 0.1 }} />
                {isMLSupported && (
                    <RowButtonGroup>
                        <RowButton
                            endIcon={<ChevronRightIcon />}
                            label={t("ml_search")}
                            onClick={showMLSettings}
                        />
                    </RowButtonGroup>
                )}
                <RowButton
                    label={t("custom_domains")}
                    endIcon={<ChevronRightIcon />}
                    onClick={showDomainSettings}
                />
                <Stack>
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("map")}
                            checked={mapEnabled}
                            onClick={handleToggleMap}
                        />
                    </RowButtonGroup>
                    <RowButtonGroupHint>
                        {t("maps_privacy_notice")}
                    </RowButtonGroupHint>
                    {mapErrorMessage && (
                        <Typography
                            variant="small"
                            sx={{ color: "critical.main", mt: 0.5 }}
                        >
                            {mapErrorMessage}
                        </Typography>
                    )}
                </Stack>
                <RowButton
                    endIcon={<ChevronRightIcon />}
                    label={t("advanced")}
                    onClick={showAdvancedSettings}
                />
                {isDesktop && (
                    <DesktopAppLockSettings
                        onAuthenticateUser={onAuthenticateUser}
                        onRootClose={onRootClose}
                    />
                )}
                {isHLSGenerationSupported && (
                    <Stack>
                        <RowButtonGroup>
                            <RowSwitch
                                label={t("streamable_videos")}
                                checked={isHLSGenerationEnabled}
                                onClick={() => void toggleHLSGeneration()}
                            />
                        </RowButtonGroup>
                        {isHLSGenerationEnabled && (
                            <SpacedRow sx={{ gap: 2, px: 2, pt: 2, pb: 1 }}>
                                <Typography sx={{ color: "text.faint" }}>
                                    {t("processed")}
                                </Typography>
                                {hlsProcessedFraction == undefined ? (
                                    <RowButtonEndActivityIndicator />
                                ) : (
                                    <Typography sx={{ textAlign: "right" }}>
                                        {t("percent_complete", {
                                            percent: hlsProcessedFraction * 100,
                                            formatParams: {
                                                percent: {
                                                    minimumFractionDigits:
                                                        hlsProcessedFraction ==
                                                        0
                                                            ? 0
                                                            : 2,
                                                    maximumFractionDigits: 2,
                                                    roundingMode: "trunc",
                                                },
                                            },
                                        })}
                                    </Typography>
                                )}
                            </SpacedRow>
                        )}
                    </Stack>
                )}
            </Stack>
            <DomainSettings
                {...domainSettingsVisibilityProps}
                onRootClose={onRootClose}
            />
            <AdvancedSettings
                {...advancedSettingsVisibilityProps}
                onRootClose={onRootClose}
            />
            <MLSettings
                {...mlSettingsVisibilityProps}
                onRootClose={handleRootClose}
            />
        </TitledNestedSidebarDrawer>
    );
};

const LanguageSelector = () => {
    const locale = getLocaleInUse();

    const updateCurrentLocale = (newLocale: SupportedLocale) => {
        if (newLocale === locale) return;

        void setLocaleInUse(newLocale).then(() => {
            // Global translations and cached formatters need a full reload.
            // Trust it so desktop app lock does not immediately lock again.
            if (globalThis.electron) {
                suppressAppLockRefreshFromSessionForTrustedReload();
            }
            window.location.reload();
        });
    };

    const options = supportedLocales.map((locale) => ({
        label: localeName(locale),
        value: locale,
    }));

    return (
        <Stack sx={{ gap: 1 }}>
            <Typography variant="small" sx={{ px: 1, color: "text.muted" }}>
                {t("language")}
            </Typography>
            <DropdownInput
                options={options}
                selected={locale}
                onSelect={updateCurrentLocale}
            />
        </Stack>
    );
};

const localeName = (locale: SupportedLocale) => {
    switch (locale) {
        case "en-US":
            return "English";
        case "fr-FR":
            return "Français";
        case "de-DE":
            return "Deutsch";
        case "ca-ES":
            return "Català";
        case "zh-CN":
            return "简体中文";
        case "zh-TW":
            return "繁體中文";
        case "nl-NL":
            return "Nederlands";
        case "es-ES":
            return "Español";
        case "pt-PT":
            return "Português";
        case "pt-BR":
            return "Português Brasileiro";
        case "ru-RU":
            return "Русский";
        case "pl-PL":
            return "Polski";
        case "it-IT":
            return "Italiano";
        case "lt-LT":
            return "Lietuvių kalba";
        case "uk-UA":
            return "Українська";
        case "ur-IN":
            return "اردو";
        case "vi-VN":
            return "Tiếng Việt";
        case "ja-JP":
            return "日本語";
        case "ar-SA":
            return "اَلْعَرَبِيَّةُ";
        case "tr-TR":
            return "Türkçe";
        case "cs-CZ":
            return "čeština";
        case "el-GR":
            return "Ελληνικά";
    }
};

const ThemeSelector = () => {
    const { mode, setMode } = useColorScheme();

    // MUI color mode is undefined during SSR.
    if (!mode) return null;

    return (
        <Stack sx={{ gap: 1 }}>
            <Typography variant="small" sx={{ px: 1, color: "text.muted" }}>
                {t("theme")}
            </Typography>
            <DropdownInput
                options={[
                    { label: t("system"), value: "system" },
                    { label: t("light"), value: "light" },
                    { label: t("dark"), value: "dark" },
                ]}
                selected={mode}
                onSelect={setMode}
            />
        </Stack>
    );
};

const DomainSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("custom_domains")}
            caption={t("custom_domains_desc")}
        >
            <DomainSettingsContents />
        </TitledNestedSidebarDrawer>
    );
};

// This component boundary resets form state on back navigation.
const DomainSettingsContents: React.FC = () => {
    const { customDomain, customDomainCNAME } = useSettingsSnapshot();

    const formik = useFormik({
        initialValues: { domain: customDomain ?? "" },
        onSubmit: async (values, { setFieldError }) => {
            const domain = values.domain;
            const setValueFieldError = (message: string) =>
                setFieldError("domain", message);

            try {
                await updateCustomDomain(domain);
            } catch (e) {
                log.error(`Failed to submit input ${domain}`, e);
                if (isHTTPErrorWithStatus(e, 400)) {
                    setValueFieldError(t("invalid_domain"));
                } else if (isHTTPErrorWithStatus(e, 402)) {
                    setValueFieldError(t("sharing_disabled_for_free_accounts"));
                } else if (isHTTPErrorWithStatus(e, 409)) {
                    setValueFieldError(t("already_linked_domain"));
                } else {
                    setValueFieldError(t("generic_error"));
                }
            }
        },
    });

    return (
        <Stack sx={{ px: 2, py: "12px" }}>
            <DomainItem title={t("link_your_domain")} ordinal={t("num_1")}>
                <form onSubmit={formik.handleSubmit}>
                    <TextField
                        name="domain"
                        value={formik.values.domain}
                        onChange={formik.handleChange}
                        type={"text"}
                        fullWidth
                        autoFocus={true}
                        margin="dense"
                        disabled={formik.isSubmitting}
                        error={!!formik.errors.domain}
                        helperText={formik.errors.domain ?? t("domain_help")}
                        label={t("domain")}
                        placeholder={ut("photos.example.org")}
                        sx={{ mb: 2 }}
                    />
                    <LoadingButton
                        fullWidth
                        type="submit"
                        loading={formik.isSubmitting}
                        color="accent"
                    >
                        {customDomain ? t("update") : t("save")}
                    </LoadingButton>
                </form>
            </DomainItem>
            <Divider sx={{ mt: 4, mb: 2, opacity: 0.5 }} />
            <DomainItem title={t("add_dns_entry")} ordinal={t("num_2")}>
                <Typography sx={{ color: "text.muted" }}>
                    <Trans
                        i18nKey="add_dns_entry_hint"
                        components={{
                            b: (
                                <Typography
                                    component="span"
                                    sx={{
                                        fontWeight: "bold",
                                        color: "text.base",
                                    }}
                                />
                            ),
                        }}
                        values={{ host: customDomainCNAME }}
                    />
                </Typography>
                <Typography sx={{ color: "text.muted", mt: 3 }}>
                    <Trans
                        i18nKey="custom_domains_help"
                        components={{
                            a: (
                                <Link
                                    href="https://ente.com/help/photos/features/sharing-and-collaboration/custom-domains/"
                                    target="_blank"
                                    rel="noopener"
                                    color="accent"
                                />
                            ),
                        }}
                    />
                </Typography>
            </DomainItem>
        </Stack>
    );
};

interface DomainSectionProps {
    title: string;
    ordinal: string;
}

const DomainItem: React.FC<React.PropsWithChildren<DomainSectionProps>> = ({
    title,
    ordinal,
    children,
}) => (
    <Stack>
        <Stack
            direction="row"
            sx={{ alignItems: "center", justifyContent: "space-between" }}
        >
            <Typography variant="h6">{title}</Typography>
            <Typography
                variant="h1"
                sx={{
                    minWidth: "28px",
                    textAlign: "center",
                    color: "stroke.faint",
                }}
            >
                {ordinal}
            </Typography>
        </Stack>
        {children}
    </Stack>
);

const AdvancedSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const { cfUploadProxyDisabled } = useSettingsSnapshot();
    const [isAutoLaunchEnabled, setIsAutoLaunchEnabled] = useState(false);

    const electron = globalThis.electron;

    const refreshAutoLaunchEnabled = useCallback(async () => {
        return electron
            ?.isAutoLaunchEnabled()
            .then((enabled) => setIsAutoLaunchEnabled(enabled));
    }, [electron]);

    useEffect(
        () => void refreshAutoLaunchEnabled(),
        [refreshAutoLaunchEnabled],
    );

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const toggleProxy = () =>
        void updateCFProxyDisabledPreference(!cfUploadProxyDisabled);

    const toggleAutoLaunch = () =>
        void electron?.toggleAutoLaunch().then(refreshAutoLaunchEnabled);

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("advanced")}
        >
            <Stack sx={{ px: 2, py: "20px", gap: 3 }}>
                <Stack>
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("faster_upload")}
                            checked={!cfUploadProxyDisabled}
                            onClick={toggleProxy}
                        />
                    </RowButtonGroup>
                    <RowButtonGroupHint>
                        {t("faster_upload_description")}
                    </RowButtonGroupHint>
                </Stack>
                {electron && (
                    <RowButtonGroup>
                        <RowSwitch
                            label={t("open_ente_on_startup")}
                            checked={isAutoLaunchEnabled}
                            onClick={toggleAutoLaunch}
                        />
                    </RowButtonGroup>
                )}
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};
