import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import WarningAmberRoundedIcon from "@mui/icons-material/WarningAmberRounded";
import { Box, CircularProgress, Stack, Typography } from "@mui/material";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
    legacyChangePassword,
    legacyGetInfo,
    legacyRejectRecovery,
    legacyStartRecovery,
    legacyStopRecovery,
    legacyUpdateContact,
    legacyUpdateRecoveryNotice,
    type LegacyContactRecord,
    type LegacyInfo,
    type LegacyRecoverySession,
    type LegacySuggestedUser,
} from "..";
import { mergeLegacySuggestedUsers } from "../suggestions";
import { ActionButton } from "./ActionButton";
import { LegacyActionSheet } from "./LegacyActionSheet";
import { LegacyAddContactContent } from "./LegacyAddContactContent";
import { LegacyIdentityRow } from "./LegacyIdentityRow";
import { LegacyRecoveryDayPicker } from "./LegacyRecoveryDayPicker";
import { LegacyResetPasswordPage } from "./LegacyResetPasswordPage";
import { LegacyTrustedAccountPage } from "./LegacyTrustedAccountPage";
type ActiveSheet =
    | { kind: "add" }
    | { kind: "owner"; contact: LegacyContactRecord }
    | { kind: "trustedInvite"; contact: LegacyContactRecord }
    | { kind: "recovery"; session: LegacyRecoverySession }
    | undefined;

type ActivePage =
    | { kind: "trusted"; contact: LegacyContactRecord }
    | {
          kind: "resetPassword";
          contact: LegacyContactRecord;
          session: LegacyRecoverySession;
      }
    | undefined;

const pairKey = (userID: number, emergencyContactID: number) =>
    `${userID}:${emergencyContactID}`;

const isActiveRecoveryStatus = (status: LegacyRecoverySession["status"]) =>
    status === "WAITING" || status === "READY";

const preferredRecoverySession = (
    current: LegacyRecoverySession | undefined,
    candidate: LegacyRecoverySession,
) => {
    if (!current) {
        return candidate;
    }
    if (candidate.status === "READY" && current.status !== "READY") {
        return candidate;
    }
    if (candidate.status !== "READY" && current.status === "READY") {
        return current;
    }
    return candidate.createdAt >= current.createdAt ? candidate : current;
};

const formatWait = (session: LegacyRecoverySession) => {
    if (session.status === "READY" || session.waitTill <= 0) {
        return "Ready now";
    }
    const totalHours = Math.ceil(session.waitTill / (1000 * 1000 * 60 * 60));
    if (totalHours >= 24) {
        const days = Math.ceil(totalHours / 24);
        return `${days} day${days === 1 ? "" : "s"} remaining`;
    }
    return `${totalHours} hour${totalHours === 1 ? "" : "s"} remaining`;
};

const formatWaitDuration = (session: LegacyRecoverySession) => {
    if (session.status === "READY" || session.waitTill <= 0) {
        return "now";
    }
    const totalHours = Math.ceil(session.waitTill / (1000 * 1000 * 60 * 60));
    if (totalHours >= 24) {
        const days = Math.ceil(totalHours / 24);
        return `${days} day${days === 1 ? "" : "s"}`;
    }
    return `${totalHours} hour${totalHours === 1 ? "" : "s"}`;
};

const ownerMessage = (contact: LegacyContactRecord) => {
    const email = contact.emergencyContact.email;
    switch (contact.state) {
        case "ACCEPTED":
            return `You have added ${email} as a trusted contact. They have accepted your invite.`;
        case "INVITED":
            return `You have invited ${email} to be a trusted contact. They are yet to accept your invite.`;
        case "CONTACT_DENIED":
            return `${email} declined your trusted-contact invite.`;
        case "CONTACT_LEFT":
            return `${email} removed themselves as your trusted contact.`;
        case "REVOKED":
            return `You removed ${email} from your trusted contacts.`;
    }
};

const recoveryAttemptMessage = (session: LegacyRecoverySession) => {
    const email = session.emergencyContact.email;
    if (session.status === "READY") {
        return `${email} is ready to recover your account.`;
    }
    return `${email} is trying to recover your account. ${formatWait(session)}.`;
};

const attentionIndicator = (
    <WarningAmberRoundedIcon
        sx={{ fontSize: 18, color: "warning.main", flexShrink: 0 }}
    />
);

const sectionTitleSx = {
    color: "text.muted",
    fontSize: 18,
    lineHeight: "24px",
    fontWeight: 500,
};

const groupedCardSx = {
    p: 0.5,
    borderRadius: "20px",
    backgroundColor: "fill.faint",
};

const warningBannerSx = {
    p: 2,
    gap: 1.5,
    borderRadius: "18px",
    backgroundColor: "rgba(255, 82, 82, 0.14)",
};

const getErrorMessage = (error: unknown) =>
    error instanceof Error ? error.message : "Something went wrong";

interface LegacyDrawerContentProps {
    open: boolean;
    suggestedUsers?: LegacySuggestedUser[];
}

interface ConfirmActionDialogInput {
    title: string;
    message: React.ReactNode;
    continueText: string;
    continueColor?: "accent" | "critical" | "primary" | "secondary";
    action: () => Promise<void>;
}

export const LegacyDrawerContent: React.FC<LegacyDrawerContentProps> = ({
    open,
    suggestedUsers = [],
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const [info, setInfo] = useState<LegacyInfo | undefined>();
    const [isLoading, setIsLoading] = useState(false);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [activeSheet, setActiveSheet] = useState<ActiveSheet>();
    const [activePage, setActivePage] = useState<ActivePage>();
    const [selectedOwnerDays, setSelectedOwnerDays] = useState(14);

    const loadInfo = useCallback(
        async (reportErrors: boolean) => {
            setIsLoading(true);
            try {
                setInfo(await legacyGetInfo());
                return true;
            } catch (error) {
                if (reportErrors) {
                    onGenericError(error);
                } else {
                    log.error(
                        "Legacy refresh failed after successful mutation",
                        error,
                    );
                }
                return false;
            } finally {
                setIsLoading(false);
            }
        },
        [onGenericError],
    );

    const refresh = useCallback(async () => {
        await loadInfo(true);
    }, [loadInfo]);

    useEffect(() => {
        if (open) {
            void refresh();
        } else {
            setInfo(undefined);
            setIsLoading(false);
            setIsSubmitting(false);
            setActiveSheet(undefined);
            setActivePage(undefined);
        }
    }, [open, refresh]);

    useEffect(() => {
        const selectedOwnerContact =
            activeSheet?.kind === "owner" ? activeSheet.contact : undefined;
        setSelectedOwnerDays(selectedOwnerContact?.recoveryNoticeInDays ?? 14);
    }, [activeSheet]);

    const activeRecoveriesByPair = useMemo(() => {
        const map = new Map<string, LegacyRecoverySession>();
        for (const session of info?.othersRecoverySession ?? []) {
            if (!isActiveRecoveryStatus(session.status)) {
                continue;
            }
            const key = pairKey(session.user.id, session.emergencyContact.id);
            map.set(key, preferredRecoverySession(map.get(key), session));
        }
        return map;
    }, [info?.othersRecoverySession]);

    const existingEmails = useMemo(
        () =>
            info?.contacts.map((contact) => contact.emergencyContact.email) ??
            [],
        [info?.contacts],
    );

    const addScreenSuggestedUsers = useMemo(() => {
        return mergeLegacySuggestedUsers(
            suggestedUsers,
            info?.othersEmergencyContact.map((contact) => ({
                id: contact.user.id,
                email: contact.user.email,
            })),
        );
    }, [info?.othersEmergencyContact, suggestedUsers]);

    const selectedOwnerContact =
        activeSheet?.kind === "owner" ? activeSheet.contact : undefined;
    const selectedTrustedInvite =
        activeSheet?.kind === "trustedInvite" ? activeSheet.contact : undefined;
    const selectedTrustedContact =
        activePage?.kind === "trusted" || activePage?.kind === "resetPassword"
            ? activePage.contact
            : undefined;
    const selectedRecoveryAttempt =
        activeSheet?.kind === "recovery" ? activeSheet.session : undefined;
    const isAddSheetOpen = activeSheet?.kind === "add";

    const selectedTrustedRecovery = useMemo(() => {
        if (!selectedTrustedContact) {
            return undefined;
        }
        return activeRecoveriesByPair.get(
            pairKey(
                selectedTrustedContact.user.id,
                selectedTrustedContact.emergencyContact.id,
            ),
        );
    }, [activeRecoveriesByPair, selectedTrustedContact]);

    const hasOverviewEntries = Boolean(
        info?.recoverSessions.length ||
        info?.contacts.length ||
        info?.othersEmergencyContact.length,
    );

    const refreshAfterMutation = useCallback(async () => {
        await loadInfo(false);
    }, [loadInfo]);

    const runAction = useCallback(
        async (
            action: () => Promise<unknown>,
            onSuccess?: () => void | Promise<void>,
        ) => {
            let didSucceed = false;
            try {
                setIsSubmitting(true);
                await action();
                didSucceed = true;
                await onSuccess?.();
            } catch (error) {
                onGenericError(error);
            } finally {
                setIsSubmitting(false);
            }
            if (didSucceed) {
                await refreshAfterMutation();
            }
        },
        [onGenericError, refreshAfterMutation],
    );

    const confirmAction = useCallback(
        ({
            title,
            message,
            continueText,
            continueColor = "critical",
            action,
        }: ConfirmActionDialogInput) => {
            showMiniDialog({
                title,
                message,
                continue: {
                    text: continueText,
                    color: continueColor,
                    action: async () => {
                        await action();
                        await refreshAfterMutation();
                    },
                },
            });
        },
        [refreshAfterMutation, showMiniDialog],
    );

    const handleSaveRecoveryNotice = useCallback(async () => {
        if (!selectedOwnerContact) {
            return;
        }
        setIsSubmitting(true);
        try {
            await legacyUpdateRecoveryNotice(
                selectedOwnerContact.emergencyContact.id,
                selectedOwnerDays,
            );
            setActiveSheet(undefined);
            await refreshAfterMutation();
        } catch (error) {
            const message = getErrorMessage(error);
            if (message.includes("active recovery session")) {
                showMiniDialog({
                    title: "Recovery in progress",
                    message:
                        "You cannot change the recovery notice while an active recovery attempt exists for this contact.",
                });
            } else {
                onGenericError(error);
            }
        } finally {
            setIsSubmitting(false);
        }
    }, [
        onGenericError,
        refreshAfterMutation,
        selectedOwnerContact,
        selectedOwnerDays,
        showMiniDialog,
    ]);

    const resetPasswordPage =
        activePage?.kind === "resetPassword" ? activePage : undefined;
    const trustedWaitLabel = selectedTrustedRecovery
        ? formatWaitDuration(selectedTrustedRecovery)
        : undefined;

    return (
        <>
            {activePage?.kind === "trusted" && selectedTrustedContact ? (
                <LegacyTrustedAccountPage
                    contact={selectedTrustedContact}
                    activeRecovery={selectedTrustedRecovery}
                    isSubmitting={isSubmitting}
                    waitLabel={trustedWaitLabel}
                    onBack={() => setActivePage(undefined)}
                    onStartRecovery={() =>
                        confirmAction({
                            title: "Start recovery",
                            message: `Are you sure you want to initiate recovery for ${selectedTrustedContact.user.email}'s account?`,
                            continueText: "Start recovery",
                            continueColor: "accent",
                            action: async () => {
                                await legacyStartRecovery(
                                    selectedTrustedContact.user.id,
                                    selectedTrustedContact.emergencyContact.id,
                                );
                            },
                        })
                    }
                    onRecoverAccount={() => {
                        if (!selectedTrustedRecovery) {
                            return;
                        }
                        setActivePage({
                            kind: "resetPassword",
                            contact: selectedTrustedContact,
                            session: selectedTrustedRecovery,
                        });
                    }}
                    onCancelRecovery={() => {
                        if (!selectedTrustedRecovery) {
                            return;
                        }
                        confirmAction({
                            title: "Cancel recovery",
                            message: `Are you sure you want to cancel recovery of ${selectedTrustedContact.user.email}'s account?`,
                            continueText: "Cancel recovery",
                            action: async () => {
                                await legacyStopRecovery(
                                    selectedTrustedRecovery.id,
                                    selectedTrustedRecovery.user.id,
                                    selectedTrustedRecovery.emergencyContact.id,
                                );
                            },
                        });
                    }}
                    onRemoveContact={() =>
                        confirmAction({
                            title: "Remove contact",
                            message: `If you remove yourself as a trusted contact, you'll lose access to ${selectedTrustedContact.user.email}'s account after their inactivity period.`,
                            continueText: "Remove contact",
                            action: async () => {
                                await legacyUpdateContact(
                                    selectedTrustedContact.user.id,
                                    selectedTrustedContact.emergencyContact.id,
                                    "CONTACT_LEFT",
                                );
                                setActivePage(undefined);
                            },
                        })
                    }
                />
            ) : resetPasswordPage ? (
                <LegacyResetPasswordPage
                    session={resetPasswordPage.session}
                    isSubmitting={isSubmitting}
                    onBack={() =>
                        setActivePage({
                            kind: "trusted",
                            contact: resetPasswordPage.contact,
                        })
                    }
                    onSubmit={async (password) => {
                        setIsSubmitting(true);
                        try {
                            await legacyChangePassword(
                                resetPasswordPage.session.id,
                                password,
                            );
                            setActivePage(undefined);
                            showMiniDialog({
                                title: "Account recovered",
                                message: `You can now sign in to ${resetPasswordPage.session.user.email} with the new password.`,
                                cancel: "Done",
                            });
                            void refreshAfterMutation();
                        } finally {
                            setIsSubmitting(false);
                        }
                    }}
                />
            ) : (
                <Stack sx={{ px: 2, pt: 2, pb: 2, gap: 2.5 }}>
                    {isLoading && !info ? (
                        <Stack
                            sx={{
                                alignItems: "center",
                                justifyContent: "center",
                                py: 6,
                                color: "text.muted",
                                gap: 1.5,
                            }}
                        >
                            <CircularProgress size={24} />
                            <Typography variant="small">
                                Loading Legacy information
                            </Typography>
                        </Stack>
                    ) : (
                        <>
                            {!!info?.recoverSessions.length && (
                                <Stack sx={{ gap: 2 }}>
                                    <Stack direction="row" sx={warningBannerSx}>
                                        <WarningAmberRoundedIcon
                                            sx={{
                                                fontSize: 28,
                                                color: "warning.main",
                                                flexShrink: 0,
                                                mt: 0.25,
                                            }}
                                        />
                                        <Typography
                                            variant="body"
                                            sx={{
                                                color: "warning.main",
                                                fontWeight: 700,
                                                lineHeight: 1.35,
                                            }}
                                        >
                                            A trusted contact is trying to
                                            access your account
                                        </Typography>
                                    </Stack>
                                    <Stack sx={groupedCardSx}>
                                        {info.recoverSessions.map(
                                            (session, index) => (
                                                <Box
                                                    key={session.id}
                                                    sx={{
                                                        pt:
                                                            index === 0
                                                                ? 0
                                                                : 0.75,
                                                        borderTop:
                                                            index === 0
                                                                ? undefined
                                                                : "1px solid",
                                                        borderColor: "divider",
                                                    }}
                                                >
                                                    <LegacyIdentityRow
                                                        email={
                                                            session
                                                                .emergencyContact
                                                                .email
                                                        }
                                                        userID={
                                                            session
                                                                .emergencyContact
                                                                .id
                                                        }
                                                        primaryColor="warning.main"
                                                        action={
                                                            <ChevronRightIcon
                                                                sx={{
                                                                    color: "text.muted",
                                                                }}
                                                            />
                                                        }
                                                        onClick={() =>
                                                            setActiveSheet({
                                                                kind: "recovery",
                                                                session,
                                                            })
                                                        }
                                                    />
                                                </Box>
                                            ),
                                        )}
                                    </Stack>
                                </Stack>
                            )}

                            {!!info?.contacts.length && (
                                <Stack sx={{ gap: 1 }}>
                                    <Typography sx={sectionTitleSx}>
                                        Trusted contacts
                                    </Typography>
                                    <Stack sx={groupedCardSx}>
                                        {info.contacts.map((contact, index) => (
                                            <Box
                                                key={pairKey(
                                                    contact.user.id,
                                                    contact.emergencyContact.id,
                                                )}
                                                sx={{
                                                    pt: index === 0 ? 0 : 0.75,
                                                    borderTop:
                                                        index === 0
                                                            ? undefined
                                                            : "1px solid",
                                                    borderColor: "divider",
                                                }}
                                            >
                                                <LegacyIdentityRow
                                                    email={
                                                        contact.emergencyContact
                                                            .email
                                                    }
                                                    userID={
                                                        contact.emergencyContact
                                                            .id
                                                    }
                                                    statusIndicator={
                                                        contact.state ===
                                                        "ACCEPTED"
                                                            ? undefined
                                                            : attentionIndicator
                                                    }
                                                    action={
                                                        <ChevronRightIcon
                                                            sx={{
                                                                color: "text.muted",
                                                            }}
                                                        />
                                                    }
                                                    onClick={() =>
                                                        setActiveSheet({
                                                            kind: "owner",
                                                            contact,
                                                        })
                                                    }
                                                />
                                            </Box>
                                        ))}
                                    </Stack>
                                </Stack>
                            )}

                            <ActionButton
                                fullWidth
                                buttonType="primary"
                                loading={isLoading}
                                disabled={!info || isSubmitting}
                                onClick={() => setActiveSheet({ kind: "add" })}
                            >
                                Add trusted contact
                            </ActionButton>

                            {!!info?.othersEmergencyContact.length && (
                                <>
                                    <Box
                                        sx={{
                                            mt: 0.5,
                                            borderTop: "1px solid",
                                            borderColor: "divider",
                                        }}
                                    />
                                    <Stack sx={{ gap: 1 }}>
                                        <Typography sx={sectionTitleSx}>
                                            Legacy accounts
                                        </Typography>
                                        <Stack sx={groupedCardSx}>
                                            {info.othersEmergencyContact.map(
                                                (contact, index) => {
                                                    const activeRecovery =
                                                        activeRecoveriesByPair.get(
                                                            pairKey(
                                                                contact.user.id,
                                                                contact
                                                                    .emergencyContact
                                                                    .id,
                                                            ),
                                                        );
                                                    return (
                                                        <Box
                                                            key={pairKey(
                                                                contact.user.id,
                                                                contact
                                                                    .emergencyContact
                                                                    .id,
                                                            )}
                                                            sx={{
                                                                pt:
                                                                    index === 0
                                                                        ? 0
                                                                        : 0.75,
                                                                borderTop:
                                                                    index === 0
                                                                        ? undefined
                                                                        : "1px solid",
                                                                borderColor:
                                                                    "divider",
                                                            }}
                                                        >
                                                            <LegacyIdentityRow
                                                                email={
                                                                    contact.user
                                                                        .email
                                                                }
                                                                userID={
                                                                    contact.user
                                                                        .id
                                                                }
                                                                statusIndicator={
                                                                    contact.state !==
                                                                        "ACCEPTED" ||
                                                                    !!activeRecovery
                                                                        ? attentionIndicator
                                                                        : undefined
                                                                }
                                                                action={
                                                                    <ChevronRightIcon
                                                                        sx={{
                                                                            color: "text.muted",
                                                                        }}
                                                                    />
                                                                }
                                                                onClick={() =>
                                                                    contact.state ===
                                                                    "INVITED"
                                                                        ? setActiveSheet(
                                                                              {
                                                                                  kind: "trustedInvite",
                                                                                  contact,
                                                                              },
                                                                          )
                                                                        : setActivePage(
                                                                              {
                                                                                  kind: "trusted",
                                                                                  contact,
                                                                              },
                                                                          )
                                                                }
                                                            />
                                                        </Box>
                                                    );
                                                },
                                            )}
                                        </Stack>
                                    </Stack>
                                </>
                            )}

                            {!hasOverviewEntries && !!info && (
                                <Typography
                                    variant="small"
                                    sx={{
                                        color: "text.muted",
                                        textAlign: "center",
                                        py: 1,
                                    }}
                                >
                                    No Legacy activity yet.
                                </Typography>
                            )}
                        </>
                    )}
                </Stack>
            )}

            <LegacyActionSheet
                open={isAddSheetOpen}
                title="Add trusted contact"
                onClose={() => setActiveSheet(undefined)}
            >
                <LegacyAddContactContent
                    variant="sheet"
                    suggestedUsers={addScreenSuggestedUsers}
                    existingEmails={existingEmails}
                    onAdded={async () => {
                        setActiveSheet(undefined);
                        await refreshAfterMutation();
                    }}
                />
            </LegacyActionSheet>

            <LegacyActionSheet
                open={!!selectedOwnerContact}
                title={selectedOwnerContact?.emergencyContact.email ?? ""}
                subtitle={
                    selectedOwnerContact
                        ? ownerMessage(selectedOwnerContact)
                        : undefined
                }
                onClose={() => setActiveSheet(undefined)}
            >
                {selectedOwnerContact &&
                    (selectedOwnerContact.state === "INVITED" ||
                        selectedOwnerContact.state === "ACCEPTED") && (
                        <Stack sx={{ gap: 2 }}>
                            <LegacyRecoveryDayPicker
                                selectedDays={selectedOwnerDays}
                                onChange={setSelectedOwnerDays}
                            />
                            <ActionButton
                                fullWidth
                                buttonType="primary"
                                loading={isSubmitting}
                                disabled={
                                    isSubmitting ||
                                    selectedOwnerDays ===
                                        selectedOwnerContact.recoveryNoticeInDays
                                }
                                onClick={() => void handleSaveRecoveryNotice()}
                            >
                                Update time
                            </ActionButton>
                            <ActionButton
                                buttonType="tertiaryCritical"
                                onClick={() =>
                                    confirmAction({
                                        title:
                                            selectedOwnerContact.state ===
                                            "INVITED"
                                                ? "Cancel invite"
                                                : "Remove contact",
                                        message:
                                            selectedOwnerContact.state ===
                                            "INVITED"
                                                ? "If you delete this invite, you'll need to send a new one if you change your mind."
                                                : "If you delete this contact, you'll need to send a new invitation, and the contact will have to accept it again.",
                                        continueText:
                                            selectedOwnerContact.state ===
                                            "INVITED"
                                                ? "Revoke invite"
                                                : "Remove contact",
                                        action: async () => {
                                            await legacyUpdateContact(
                                                selectedOwnerContact.user.id,
                                                selectedOwnerContact
                                                    .emergencyContact.id,
                                                "REVOKED",
                                            );
                                            setActiveSheet(undefined);
                                        },
                                    })
                                }
                                disabled={isSubmitting}
                            >
                                {selectedOwnerContact.state === "INVITED"
                                    ? "Revoke invite"
                                    : "Remove"}
                            </ActionButton>
                        </Stack>
                    )}
            </LegacyActionSheet>

            <LegacyActionSheet
                open={!!selectedTrustedInvite}
                title={selectedTrustedInvite?.user.email ?? ""}
                subtitle={
                    selectedTrustedInvite
                        ? `${selectedTrustedInvite.user.email} has invited you to be a trusted contact.`
                        : undefined
                }
                onClose={() => setActiveSheet(undefined)}
            >
                {selectedTrustedInvite && (
                    <Stack sx={{ gap: 1.5 }}>
                        <ActionButton
                            fullWidth
                            buttonType="primary"
                            loading={isSubmitting}
                            onClick={() =>
                                void runAction(
                                    () =>
                                        legacyUpdateContact(
                                            selectedTrustedInvite.user.id,
                                            selectedTrustedInvite
                                                .emergencyContact.id,
                                            "ACCEPTED",
                                        ),
                                    () => setActiveSheet(undefined),
                                )
                            }
                        >
                            Accept invite
                        </ActionButton>
                        <ActionButton
                            buttonType="tertiaryCritical"
                            onClick={() =>
                                void runAction(
                                    () =>
                                        legacyUpdateContact(
                                            selectedTrustedInvite.user.id,
                                            selectedTrustedInvite
                                                .emergencyContact.id,
                                            "CONTACT_DENIED",
                                        ),
                                    () => setActiveSheet(undefined),
                                )
                            }
                            disabled={isSubmitting}
                        >
                            Decline invite
                        </ActionButton>
                    </Stack>
                )}
            </LegacyActionSheet>

            <LegacyActionSheet
                open={!!selectedRecoveryAttempt}
                title={selectedRecoveryAttempt?.emergencyContact.email ?? ""}
                subtitle={
                    selectedRecoveryAttempt
                        ? recoveryAttemptMessage(selectedRecoveryAttempt)
                        : undefined
                }
                onClose={() => setActiveSheet(undefined)}
            >
                {selectedRecoveryAttempt && (
                    <ActionButton
                        fullWidth
                        buttonType="critical"
                        onClick={() =>
                            confirmAction({
                                title: "Reject recovery",
                                message: recoveryAttemptMessage(
                                    selectedRecoveryAttempt,
                                ),
                                continueText: "Reject recovery",
                                action: async () => {
                                    await legacyRejectRecovery(
                                        selectedRecoveryAttempt.id,
                                        selectedRecoveryAttempt.user.id,
                                        selectedRecoveryAttempt.emergencyContact
                                            .id,
                                    );
                                    setActiveSheet(undefined);
                                },
                            })
                        }
                        disabled={isSubmitting}
                    >
                        Reject recovery
                    </ActionButton>
                )}
            </LegacyActionSheet>
        </>
    );
};
