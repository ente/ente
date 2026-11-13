import { Stack, Typography } from "@mui/material";
import React from "react";
import type { LegacyContactRecord, LegacyRecoverySession } from "..";
import { ActionButton } from "./ActionButton";
import { LegacyPageFrame } from "./LegacyPageFrame";

interface LegacyTrustedAccountPageProps {
    contact: LegacyContactRecord;
    activeRecovery: LegacyRecoverySession | undefined;
    isSubmitting: boolean;
    waitLabel: string | undefined;
    onBack: () => void;
    onStartRecovery: () => void;
    onRecoverAccount: () => void;
    onCancelRecovery: () => void;
    onRemoveContact: () => void;
}

const trustedAccountDescription = (
    email: string,
    recoveryNoticeInDays: number,
    activeRecovery: LegacyRecoverySession | undefined,
    waitLabel: string | undefined,
) => {
    if (!activeRecovery) {
        return `You can recover ${email}'s account in ${recoveryNoticeInDays} days after starting the recovery process.`;
    }
    if (activeRecovery.status === "READY") {
        return `You can now recover ${email}'s account by setting a new password.`;
    }
    return `You can recover ${email}'s account after ${waitLabel}.`;
};

export const LegacyTrustedAccountPage: React.FC<
    LegacyTrustedAccountPageProps
> = ({
    contact,
    activeRecovery,
    isSubmitting,
    waitLabel,
    onBack,
    onStartRecovery,
    onRecoverAccount,
    onCancelRecovery,
    onRemoveContact,
}) => {
    const email = contact.user.email;
    const isReady = activeRecovery?.status === "READY";

    return (
        <LegacyPageFrame
            title="Recover account"
            caption={email}
            description={trustedAccountDescription(
                email,
                contact.recoveryNoticeInDays,
                activeRecovery,
                waitLabel,
            )}
            onBack={onBack}
        >
            <Stack sx={{ gap: 1.5, px: 0.5 }}>
                {!activeRecovery && (
                    <ActionButton
                        fullWidth
                        buttonType="primary"
                        loading={isSubmitting}
                        onClick={onStartRecovery}
                    >
                        Start recovery
                    </ActionButton>
                )}

                {isReady && (
                    <>
                        <ActionButton
                            fullWidth
                            buttonType="primary"
                            loading={isSubmitting}
                            onClick={onRecoverAccount}
                        >
                            Recover account
                        </ActionButton>
                        <ActionButton
                            buttonType="tertiaryCritical"
                            onClick={onCancelRecovery}
                            disabled={isSubmitting}
                            sx={{ alignSelf: "center" }}
                        >
                            Cancel recovery
                        </ActionButton>
                        <Typography
                            variant="body"
                            sx={{ color: "text.muted", lineHeight: 1.5, mt: 2 }}
                        >
                            Or remove yourself as {email}'s trusted contact
                        </Typography>
                        <ActionButton
                            fullWidth
                            buttonType="critical"
                            loading={isSubmitting}
                            onClick={onRemoveContact}
                        >
                            Remove contact
                        </ActionButton>
                    </>
                )}

                {activeRecovery && !isReady && (
                    <>
                        <ActionButton
                            fullWidth
                            buttonType="secondary"
                            loading={isSubmitting}
                            onClick={onCancelRecovery}
                        >
                            Cancel recovery
                        </ActionButton>
                        <ActionButton
                            fullWidth
                            buttonType="critical"
                            loading={isSubmitting}
                            onClick={onRemoveContact}
                            sx={{ mt: 1 }}
                        >
                            Remove contact
                        </ActionButton>
                    </>
                )}

                {!activeRecovery && (
                    <ActionButton
                        fullWidth
                        buttonType="critical"
                        loading={isSubmitting}
                        onClick={onRemoveContact}
                        sx={{ mt: 1 }}
                    >
                        Remove contact
                    </ActionButton>
                )}
            </Stack>
        </LegacyPageFrame>
    );
};
