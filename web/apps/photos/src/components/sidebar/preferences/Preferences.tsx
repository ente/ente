import ArrowOutwardRoundedIcon from "@mui/icons-material/ArrowOutwardRounded";
import DarkModeIcon from "@mui/icons-material/DarkMode";
import LightModeIcon from "@mui/icons-material/LightMode";
import SmartphoneIcon from "@mui/icons-material/Smartphone";
import {
    InputBase,
    Link,
    Stack,
    useColorScheme,
    type Theme,
} from "@mui/material";
import Typography from "@mui/material/Typography";
import { isDesktop } from "ente-base/app";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import {
    RowButtonEndActivityIndicator,
    RowButtonGroupHint,
    RowButtonGroupTitle,
} from "ente-base/components/RowButton";
import {
    v2HelperSx,
    v2InputSx,
    v2LabelSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import { MenuComponent } from "ente-base/components/v2/MenuComponent";
import { MenuGroupComponent } from "ente-base/components/v2/MenuGroupComponent";
import { RowCard } from "ente-base/components/v2/RowCard";
import { isHTTPErrorWithStatus } from "ente-base/http";
import {
    getLocaleInUse,
    setLocaleInUse,
    supportedLocales,
    ut,
    type SupportedLocale,
} from "ente-base/i18n";
import log from "ente-base/log";
import type { CloseAction } from "ente-base/types/ipc";
import {
    isHLSGenerationSupported,
    toggleHLSGeneration,
} from "ente-gallery/services/video";
import {
    useHLSGenerationStatusSnapshot,
    useMLStatusSnapshot,
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
import React, { useCallback, useEffect, useId, useState } from "react";
import { Trans } from "react-i18next";
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
    const { mode } = useColorScheme();
    const mlStatus = useMLStatusSnapshot();
    const {
        show: showLanguageSettings,
        props: languageSettingsVisibilityProps,
    } = useModalVisibility();
    const { show: showThemeSettings, props: themeSettingsVisibilityProps } =
        useModalVisibility();
    const { show: showDomainSettings, props: domainSettingsVisibilityProps } =
        useModalVisibility();
    const {
        show: showAdvancedSettings,
        props: advancedSettingsVisibilityProps,
    } = useModalVisibility();
    const { show: showMLSettings, props: mlSettingsVisibilityProps } =
        useModalVisibility();

    const { mapEnabled, customDomain } = useSettingsSnapshot();
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
            case "preferences.language":
                showLanguageSettings();
                break;
            case "preferences.theme":
                showThemeSettings();
                break;
            case "preferences.map":
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
        showLanguageSettings,
        showThemeSettings,
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
            <Stack sx={{ px: 2, py: 1, gap: 1 }}>
                <RowCard
                    title={t("language")}
                    subtitle={localeName(getLocaleInUse())}
                    onClick={showLanguageSettings}
                />
                <RowCard
                    title={t("theme")}
                    subtitle={mode ? t(mode) : undefined}
                    onClick={showThemeSettings}
                />
                {isMLSupported && (
                    <RowCard
                        title={t("ml_search")}
                        subtitle={
                            mlStatus
                                ? t(
                                      mlStatus.phase === "disabled"
                                          ? "off"
                                          : "on",
                                  )
                                : undefined
                        }
                        onClick={showMLSettings}
                    />
                )}
                <RowCard
                    title={t("custom_domains")}
                    subtitle={customDomain || t("none")}
                    onClick={showDomainSettings}
                />
                <Stack>
                    <RowCard
                        title={t("map")}
                        endIcon={
                            <EnteSwitch
                                checked={mapEnabled}
                                onChange={handleToggleMap}
                                slotProps={{
                                    input: { "aria-label": t("map") },
                                }}
                            />
                        }
                    />
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
                <RowCard title={t("advanced")} onClick={showAdvancedSettings} />
                {isDesktop && (
                    <AppLockSettings
                        onAuthenticateUser={onAuthenticateUser}
                        onRootClose={onRootClose}
                    />
                )}
                {isHLSGenerationSupported && (
                    <Stack>
                        <RowCard
                            title={t("streamable_videos")}
                            endIcon={
                                <EnteSwitch
                                    checked={isHLSGenerationEnabled}
                                    onChange={() => void toggleHLSGeneration()}
                                    slotProps={{
                                        input: {
                                            "aria-label":
                                                t("streamable_videos"),
                                        },
                                    }}
                                />
                            }
                        />
                        {isHLSGenerationEnabled && (
                            <RowCard
                                title={
                                    <Typography
                                        component="span"
                                        sx={{ color: "text.faint", pl: 1 }}
                                    >
                                        {t("processed")}
                                    </Typography>
                                }
                                endIcon={
                                    hlsProcessedFraction == undefined ? (
                                        <RowButtonEndActivityIndicator />
                                    ) : (
                                        <Typography sx={{ textAlign: "right" }}>
                                            {t("percent_complete", {
                                                percent:
                                                    hlsProcessedFraction * 100,
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
                                    )
                                }
                            />
                        )}
                    </Stack>
                )}
            </Stack>
            <LanguageSelector
                {...languageSettingsVisibilityProps}
                onRootClose={handleRootClose}
            />
            <ThemeSelector
                {...themeSettingsVisibilityProps}
                onRootClose={handleRootClose}
            />
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

const LanguageSelector: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const locale = getLocaleInUse();

    const updateCurrentLocale = (newLocale: SupportedLocale) => {
        if (newLocale === locale) {
            onClose();
            return;
        }

        void setLocaleInUse(newLocale).then(() => {
            // Global translations and cached formatters need a full reload.
            // Trust it so desktop app lock does not immediately lock again.
            if (globalThis.electron) {
                suppressAppLockRefreshFromSessionForTrustedReload();
            }
            window.location.reload();
        });
    };

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("select_language")}
        >
            <Stack sx={{ px: 2, py: 1 }}>
                <MenuGroupComponent>
                    {supportedLocales.map((option) => (
                        <MenuComponent
                            key={option}
                            title={localeName(option)}
                            selected={option === locale}
                            onClick={() => updateCurrentLocale(option)}
                        />
                    ))}
                </MenuGroupComponent>
            </Stack>
        </TitledNestedSidebarDrawer>
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
            return "Português (Portugal)";
        case "pt-BR":
            return "Português (Brasil)";
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
        case "tt-RU":
            return "Татарча";
        case "cs-CZ":
            return "Čeština";
        case "el-GR":
            return "Ελληνικά";
    }
};

const ThemeSelector: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const { mode, setMode } = useColorScheme();

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    // MUI color mode is undefined during SSR.
    if (!mode) return null;

    const options = [
        { label: t("system"), value: "system", icon: <SmartphoneIcon /> },
        { label: t("light"), value: "light", icon: <LightModeIcon /> },
        { label: t("dark"), value: "dark", icon: <DarkModeIcon /> },
    ] as const;

    return (
        <TitledNestedSidebarDrawer
            maxWidth="440px"
            {...{ open, onClose }}
            onRootClose={handleRootClose}
            title={t("theme")}
        >
            <Stack sx={{ px: 2, py: 1 }}>
                <MenuGroupComponent dividerInset={68}>
                    {options.map(({ label, value, icon }) => (
                        <MenuComponent
                            key={value}
                            title={label}
                            startIcon={icon}
                            selected={value === mode}
                            onClick={() => {
                                setMode(value);
                                onClose();
                            }}
                        />
                    ))}
                </MenuGroupComponent>
            </Stack>
        </TitledNestedSidebarDrawer>
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
            titleInline
        >
            <DomainSettingsContents />
        </TitledNestedSidebarDrawer>
    );
};

const domainSurfaceSx = (theme: Theme) => ({
    bgcolor: "background.default",
    ...theme.applyStyles("dark", { bgcolor: "#282828" }),
});

// This component boundary resets form state on back navigation.
const DomainSettingsContents: React.FC = () => {
    const { customDomain, customDomainCNAME } = useSettingsSnapshot();
    const domainInputID = useId();
    const domainHintID = useId();

    const formik = useFormik({
        initialValues: { domain: customDomain ?? "" },
        onSubmit: async ({ domain }, { setFieldError }) => {
            try {
                await updateCustomDomain(domain);
            } catch (e) {
                const message = isHTTPErrorWithStatus(e, 400)
                    ? t("invalid_domain")
                    : isHTTPErrorWithStatus(e, 402)
                      ? t("sharing_disabled_for_free_accounts")
                      : isHTTPErrorWithStatus(e, 409)
                        ? t("already_linked_domain")
                        : t("generic_error");
                log.error("Failed to update the custom domain", e);
                setFieldError("domain", message);
            }
        },
    });
    const submitLabel = t(customDomain ? "update" : "save");
    const domainError = formik.errors.domain;

    return (
        <Stack sx={{ maxWidth: 528, px: 2, pt: 1, pb: 2, gap: 2.5 }}>
            <Typography variant="body" sx={{ color: "text.muted" }}>
                {t("custom_domains_desc")}
            </Typography>
            <Stack
                component="form"
                onSubmit={formik.handleSubmit}
                sx={{ gap: 1 }}
            >
                <Typography
                    component="label"
                    htmlFor={domainInputID}
                    sx={v2LabelSx}
                >
                    {t("domain")}
                </Typography>
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "flex-start",
                        flexWrap: "wrap",
                        gap: 1.5,
                    }}
                >
                    <Stack sx={{ flex: "1 1 180px", minWidth: 0, gap: 1 }}>
                        <InputBase
                            id={domainInputID}
                            name="domain"
                            value={formik.values.domain}
                            onChange={formik.handleChange}
                            placeholder={ut("photos.example.org")}
                            error={!!domainError}
                            disabled={formik.isSubmitting}
                            aria-describedby={domainHintID}
                            inputProps={{
                                autoCapitalize: "none",
                                inputMode: "url",
                                spellCheck: false,
                            }}
                            sx={[
                                ...(isSxArray(v2InputSx)
                                    ? v2InputSx
                                    : [v2InputSx]),
                                { boxSizing: "border-box" },
                                domainSurfaceSx,
                            ]}
                        />
                        <Typography
                            id={domainHintID}
                            aria-live="polite"
                            sx={[
                                v2HelperSx(!!domainError),
                                !domainError && { color: "text.muted" },
                            ]}
                        >
                            {domainError ?? t("domain_help")}
                        </Typography>
                    </Stack>
                    <LoadingButton
                        type="submit"
                        color="accent"
                        loading={formik.isSubmitting}
                        aria-label={submitLabel}
                        sx={[
                            v2SubmitButtonSx,
                            { flex: "0 0 auto", minWidth: 84, ml: "auto" },
                        ]}
                    >
                        {submitLabel}
                    </LoadingButton>
                </Stack>
            </Stack>
            <Stack
                sx={[
                    domainSurfaceSx,
                    { p: 2, gap: 1, borderRadius: 2, overflowWrap: "anywhere" },
                ]}
            >
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "center",
                        justifyContent: "space-between",
                        flexWrap: "wrap",
                        columnGap: 1.5,
                        rowGap: 0.5,
                    }}
                >
                    <Typography
                        component="h4"
                        variant="body"
                        sx={{ fontWeight: 600 }}
                    >
                        {t("custom_domain_dns_setup")}
                    </Typography>
                    <Link
                        href="https://ente.com/help/photos/features/sharing-and-collaboration/custom-domains/"
                        target="_blank"
                        rel="noopener"
                        variant="small"
                        color="text.muted"
                        underline="hover"
                        sx={{
                            display: "inline-flex",
                            alignItems: "center",
                            minHeight: 32,
                            gap: 0.5,
                            "&:hover": { color: "text.base" },
                            "&:focus-visible": {
                                outline: "2px solid",
                                outlineColor: "stroke.base",
                                outlineOffset: 2,
                            },
                        }}
                    >
                        {t("add_dns_entry")}
                        <ArrowOutwardRoundedIcon
                            aria-hidden
                            sx={{ fontSize: 14, flexShrink: 0 }}
                        />
                    </Link>
                </Stack>
                <Typography
                    variant="body"
                    sx={{ color: "text.muted", lineHeight: "24px" }}
                >
                    <Trans
                        i18nKey="add_dns_entry_hint"
                        values={{ host: customDomainCNAME }}
                        components={{
                            b: (
                                <Typography
                                    component="code"
                                    sx={{
                                        px: 0.75,
                                        py: 0.25,
                                        borderRadius: 0.75,
                                        bgcolor: "background.paper",
                                        color: "text.base",
                                        fontFamily: "monospace",
                                        fontSize: "0.9em",
                                        boxDecorationBreak: "clone",
                                    }}
                                />
                            ),
                        }}
                    />
                </Typography>
            </Stack>
        </Stack>
    );
};

const AdvancedSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const { cfUploadProxyDisabled } = useSettingsSnapshot();
    const [isAutoLaunchEnabled, setIsAutoLaunchEnabled] = useState(false);
    const [closeAction, setCloseAction] = useState<CloseAction | undefined>();

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

    useEffect(() => {
        void electron?.closeAction().then(setCloseAction);
    }, [electron]);

    const updateCloseAction = (action: CloseAction) =>
        void electron
            ?.setCloseAction(action)
            .then(() => setCloseAction(action))
            .catch((e: unknown) => log.error("Failed to set close action", e));

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
            <Stack sx={{ px: 2, py: 1, gap: 1 }}>
                <Stack>
                    <RowCard
                        title={t("smart_routing")}
                        endIcon={
                            <EnteSwitch
                                checked={!cfUploadProxyDisabled}
                                onChange={toggleProxy}
                                slotProps={{
                                    input: { "aria-label": t("smart_routing") },
                                }}
                            />
                        }
                    />
                    <Typography
                        variant="small"
                        sx={{ color: "text.faint", pl: 2, pr: 1, py: "6px" }}
                    >
                        {t("faster_upload_description")}
                    </Typography>
                </Stack>
                {electron && (
                    <RowCard
                        title={t("open_ente_on_startup")}
                        endIcon={
                            <EnteSwitch
                                checked={isAutoLaunchEnabled}
                                onChange={toggleAutoLaunch}
                                slotProps={{
                                    input: {
                                        "aria-label": t("open_ente_on_startup"),
                                    },
                                }}
                            />
                        }
                    />
                )}
                {closeAction && (
                    <Stack>
                        <RowButtonGroupTitle>
                            {t("when_closing_window")}
                        </RowButtonGroupTitle>
                        <MenuGroupComponent>
                            {closeActionOptions.map((option) => (
                                <MenuComponent
                                    key={option}
                                    title={closeActionLabel(option)}
                                    selected={option === closeAction}
                                    onClick={() => updateCloseAction(option)}
                                />
                            ))}
                        </MenuGroupComponent>
                        <Typography
                            variant="small"
                            sx={{
                                color: "text.faint",
                                pl: 2,
                                pr: 1,
                                py: "6px",
                            }}
                        >
                            {t("when_closing_window_description")}
                        </Typography>
                    </Stack>
                )}
            </Stack>
        </TitledNestedSidebarDrawer>
    );
};

const closeActionOptions: CloseAction[] = ["ask", "quit", "background"];

const closeActionLabel = (action: CloseAction) => {
    switch (action) {
        case "ask":
            return t("close_action_ask");
        case "quit":
            return t("close_action_quit");
        case "background":
            return t("close_action_background");
    }
};
