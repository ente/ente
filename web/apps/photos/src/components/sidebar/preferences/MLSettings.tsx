import { useWrapAsyncOperation } from "@/components/utils/use-wrap-async";
import {
    Box,
    Button,
    Checkbox,
    FormControlLabel,
    FormGroup,
    Link,
    Stack,
    Typography,
} from "@mui/material";
import { EnteSwitch } from "ente-base/components/EnteSwitch";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { RowCard } from "ente-base/components/v2/RowCard";
import { useBaseContext } from "ente-base/context";
import { useMLStatusSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    disableML,
    enableML,
    type MLStatus,
} from "ente-new/photos/services/ml";
import { openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import React, { useEffect, useState } from "react";
import { Trans } from "react-i18next";

export const MLSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const mlStatus = useMLStatusSnapshot();
    const [openFaceConsent, setOpenFaceConsent] = useState(false);

    const handleRootClose = () => {
        onClose();
        onRootClose();
    };

    const handleEnableML = () => setOpenFaceConsent(true);

    const handleConsent = useWrapAsyncOperation(async () => {
        await enableML();
        setOpenFaceConsent(false);
    });

    const handleDisableML = useWrapAsyncOperation(disableML);

    let component: React.ReactNode;
    if (!mlStatus) {
        component = <Loading />;
    } else if (mlStatus.phase == "disabled") {
        component = <EnableML onEnable={handleEnableML} showMagicSearchHint />;
    } else {
        component = (
            <ManageML {...{ mlStatus }} onDisableML={handleDisableML} />
        );
    }

    return (
        <>
            <TitledNestedSidebarDrawer
                maxWidth="440px"
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("ml_search")}
            >
                {component}
            </TitledNestedSidebarDrawer>

            <FaceConsentDrawer
                open={openFaceConsent}
                onClose={() => setOpenFaceConsent(false)}
                onRootClose={handleRootClose}
                onConsent={handleConsent}
            />
        </>
    );
};

const Loading: React.FC = () => {
    return (
        <Box sx={{ textAlign: "center", pt: 4 }}>
            <ActivityIndicator />
        </Box>
    );
};

interface EnableMLProps {
    onEnable: () => void;
    showMagicSearchHint?: boolean;
}

export const EnableML: React.FC<EnableMLProps> = ({
    onEnable,
    showMagicSearchHint,
}) => {
    const moreDetails = () =>
        openURL("https://ente.com/help/photos/features/machine-learning");

    return (
        <Stack sx={{ gap: 3, py: 1, px: 2 }}>
            <Typography sx={{ color: "text.muted", px: 1 }}>
                {t("ml_search_description")}
            </Typography>
            <Stack sx={{ gap: "8px" }}>
                <Button fullWidth color="accent" onClick={onEnable}>
                    {t("enable")}
                </Button>
                <Button fullWidth color="secondary" onClick={moreDetails}>
                    {t("more_details")}
                </Button>
            </Stack>
            {showMagicSearchHint && (
                <Typography variant="small" sx={{ color: "text.faint", px: 1 }}>
                    {t("ml_search_footnote")}
                </Typography>
            )}
        </Stack>
    );
};

type FaceConsentDrawerProps = NestedSidebarDrawerVisibilityProps &
    Pick<FaceConsentProps, "onConsent">;

const FaceConsentDrawer: React.FC<FaceConsentDrawerProps> = ({
    open,
    onClose,
    onRootClose,
    onConsent,
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
            title={t("ml_consent_title")}
        >
            <FaceConsent onConsent={onConsent} onCancel={onClose} />
        </TitledNestedSidebarDrawer>
    );
};

interface FaceConsentProps {
    onConsent: () => void;
    onCancel: () => void;
}

export const FaceConsent: React.FC<FaceConsentProps> = ({
    onConsent,
    onCancel,
}) => {
    const [acceptTerms, setAcceptTerms] = useState(false);

    useEffect(() => {
        setAcceptTerms(false);
    }, []);

    const privacyPolicyLink = (
        <Link
            target="_blank"
            href="https://ente.com/privacy#8-biometric-information-privacy-policy"
            underline="always"
            sx={{ color: "inherit", textDecorationColor: "inherit" }}
        />
    );

    return (
        <Stack sx={{ gap: 3, py: 1, px: 2 }}>
            <Typography component="div" sx={{ color: "text.muted", px: "8px" }}>
                <Trans
                    i18nKey={"ml_consent_description"}
                    components={{ a: privacyPolicyLink }}
                />
            </Typography>
            <FormGroup sx={{ width: "100%" }}>
                <FormControlLabel
                    sx={{ color: "text.muted", ml: 0 }}
                    control={
                        <Checkbox
                            size="small"
                            checked={acceptTerms}
                            onChange={(e) => setAcceptTerms(e.target.checked)}
                        />
                    }
                    label={t("ml_consent_confirmation")}
                />
            </FormGroup>
            <Stack sx={{ gap: 1 }}>
                <FocusVisibleButton
                    fullWidth
                    color="accent"
                    disabled={!acceptTerms}
                    onClick={onConsent}
                >
                    {t("ml_consent")}
                </FocusVisibleButton>
                <FocusVisibleButton
                    fullWidth
                    color="secondary"
                    onClick={onCancel}
                >
                    {t("cancel")}
                </FocusVisibleButton>
            </Stack>
        </Stack>
    );
};

interface ManageMLProps {
    mlStatus: Exclude<MLStatus, { phase: "disabled" }>;
    onDisableML: () => void;
}

const ManageML: React.FC<ManageMLProps> = ({ mlStatus, onDisableML }) => {
    const { showMiniDialog } = useBaseContext();

    const { phase, phaseFailed, nSyncedFiles, nTotalFiles } = mlStatus;

    let status: string;
    switch (phase) {
        case "scheduled":
            status = t("indexing_status_scheduled");
            break;
        case "fetching":
            status = t("indexing_status_fetching");
            break;
        case "indexing":
            status = t("indexing_status_running");
            break;
        case "clustering":
            status = t("people");
            break;
        default:
            status = phaseFailed ? t("error") : t("indexing_status_done");
            break;
    }

    const processed = `${nTotalFiles ? Math.round((100 * nSyncedFiles) / nTotalFiles) : 100}%`;

    const confirmDisableML = () =>
        showMiniDialog({
            title: t("ml_search_disable"),
            message: t("ml_search_disable_confirm"),
            continue: {
                text: t("disable"),
                color: "critical",
                action: onDisableML,
            },
        });

    return (
        <Stack sx={{ px: 2, py: 1, gap: 1 }}>
            <RowCard
                title={t("enabled")}
                endIcon={
                    <EnteSwitch
                        checked
                        onChange={confirmDisableML}
                        slotProps={{ input: { "aria-label": t("enabled") } }}
                    />
                }
            />
            <RowCard
                title={
                    <Typography
                        component="span"
                        sx={{ color: "text.faint", pl: 1 }}
                    >
                        {t("indexing")}
                    </Typography>
                }
                endIcon={
                    <Typography sx={{ textAlign: "right" }}>
                        {status}
                    </Typography>
                }
            />
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
                    <Typography sx={{ textAlign: "right" }}>
                        {processed}
                    </Typography>
                }
            />
        </Stack>
    );
};
