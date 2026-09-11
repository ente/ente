import { FormField } from "@/components/ui/FormField";
import {
    LockerMenuOption,
    LockerOverflowMenu,
} from "@/components/ui/LockerMenu";
import {
    canLeaveCollection,
    canManageCollectionSharing,
    type LockerCollection,
    type LockerCollectionParticipant,
} from "@/types";
import LogoutOutlinedIcon from "@mui/icons-material/LogoutOutlined";
import {
    Avatar,
    Box,
    Button,
    CircularProgress,
    Dialog,
    DialogContent,
    DialogTitle,
    Stack,
    Typography,
    type Theme,
} from "@mui/material";
import { savedLocalUser } from "ente-accounts/services/accounts-db";
import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import {
    useResolvedContactAvatar,
    useResolvedContactDisplay,
} from "ente-contacts";
import { t } from "i18next";
import React, { useEffect, useMemo, useState } from "react";
import {
    lockerSheetContainerSx,
    lockerSheetPaperSx,
} from "../../styles/dialog";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextBodySx,
    lockerTextH2Sx,
    lockerTextMiniSx,
} from "../../styles/tokens";
import {
    LockerSidebarDrawer,
    LockerSidebarTitlebar,
} from "../sidebar/LockerSidebarShell";
import { LockerConfirmDialog } from "../ui/LockerConfirmDialog";

interface LockerCollectionShareDrawerProps {
    open: boolean;
    collection: LockerCollection | null;
    onClose: () => void;
    onShareCollection: (collectionID: number, email: string) => Promise<void>;
    onUnshareCollection: (collectionID: number, email: string) => Promise<void>;
    onLeaveCollection: (collection: LockerCollection) => void;
    onRefreshSharees?: (
        collectionID: number,
    ) => Promise<LockerCollectionParticipant[]>;
    warmContacts: () => Promise<void>;
}

const primaryButtonSx = (theme: Theme) => ({
    ...lockerTextBodyBoldSx,
    minHeight: 52,
    borderRadius: "20px",
    ...lockerColorSx(theme, {
        backgroundColor: "primary",
        color: "specialWhite",
    }),
    "&:hover": lockerColorSx(theme, { backgroundColor: "primaryDark" }),
});

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const LockerCollectionShareDrawer: React.FC<
    LockerCollectionShareDrawerProps
> = ({
    open,
    collection,
    onClose,
    onShareCollection,
    onUnshareCollection,
    onLeaveCollection,
    onRefreshSharees,
    warmContacts,
}) => {
    const currentUser = savedLocalUser() ?? { id: Number.NaN, email: "" };
    const [sharees, setSharees] = useState<LockerCollectionParticipant[]>([]);
    const [isRefreshingSharees, setIsRefreshingSharees] = useState(false);
    const [addViewerOpen, setAddViewerOpen] = useState(false);
    const [viewerEmail, setViewerEmail] = useState("");
    const [viewerEmailError, setViewerEmailError] = useState<string | null>(
        null,
    );
    const [isSubmittingViewer, setIsSubmittingViewer] = useState(false);
    const [participantToRemove, setParticipantToRemove] =
        useState<LockerCollectionParticipant>();
    const [isRemovingViewer, setIsRemovingViewer] = useState(false);
    const [removeViewerError, setRemoveViewerError] = useState<string>();

    useEffect(() => {
        setParticipantToRemove(undefined);
        setRemoveViewerError(undefined);
    }, [collection?.id, open]);

    const ownerEmail =
        collection?.owner.email?.trim() ||
        (collection?.owner.id === currentUser.id ? currentUser.email : "");
    const canManageParticipants = !!(
        collection && canManageCollectionSharing(collection, currentUser.id)
    );
    const canLeaveSharedCollection = !!(
        collection && canLeaveCollection(collection, currentUser.id)
    );

    useEffect(() => {
        if (!open || !collection) {
            setAddViewerOpen(false);
            setViewerEmail("");
            setViewerEmailError(null);
            setIsSubmittingViewer(false);
            setSharees([]);
            return;
        }

        setSharees(collection.sharees);
    }, [collection, open]);

    useEffect(() => {
        if (
            !open ||
            !collection ||
            !onRefreshSharees ||
            (!collection.isShared &&
                !collection.sharees.some((participant) => !participant.email))
        ) {
            return;
        }

        let cancelled = false;
        setIsRefreshingSharees(true);
        void onRefreshSharees(collection.id)
            .then((nextSharees) => {
                if (!cancelled) {
                    setSharees(nextSharees);
                }
            })
            .catch((error: unknown) => {
                log.error(
                    `[LockerCollectionShareDrawer] Failed to refresh sharees for ${collection.id}`,
                    error,
                );
            })
            .finally(() => {
                if (!cancelled) {
                    setIsRefreshingSharees(false);
                }
            });

        return () => {
            cancelled = true;
        };
    }, [collection, onRefreshSharees, open]);

    useEffect(() => {
        if (!open) {
            return;
        }

        void warmContacts().catch((error: unknown) => {
            log.warn(
                "[LockerCollectionShareDrawer] Failed to warm contacts display cache",
                error,
            );
        });
    }, [open, warmContacts]);

    const sortedSharees = useMemo(
        () =>
            [...sharees].sort((a, b) => {
                if (a.id === currentUser.id && b.id !== currentUser.id)
                    return -1;
                if (a.id !== currentUser.id && b.id === currentUser.id)
                    return 1;
                return (a.email ?? "").localeCompare(b.email ?? "");
            }),
        [currentUser.id, sharees],
    );

    const handleCloseAddViewer = () => {
        if (isSubmittingViewer) {
            return;
        }
        setAddViewerOpen(false);
        setViewerEmail("");
        setViewerEmailError(null);
    };

    const handleAddViewer = async () => {
        if (!collection) {
            return;
        }

        const normalizedEmail = viewerEmail.trim().toLowerCase();

        if (!normalizedEmail) {
            setViewerEmailError(t("enterViewerEmail"));
            return;
        }
        if (!EMAIL_PATTERN.test(normalizedEmail)) {
            setViewerEmailError(t("enterValidEmail"));
            return;
        }
        if (normalizedEmail === currentUser.email.toLowerCase()) {
            setViewerEmailError(t("cannotShareWithYourself"));
            return;
        }
        if (
            sortedSharees.some(
                (sharee) => sharee.email?.toLowerCase() === normalizedEmail,
            )
        ) {
            setViewerEmailError(t("viewerAlreadyHasAccess"));
            return;
        }

        setIsSubmittingViewer(true);
        setViewerEmailError(null);
        try {
            await onShareCollection(collection.id, normalizedEmail);
            handleCloseAddViewer();
        } catch (error) {
            if (isHTTPErrorWithStatus(error, 402)) {
                setViewerEmailError(t("sharingRequiresPaidPlan"));
            } else if (isHTTPErrorWithStatus(error, 404)) {
                setViewerEmailError(t("viewerEmailNotOnEnte"));
            } else if (error instanceof Error) {
                setViewerEmailError(error.message);
            } else {
                setViewerEmailError(t("failedToShareCollection"));
            }
        } finally {
            setIsSubmittingViewer(false);
        }
    };

    const handleRemoveViewer = async () => {
        if (!collection || !participantToRemove?.email || isRemovingViewer)
            return;
        const email = participantToRemove.email;
        setIsRemovingViewer(true);
        setRemoveViewerError(undefined);
        try {
            await onUnshareCollection(collection.id, email);
            setSharees((current) =>
                current.filter(
                    (sharee) =>
                        sharee.email?.toLowerCase() !== email.toLowerCase(),
                ),
            );
            setParticipantToRemove(undefined);
        } catch (error) {
            log.error("Failed to remove Locker collection participant", error);
            setRemoveViewerError(t("generic_error"));
        } finally {
            setIsRemovingViewer(false);
        }
    };

    if (!collection) {
        return null;
    }

    const participants = [
        {
            participant: {
                id: collection.owner.id,
                email: ownerEmail || t("unknownEmail"),
            },
            subtitle: t("owner"),
            action: undefined,
        },
        ...sortedSharees.map((participant) => ({
            participant,
            subtitle:
                participant.id === currentUser.id
                    ? t("sharedWithYou")
                    : undefined,
            action:
                canManageParticipants &&
                participant.id !== currentUser.id &&
                participant.email ? (
                    <LockerOverflowMenu
                        ariaID={`sharee-${participant.id}`}
                        triggerButtonSxProps={(theme) => ({
                            "&&": {
                                width: 36,
                                height: 36,
                                p: 0,
                                borderRadius: "12px",
                                backgroundColor: "transparent",
                            },
                            flexShrink: 0,
                            ...lockerColorSx(theme, { color: "textLight" }),
                            "&&:hover": lockerColorSx(theme, {
                                backgroundColor: "fillHover",
                            }),
                        })}
                    >
                        <LockerMenuOption
                            critical
                            onClick={() => {
                                setRemoveViewerError(undefined);
                                setParticipantToRemove(participant);
                            }}
                        >
                            {t("removeParticipant")}
                        </LockerMenuOption>
                    </LockerOverflowMenu>
                ) : undefined,
        })),
    ];

    return (
        <>
            <LockerSidebarDrawer anchor="right" open={open} onClose={onClose}>
                <Stack sx={{ height: "100%", minHeight: 0 }}>
                    <LockerSidebarTitlebar
                        title={collection.name}
                        tooltip={collection.name}
                        onClose={onClose}
                        closeLabel={t("close")}
                    />
                    <Stack
                        sx={{
                            px: 2,
                            gap: 2,
                            flex: 1,
                            minHeight: 0,
                            overflowY: "auto",
                            overscrollBehavior: "contain",
                            WebkitOverflowScrolling: "touch",
                            pb: "max(16px, env(safe-area-inset-bottom))",
                        }}
                    >
                        <Typography
                            sx={(theme) => ({
                                ...lockerTextBodySx,
                                ...lockerColorSx(theme, { color: "textLight" }),
                            })}
                        >
                            {t("sharedWith")}
                        </Typography>
                        {isRefreshingSharees && (
                            <Stack
                                direction="row"
                                sx={{
                                    alignItems: "center",
                                    justifyContent: "flex-end",
                                    px: 0.5,
                                }}
                            >
                                <CircularProgress size={16} />
                            </Stack>
                        )}

                        <Stack sx={{ gap: 1, flexShrink: 0 }}>
                            {participants.map((row, index) => (
                                <ParticipantRow
                                    key={`${row.participant.id}-${row.participant.email ?? index}`}
                                    participant={row.participant}
                                    subtitle={row.subtitle}
                                    action={row.action}
                                />
                            ))}
                        </Stack>

                        {sortedSharees.length === 0 && (
                            <Typography
                                variant="small"
                                sx={(theme) => ({
                                    ...lockerTextBodySx,
                                    ...lockerColorSx(theme, {
                                        color: "textLight",
                                    }),
                                })}
                            >
                                {t("noSharedUsers")}
                            </Typography>
                        )}

                        {canManageParticipants && (
                            <Button
                                variant="contained"
                                onClick={() => setAddViewerOpen(true)}
                                sx={(theme) => ({
                                    ...primaryButtonSx(theme),
                                    textTransform: "none",
                                })}
                            >
                                {t("addEmail")}
                            </Button>
                        )}

                        {canLeaveSharedCollection && (
                            <Button
                                color="primary"
                                variant="contained"
                                startIcon={<LogoutOutlinedIcon />}
                                onClick={() => onLeaveCollection(collection)}
                                sx={(theme) => ({
                                    ...primaryButtonSx(theme),
                                    textTransform: "none",
                                })}
                            >
                                {t("leaveCollection")}
                            </Button>
                        )}
                    </Stack>
                </Stack>
            </LockerSidebarDrawer>

            <LockerConfirmDialog
                open={!!participantToRemove}
                illustration="/images/warning-red.png"
                title={t("removeParticipant")}
                body={t("removeParticipantConfirmation", {
                    email: participantToRemove?.email ?? "",
                })}
                confirmLabel={t("remove")}
                loading={isRemovingViewer}
                error={removeViewerError}
                onClose={() => setParticipantToRemove(undefined)}
                onConfirm={handleRemoveViewer}
            />
            <Dialog
                slotProps={{
                    paper: { sx: lockerSheetPaperSx },
                    container: { sx: lockerSheetContainerSx },
                }}
                open={addViewerOpen}
                onClose={handleCloseAddViewer}
                fullWidth
                maxWidth="xs"
            >
                <DialogTitle
                    sx={(theme) => ({
                        ...lockerTextH2Sx,
                        "&&&": { p: 0 },
                        minHeight: 38,
                        display: "flex",
                        alignItems: "center",
                        mb: 2.5,
                        ...lockerColorSx(theme, { color: "textBase" }),
                    })}
                >
                    {t("addEmail")}
                </DialogTitle>
                <DialogContent sx={{ "&&&": { p: 0 } }}>
                    <Stack sx={{ gap: 3 }}>
                        <FormField
                            type="email"
                            label={t("enterEmail")}
                            value={viewerEmail}
                            onChange={(event) => {
                                setViewerEmail(event.target.value);
                                setViewerEmailError(null);
                            }}
                            autoFocus
                            fullWidth
                            error={!!viewerEmailError}
                            helperText={viewerEmailError ?? undefined}
                            onKeyDown={(event) => {
                                if (event.key === "Enter") {
                                    void handleAddViewer();
                                }
                            }}
                        />
                        <Stack direction="row" sx={{ gap: 1 }}>
                            <Button
                                fullWidth
                                color="secondary"
                                onClick={handleCloseAddViewer}
                                disabled={isSubmittingViewer}
                                sx={(theme) => ({
                                    ...lockerTextBodyBoldSx,
                                    minHeight: 52,
                                    borderRadius: "20px",
                                    ...lockerColorSx(theme, {
                                        backgroundColor: "fillDark",
                                        color: "textBase",
                                    }),
                                })}
                            >
                                {t("cancel")}
                            </Button>
                            <Button
                                fullWidth
                                variant="contained"
                                onClick={() => void handleAddViewer()}
                                disabled={isSubmittingViewer}
                                sx={(theme) => ({
                                    ...primaryButtonSx(theme),
                                    "&.Mui-disabled": lockerColorSx(theme, {
                                        backgroundColor: "fillDarkest",
                                        color: "textLighter",
                                    }),
                                })}
                            >
                                {isSubmittingViewer
                                    ? t("sharing")
                                    : t("addEmail")}
                            </Button>
                        </Stack>
                    </Stack>
                </DialogContent>
            </Dialog>
        </>
    );
};

const ParticipantRow: React.FC<{
    participant: LockerCollectionParticipant;
    subtitle?: string;
    action?: React.ReactNode;
}> = ({ participant, subtitle, action }) => {
    const email = participant.email ?? t("unknownEmail");
    const resolvedDisplay = useResolvedContactDisplay({
        userID: participant.id,
        email: participant.email,
    });
    const resolved = useResolvedContactAvatar({
        userID: participant.id,
        email: participant.email,
    });
    const label = resolvedDisplay.primaryLabel || email;
    const initial =
        resolved.source === "contact"
            ? resolved.initial
            : email.charAt(0).toUpperCase() || "?";

    return (
        <Stack
            direction="row"
            sx={(theme) => ({
                alignItems: "center",
                gap: 1.5,
                p: 1.5,
                minHeight: 64,
                borderRadius: "20px",
                ...lockerColorSx(theme, { backgroundColor: "fillLight" }),
            })}
        >
            <Avatar
                sx={(theme) => ({
                    width: 40,
                    height: 40,
                    borderRadius: "12px",
                    flexShrink: 0,
                    ...lockerTextBodyBoldSx,
                    ...lockerColorSx(theme, {
                        backgroundColor: "backgroundBase",
                        color: "textLight",
                    }),
                })}
                src={resolved.avatarURL}
            >
                {initial}
            </Avatar>
            <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography
                    sx={(theme) => ({
                        ...lockerTextBodySx,
                        ...lockerColorSx(theme, { color: "textBase" }),
                    })}
                    title={label}
                    noWrap
                >
                    {label}
                </Typography>
                {subtitle && (
                    <Typography
                        variant="small"
                        sx={(theme) => ({
                            ...lockerTextMiniSx,
                            mt: 0.5,
                            ...lockerColorSx(theme, { color: "textLight" }),
                        })}
                        noWrap
                    >
                        {subtitle}
                    </Typography>
                )}
            </Box>
            {action}
        </Stack>
    );
};
