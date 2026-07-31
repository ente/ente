import CheckCircleOutlinedIcon from "@mui/icons-material/CheckCircleOutlined";
import EditIcon from "@mui/icons-material/Edit";
import { Box, Button, IconButton, Stack, Typography } from "@mui/material";
import { TitledMiniDialog } from "ente-base/components/MiniDialog";
import {
    RowButton,
    RowButtonDivider,
    RowButtonGroup,
} from "ente-base/components/RowButton";
import {
    SingleInputForm,
    type SingleInputFormProps,
} from "ente-base/components/SingleInputForm";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import {
    isHTTP4xxError,
    isHTTPErrorWithStatus,
    isMuseumHTTPError,
} from "ente-base/http";
import log from "ente-base/log";
import { bytesInGB } from "ente-gallery/utils/units";
import { useUserDetailsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    changeReferralCode,
    claimReferralCode,
    getReferralView,
    getStorageBonusDetails,
    normalizeReferralCode,
    type ReferralView,
    type StorageBonusDetails,
} from "ente-new/photos/services/storage-bonus";
import {
    familyAdminEmail,
    isPartOfFamily,
    pullUserDetails,
    userDetailsAddOnBonuses,
    userDetailsSnapshot,
    type UserDetails,
} from "ente-new/photos/services/user-details";
import { openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import React, { useCallback, useEffect, useRef, useState } from "react";

type ReferralScreen =
    | "main"
    | "apply-refreshing"
    | "apply-refresh-error"
    | "success"
    | "details";

type Loadable<T> =
    | { status: "loading" }
    | { status: "error" }
    | { status: "loaded"; value: T };

const isValidReferralCode = (code: string) => /^[A-Z0-9]{4,20}$/.test(code);

export const ReferralSettings: React.FC<NestedSidebarDrawerVisibilityProps> = ({
    open,
    onClose,
    onRootClose,
}) => {
    const { showMiniDialog } = useBaseContext();
    const userDetails = useUserDetailsSnapshot();
    const {
        show: showEditCodeDialog,
        props: { open: isEditCodeDialogOpen, onClose: closeEditCodeDialog },
    } = useModalVisibility();
    const {
        show: showApplyCodeDialog,
        props: { open: isApplyCodeDialogOpen, onClose: closeApplyCodeDialog },
    } = useModalVisibility();
    const [screen, setScreen] = useState<ReferralScreen>("main");
    const [referralView, setReferralView] = useState<Loadable<ReferralView>>({
        status: "loading",
    });
    const [bonusDetails, setBonusDetails] = useState<
        Loadable<StorageBonusDetails>
    >({ status: "loading" });
    const requestNonce = useRef(0);
    const invalidateFetches = useCallback(() => {
        requestNonce.current++;
    }, []);

    const fetchReferralView = useCallback(async (showLoading: boolean) => {
        const nonce = ++requestNonce.current;
        if (showLoading) setReferralView({ status: "loading" });

        try {
            const [view] = await Promise.all([
                getReferralView(),
                userDetailsSnapshot() ? Promise.resolve() : pullUserDetails(),
            ]);
            if (requestNonce.current != nonce) return;
            setReferralView({ status: "loaded", value: view });
        } catch (e) {
            if (requestNonce.current != nonce) return;
            log.error("Failed to fetch referral details", e);
            setReferralView({ status: "error" });
            throw e;
        }
    }, []);

    const loadReferralView = useCallback(() => {
        void fetchReferralView(true).catch(() => undefined);
    }, [fetchReferralView]);

    const handleCodeChanged = useCallback(async () => {
        try {
            await fetchReferralView(false);
        } catch (e) {
            closeEditCodeDialog();
            setReferralView({ status: "error" });
            throw e;
        }
    }, [closeEditCodeDialog, fetchReferralView]);

    const loadBonusDetails = useCallback(() => {
        const nonce = ++requestNonce.current;
        setBonusDetails({ status: "loading" });

        void (async () => {
            try {
                const details = await getStorageBonusDetails();
                if (requestNonce.current != nonce) return;
                setBonusDetails({ status: "loaded", value: details });
            } catch (e) {
                if (requestNonce.current != nonce) return;
                log.error("Failed to fetch storage bonus details", e);
                setBonusDetails({ status: "error" });
            }
        })();
    }, []);

    useEffect(() => {
        if (!open) {
            closeEditCodeDialog();
            closeApplyCodeDialog();
            return;
        }

        setScreen("main");
        closeEditCodeDialog();
        closeApplyCodeDialog();
        loadReferralView();

        return invalidateFetches;
    }, [
        open,
        loadReferralView,
        invalidateFetches,
        closeEditCodeDialog,
        closeApplyCodeDialog,
    ]);

    const handleClose = () => {
        invalidateFetches();
        closeEditCodeDialog();
        closeApplyCodeDialog();
        if (screen != "main") {
            setScreen("main");
        } else {
            onClose();
        }
    };

    const handleRootClose = () => {
        invalidateFetches();
        closeEditCodeDialog();
        closeApplyCodeDialog();
        onClose();
        onRootClose();
    };

    const showDetails = () => {
        setScreen("details");
        loadBonusDetails();
    };

    const handleEditCode = () => {
        if (referralView.status != "loaded" || !userDetails) return;

        if (referralView.value.isFamilyMember) {
            showMiniDialog({
                message: t("referral_code_change_family_admin_only", {
                    familyAdminEmail: familyAdminEmail(userDetails) ?? "",
                }),
                cancel: t("ok"),
            });
        } else {
            showEditCodeDialog();
        }
    };

    const handleCodeApplied = useCallback(async () => {
        const nonce = ++requestNonce.current;
        closeApplyCodeDialog();
        setScreen("apply-refreshing");

        try {
            const [view, details] = await Promise.all([
                getReferralView(),
                getStorageBonusDetails(),
                pullUserDetails(),
            ]);
            if (requestNonce.current != nonce) return;

            setReferralView({ status: "loaded", value: view });
            setBonusDetails({ status: "loaded", value: details });
            setScreen("success");
        } catch (e) {
            if (requestNonce.current != nonce) return;

            log.error(
                "Failed to refresh referral details after applying a code",
                e,
            );
            setScreen("apply-refresh-error");
        }
    }, [closeApplyCodeDialog]);

    let contents: React.ReactNode;
    if (referralView.status == "loading") {
        contents = <Loading />;
    } else if (referralView.status == "error") {
        contents = <LoadError onRetry={loadReferralView} />;
    } else if (!userDetails) {
        contents = <Loading />;
    } else if (screen == "apply-refreshing") {
        contents = <Loading />;
    } else if (screen == "apply-refresh-error") {
        contents = (
            <LoadError
                message={t("referral_applied_refresh_failed")}
                onRetry={() => void handleCodeApplied()}
            />
        );
    } else if (screen == "details") {
        contents = (
            <DetailsContents
                referralView={referralView.value}
                {...{ userDetails, bonusDetails }}
                onRetry={loadBonusDetails}
            />
        );
    } else if (screen == "success") {
        contents = (
            <SuccessContents
                referralView={referralView.value}
                onShowDetails={() => setScreen("details")}
            />
        );
    } else {
        contents = (
            <MainContents
                referralView={referralView.value}
                familyAdminEmail={familyAdminEmail(userDetails)}
                onShowDetails={showDetails}
                onEditCode={handleEditCode}
                onApplyCode={showApplyCodeDialog}
            />
        );
    }

    return (
        <TitledNestedSidebarDrawer
            {...{ open }}
            onClose={handleClose}
            onRootClose={handleRootClose}
            title={t(
                screen == "details"
                    ? "details"
                    : screen == "success"
                      ? "code_applied"
                      : "referrals",
            )}
        >
            <Stack sx={{ px: 2, py: 1, gap: 3 }}>{contents}</Stack>
            {isEditCodeDialogOpen && referralView.status == "loaded" && (
                <EditCodeDialog
                    open={isEditCodeDialogOpen}
                    onClose={closeEditCodeDialog}
                    currentCode={referralView.value.code}
                    remainingCodeChangeAttempts={
                        referralView.value.remainingCodeChangeAttempts
                    }
                    onChanged={handleCodeChanged}
                />
            )}
            {isApplyCodeDialogOpen && (
                <ApplyCodeDialog
                    open={isApplyCodeDialogOpen}
                    onClose={closeApplyCodeDialog}
                    onApplied={handleCodeApplied}
                    onRefresh={() =>
                        void fetchReferralView(false).catch(() => undefined)
                    }
                />
            )}
        </TitledNestedSidebarDrawer>
    );
};

const Loading: React.FC = () => (
    <Box sx={{ textAlign: "center", pt: 4 }}>
        <ActivityIndicator />
    </Box>
);

interface LoadErrorProps {
    onRetry: () => void;
    message?: string;
}

const LoadError: React.FC<LoadErrorProps> = ({ onRetry, message }) => (
    <Stack sx={{ gap: 2, pt: 3 }}>
        <Typography sx={{ color: "text.muted" }}>
            {message ?? t("referral_fetch_failed")}
        </Typography>
        <Button fullWidth color="secondary" onClick={onRetry}>
            {t("retry")}
        </Button>
    </Stack>
);

interface MainContentsProps {
    referralView: ReferralView;
    familyAdminEmail?: string;
    onShowDetails: () => void;
    onEditCode: () => void;
    onApplyCode: () => void;
}

const MainContents: React.FC<MainContentsProps> = ({
    referralView,
    familyAdminEmail,
    onShowDetails,
    onEditCode,
    onApplyCode,
}) => {
    const { planInfo, code } = referralView;
    const codeChangeHint = referralView.isFamilyMember
        ? t("referral_code_change_family_admin_only", { familyAdminEmail })
        : referralView.remainingCodeChangeAttempts == undefined
          ? t("referral_code_change_hint")
          : referralView.remainingCodeChangeAttempts === 0
            ? t("code_change_limit_reached")
            : t("referral_code_changes_remaining", {
                  count: referralView.remainingCodeChangeAttempts,
              });

    return (
        <>
            <Stack sx={{ gap: 0.5 }}>
                <Typography variant="h5">{t("earn_free_storage")}</Typography>
                <Typography sx={{ color: "text.muted" }}>
                    {t(
                        planInfo.isEnabled
                            ? "share_code_earn_storage"
                            : "referrals_paused",
                    )}
                </Typography>
            </Stack>
            {planInfo.isEnabled && (
                <>
                    <Stack sx={{ gap: 1 }}>
                        <ReferralCodeCard
                            code={code}
                            onEdit={
                                referralView.isFamilyMember ||
                                referralView.remainingCodeChangeAttempts === 0
                                    ? undefined
                                    : onEditCode
                            }
                        />
                        <Typography
                            variant="small"
                            sx={{ px: 1, color: "text.muted" }}
                        >
                            {codeChangeHint}
                        </Typography>
                    </Stack>
                    <InviteShareButton
                        code={code}
                        storageInGB={planInfo.storageInGB}
                    />
                    <HowItWorks storageInGB={planInfo.storageInGB} />
                </>
            )}

            <RowButtonGroup>
                {referralView.enableApplyCode && (
                    <>
                        <RowButton
                            variant="secondary"
                            label={t("apply_code")}
                            onClick={onApplyCode}
                        />
                        <RowButtonDivider />
                    </>
                )}
                <RowButton
                    variant="secondary"
                    label={t("faq")}
                    onClick={() =>
                        openURL(
                            "https://ente.com/help/photos/features/account/referral-program/",
                        )
                    }
                />
                <RowButtonDivider />
                <RowButton
                    variant="secondary"
                    label={t("details")}
                    onClick={onShowDetails}
                />
            </RowButtonGroup>
        </>
    );
};

interface ReferralCodeCardProps {
    code: string;
    onEdit?: () => void;
}

const ReferralCodeCard: React.FC<ReferralCodeCardProps> = ({
    code,
    onEdit,
}) => (
    <Box
        sx={{
            position: "relative",
            border: "1px dashed",
            borderColor: "stroke.muted",
            borderRadius: 2,
            px: 2,
            py: 3,
            textAlign: "center",
        }}
    >
        <Typography
            variant="h3"
            sx={{
                letterSpacing: "0.08em",
                overflowWrap: "anywhere",
                ...(onEdit && { px: 6 }),
            }}
        >
            {code}
        </Typography>
        {onEdit && (
            <IconButton
                aria-label={t("change_code")}
                onClick={onEdit}
                sx={{
                    position: "absolute",
                    top: "50%",
                    right: 4,
                    width: 48,
                    height: 48,
                    transform: "translateY(-50%)",
                }}
            >
                <EditIcon />
            </IconButton>
        )}
    </Box>
);

interface SuccessContentsProps {
    referralView: ReferralView;
    onShowDetails: () => void;
}

const SuccessContents: React.FC<SuccessContentsProps> = ({
    referralView,
    onShowDetails,
}) => {
    const { code, planInfo } = referralView;

    return (
        <>
            <Stack
                role="status"
                aria-live="polite"
                sx={{ alignItems: "center", gap: 1, pt: 2 }}
            >
                <CheckCircleOutlinedIcon
                    sx={{ color: "accent.main", fontSize: 72 }}
                />
                <Typography variant="h3" sx={{ textAlign: "center" }}>
                    {t("referral_storage_claimed", {
                        storageAmountInGB: planInfo.storageInGB,
                    })}
                </Typography>
            </Stack>
            <RowButtonGroup>
                <RowButton
                    variant="secondary"
                    label={t("details")}
                    onClick={onShowDetails}
                />
            </RowButtonGroup>
            <Stack sx={{ gap: 2 }}>
                <Typography variant="h5">{t("earn_more_space")}</Typography>
                <ReferralCodeCard code={code} />
                <Typography sx={{ color: "text.muted" }}>
                    {t("referral_storage_for_both", {
                        storageAmountInGB: planInfo.storageInGB,
                    })}
                </Typography>
                <InviteShareButton
                    code={code}
                    storageInGB={planInfo.storageInGB}
                />
            </Stack>
        </>
    );
};

interface EditCodeDialogProps {
    open: boolean;
    onClose: () => void;
    currentCode: string;
    remainingCodeChangeAttempts?: number;
    onChanged: () => Promise<void>;
}

const EditCodeDialog: React.FC<EditCodeDialogProps> = ({
    open,
    onClose,
    currentCode,
    remainingCodeChangeAttempts,
    onChanged,
}) => {
    const handleSubmit: SingleInputFormProps["onSubmit"] = async (
        code,
        setFieldError,
    ) => {
        const normalized = normalizeReferralCode(code);

        if (normalized == normalizeReferralCode(currentCode)) {
            onClose();
            return;
        }

        if (!isValidReferralCode(normalized)) {
            setFieldError(t("referral_code_invalid"));
            return;
        }
        if (remainingCodeChangeAttempts === 0) {
            setFieldError(t("code_change_limit_reached"));
            return;
        }

        try {
            await changeReferralCode(normalized);
            await onChanged();
            onClose();
        } catch (e) {
            log.error("Failed to change referral code", e);

            const isUnavailable = await isMuseumHTTPError(
                e,
                400,
                "CODE_ALREADY_EXISTS",
            );
            const isChangeLimitReached = await isMuseumHTTPError(
                e,
                429,
                "REFERRAL_CHANGE_LIMIT_REACHED",
            );

            setFieldError(
                isUnavailable || isHTTPErrorWithStatus(e, 400)
                    ? t("code_unavailable")
                    : isChangeLimitReached
                      ? t("code_change_limit_reached")
                      : t("generic_error"),
            );
        }
    };

    return (
        <TitledMiniDialog {...{ open, onClose }} title={t("change_code")}>
            <SingleInputForm
                initialValue={currentCode}
                label={t("enter_referral_code")}
                submitButtonTitle={t("save")}
                onCancel={onClose}
                onSubmit={handleSubmit}
            />
        </TitledMiniDialog>
    );
};

interface ApplyCodeDialogProps {
    open: boolean;
    onClose: () => void;
    onApplied: () => Promise<void>;
    onRefresh: () => void;
}

const ApplyCodeDialog: React.FC<ApplyCodeDialogProps> = ({
    open,
    onClose,
    onApplied,
    onRefresh,
}) => {
    const handleSubmit: SingleInputFormProps["onSubmit"] = async (
        code,
        setFieldError,
    ) => {
        const normalized = normalizeReferralCode(code);
        if (normalized.length < 4) {
            setFieldError(t("invalid_code"));
            return;
        }

        try {
            await claimReferralCode(normalized);
            await onApplied();
        } catch (e) {
            log.error("Failed to apply referral code", e);

            const isInvalidCode = await isMuseumHTTPError(
                e,
                404,
                "INVALID_CODE",
            );
            const isNotEligible = await isMuseumHTTPError(
                e,
                400,
                "ACCOUNT_NOT_ELIGIBLE",
            );
            const isAlreadyApplied = await isMuseumHTTPError(
                e,
                409,
                "CODE_ALREADY_APPLIED",
            );

            if (isNotEligible || isAlreadyApplied) onRefresh();
            setFieldError(
                isInvalidCode
                    ? t("invalid_code")
                    : isNotEligible
                      ? t("code_apply_not_eligible")
                      : isAlreadyApplied
                        ? t("code_already_applied")
                        : isHTTP4xxError(e)
                          ? t("apply_code_failed")
                          : t("generic_error"),
            );
        }
    };

    return (
        <TitledMiniDialog {...{ open, onClose }} title={t("apply_code")}>
            <Stack sx={{ gap: 1 }}>
                <Typography
                    id="referral-code-apply-description"
                    sx={{ color: "text.muted" }}
                >
                    {t("apply_code_description")}
                </Typography>
                <SingleInputForm
                    label={t("enter_referral_code")}
                    slotProps={{
                        htmlInput: {
                            "aria-describedby":
                                "referral-code-apply-description",
                            style: { textTransform: "uppercase" },
                        },
                    }}
                    submitButtonTitle={t("apply_code")}
                    onCancel={onClose}
                    onSubmit={handleSubmit}
                />
            </Stack>
        </TitledMiniDialog>
    );
};

interface InviteShareButtonProps {
    code: string;
    storageInGB: number;
}

const InviteShareButton: React.FC<InviteShareButtonProps> = ({
    code,
    storageInGB,
}) => {
    const { onGenericError } = useBaseContext();
    const [copied, setCopied] = useState(false);
    const copiedTimeout = useRef<ReturnType<typeof setTimeout> | undefined>(
        undefined,
    );

    useEffect(
        () => () => {
            if (copiedTimeout.current) clearTimeout(copiedTimeout.current);
        },
        [],
    );

    const handleShare = async () => {
        const text = t("referral_share_text", {
            referralCode: code,
            referralStorageInGB: storageInGB,
        });

        if (typeof navigator.share == "function") {
            try {
                await navigator.share({ text });
            } catch (e) {
                if ((e as Error).name == "AbortError") return;
                log.error("Failed to share referral invite", e);
                onGenericError(e);
            }
            return;
        }

        try {
            await navigator.clipboard.writeText(text);
            setCopied(true);
            if (copiedTimeout.current) clearTimeout(copiedTimeout.current);
            copiedTimeout.current = setTimeout(() => setCopied(false), 2000);
        } catch (e) {
            onGenericError(e);
        }
    };

    return (
        <Button fullWidth color="accent" onClick={() => void handleShare()}>
            <span aria-live="polite">
                {t(copied ? "invite_copied" : "share_invite")}
            </span>
        </Button>
    );
};

const HowItWorks: React.FC<{ storageInGB: number }> = ({ storageInGB }) => (
    <Box
        component="ol"
        sx={{ m: 0, pl: 3, color: "text.muted", display: "grid", gap: 1.5 }}
    >
        {[
            t("referral_step_1"),
            t("referral_step_2"),
            t("referral_step_3", { storageInGB }),
        ].map((step) => (
            <Typography component="li" key={step}>
                {step}
            </Typography>
        ))}
    </Box>
);

interface DetailsContentsProps {
    referralView: ReferralView;
    userDetails: UserDetails;
    bonusDetails: Loadable<StorageBonusDetails>;
    onRetry: () => void;
}

const DetailsContents: React.FC<DetailsContentsProps> = ({
    referralView,
    userDetails,
    bonusDetails,
    onRetry,
}) => {
    if (bonusDetails.status == "loading") return <Loading />;
    if (bonusDetails.status == "error") return <LoadError {...{ onRetry }} />;

    const details = bonusDetails.value;
    const addOnStorage = userDetailsAddOnBonuses(userDetails).reduce(
        (sum, bonus) => sum + bonus.storage,
        0,
    );
    const planStorage = isPartOfFamily(userDetails)
        ? (userDetails.familyData?.storage ?? 0)
        : userDetails.subscription.storage;
    const usableStorage = Math.min(
        referralView.claimedStorage,
        planStorage + addOnStorage,
    );
    const formatStorage = (storage: number) =>
        `${bytesInGB(storage)} ${t("storage_unit.gb")}`;

    const stats = [
        {
            label: t("referral_used_your_code"),
            value: String(details.refCount),
        },
        {
            label: t("referral_eligible"),
            value: String(details.refUpgradeCount),
        },
        ...(details.hasAppliedCode
            ? [{ label: t("referral_claimed_by_you"), value: "1" }]
            : []),
        {
            label: t("referral_earned"),
            value: formatStorage(referralView.claimedStorage),
        },
        { label: t("referral_usable"), value: formatStorage(usableStorage) },
    ];

    return (
        <>
            <Stack
                divider={<RowButtonDivider />}
                sx={{ bgcolor: "fill.faint", borderRadius: 2 }}
            >
                {stats.map(({ label, value }) => (
                    <Stack
                        key={label}
                        direction="row"
                        aria-label={`${label}: ${value}`}
                        sx={{
                            alignItems: "center",
                            justifyContent: "space-between",
                            gap: 2,
                            px: 2,
                            py: 1.75,
                        }}
                    >
                        <Typography>{label}</Typography>
                        <Typography sx={{ fontWeight: "medium" }}>
                            {value}
                        </Typography>
                    </Stack>
                ))}
            </Stack>
            <Typography
                variant="small"
                sx={{ color: "text.faint", whiteSpace: "pre-line" }}
            >
                {t("referral_usable_info")}
            </Typography>
        </>
    );
};
