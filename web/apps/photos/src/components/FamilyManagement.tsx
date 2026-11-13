import { avatarTextColor } from "@/services/avatar";
import {
    createFamily,
    inviteFamilyMember,
    modifyFamilyMemberStorage,
    removeFamilyMember,
    revokeFamilyInvite,
} from "@/services/family";
import { ArrowRight01Icon, Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Avatar,
    Box,
    Dialog,
    DialogTitle,
    FormControlLabel,
    IconButton,
    InputBase,
    Radio,
    RadioGroup,
    Stack,
    styled,
    Typography,
} from "@mui/material";
import { ContextMenu, ContextMenuItem } from "ente-base/components/ContextMenu";
import {
    v2CancelButtonSx,
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2HelperSx,
    v2InputSx,
    v2PaperSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    TitledNestedSidebarDrawer,
    type NestedSidebarDrawerVisibilityProps,
} from "ente-base/components/mui/SidebarDrawer";
import { SidebarPanelContext } from "ente-base/components/mui/SidebarDrawerContext";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import { useBaseContext } from "ente-base/context";
import { isHTTPErrorWithStatus } from "ente-base/http";
import {
    uploadSheetMediaQuery,
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import { formattedStorageByteSize } from "ente-gallery/utils/units";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import { useUserDetailsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    familyUsage,
    isFamilyAdmin,
    isSubscriptionActivePaid,
    leaveFamily,
    pullUserDetails,
    type FamilyMember,
    type UserDetails,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import React, { useContext, useEffect, useId, useRef, useState } from "react";

type FamilyManagementProps = NestedSidebarDrawerVisibilityProps & {
    onShowPlanSelector: () => void;
};

export const FamilyManagement: React.FC<FamilyManagementProps> = ({
    open,
    onClose,
    onRootClose,
    onShowPlanSelector,
}) => {
    const { onGenericError, showMiniDialog } = useBaseContext();
    const settingsPanel = useContext(SidebarPanelContext);
    const userDetails = useUserDetailsSnapshot();
    const [inviteOpen, setInviteOpen] = useState(false);
    const [selectedMember, setSelectedMember] = useState<FamilyMember>();
    const [memberActionsAnchor, setMemberActionsAnchor] =
        useState<HTMLElement | null>(null);
    const [editingMember, setEditingMember] = useState<FamilyMember>();
    const [resendingID, setResendingID] = useState<string>();

    useEffect(() => {
        if (!open) return;
        void pullUserDetails().catch(onGenericError);
    }, [onGenericError, open]);

    const members = [...(userDetails?.familyData?.members ?? [])].sort(
        (a, b) => {
            if (a.status == "SELF") return -1;
            if (b.status == "SELF") return 1;
            if (a.status == "INVITED" && b.status != "INVITED") return 1;
            if (b.status == "INVITED" && a.status != "INVITED") return -1;
            return a.email.localeCompare(b.email);
        },
    );

    const isAdmin = userDetails ? isFamilyAdmin(userDetails) : false;

    const confirmRemove = (member: FamilyMember) => {
        const invited = member.status == "INVITED";
        showMiniDialog({
            title: t(invited ? "revoke_family_invite" : "remove_family_member"),
            message: t(
                invited
                    ? "revoke_family_invite_confirm"
                    : "remove_family_member_confirm",
                { email: member.email },
            ),
            continue: {
                text: t(invited ? "revoke" : "remove"),
                color: "critical",
                action: () =>
                    invited
                        ? revokeFamilyInvite(member.id)
                        : removeFamilyMember(member.id),
            },
        });
    };

    const resendInvite = async (member: FamilyMember) => {
        setResendingID(member.id);
        try {
            await inviteFamilyMember(member.email);
            setSelectedMember(undefined);
        } catch (e) {
            onGenericError(e);
        } finally {
            setResendingID(undefined);
        }
    };

    const confirmLeave = () =>
        showMiniDialog({
            title: t("leave_family_plan"),
            message: t("leave_family_plan_confirm"),
            continue: {
                text: t("leave"),
                color: "critical",
                action: async () => {
                    await leaveFamily();
                    onClose();
                },
            },
        });

    const showPlans = () => {
        onClose();
        onShowPlanSelector();
    };

    const content = (
        <>
            {!userDetails ? (
                <Stack
                    sx={{
                        height: 300,
                        placeContent: "center",
                        alignItems: "center",
                    }}
                >
                    <ActivityIndicator />
                </Stack>
            ) : members.length ? (
                <FamilyDashboard
                    {...{ userDetails, members, isAdmin }}
                    onInvite={() => setInviteOpen(true)}
                    onManage={(member, anchor) => {
                        setSelectedMember(member);
                        setMemberActionsAnchor(anchor);
                    }}
                    onLeave={confirmLeave}
                />
            ) : (
                <FamilyIntroduction
                    canCreate={isSubscriptionActivePaid(
                        userDetails.subscription,
                    )}
                    onContinue={() => setInviteOpen(true)}
                    onShowPlans={showPlans}
                />
            )}
        </>
    );

    return (
        <>
            {settingsPanel ? (
                <Dialog
                    open={open}
                    onClose={onClose}
                    container={settingsPanel}
                    aria-labelledby="family-dialog-title"
                    maxWidth={false}
                    sx={{ position: "absolute", inset: 0 }}
                    slotProps={{
                        backdrop: {
                            sx: {
                                position: "absolute",
                                bgcolor: "transparent",
                            },
                        },
                        paper: {
                            sx: {
                                m: 0,
                                width: "100%",
                                maxWidth: "none",
                                height: "100%",
                                maxHeight: "none",
                                borderRadius: "20px",
                                boxShadow: "none",
                                bgcolor: "background.paper",
                            },
                        },
                    }}
                >
                    <Stack sx={{ p: "36px", gap: "20px" }}>
                        <Typography
                            id="family-dialog-title"
                            component="h2"
                            sx={{
                                fontSize: 18,
                                lineHeight: "24px",
                                fontWeight: 600,
                            }}
                        >
                            {t("family")}
                        </Typography>
                        {content}
                    </Stack>
                </Dialog>
            ) : (
                <TitledNestedSidebarDrawer
                    {...{ open, onClose, onRootClose }}
                    anchor="right"
                    maxWidth="440px"
                    title={t("family")}
                    showBackButton
                >
                    <Box sx={{ px: 2, py: 1 }}>{content}</Box>
                </TitledNestedSidebarDrawer>
            )}
            <InviteMemberDialog
                open={inviteOpen}
                onClose={() => setInviteOpen(false)}
                create={!members.length}
            />
            <MemberActionsMenu
                anchorEl={memberActionsAnchor}
                member={selectedMember}
                resending={selectedMember?.id == resendingID}
                onClose={() => setSelectedMember(undefined)}
                onEdit={(member) => {
                    setSelectedMember(undefined);
                    setEditingMember(member);
                }}
                onRemove={(member) => {
                    setSelectedMember(undefined);
                    confirmRemove(member);
                }}
                onResend={(member) => void resendInvite(member)}
            />
            <StorageLimitDialog
                member={editingMember}
                color={
                    familyMemberColors[
                        members.findIndex(
                            (member) => member.id == editingMember?.id,
                        )
                    ] ?? familyMemberColors[0]!
                }
                totalStorage={
                    (userDetails?.familyData?.storage ?? 0) +
                    (userDetails?.storageBonus ?? 0)
                }
                onClose={() => setEditingMember(undefined)}
            />
        </>
    );
};

const FamilyIntroduction: React.FC<{
    canCreate: boolean;
    onContinue: () => void;
    onShowPlans: () => void;
}> = ({ canCreate, onContinue, onShowPlans }) => (
    <Stack sx={{ gap: "24px" }}>
        <Stack
            sx={{
                alignItems: "center",
                justifyContent: "center",
                minHeight: 216,
                bgcolor: "fill.faint",
                borderRadius: "16px",
                p: 3,
            }}
        >
            <Box
                component="img"
                alt=""
                src="/images/family-plan/1x.png"
                sx={{ height: 168, maxWidth: "100%", objectFit: "contain" }}
            />
        </Stack>
        <Stack sx={{ gap: "8px", textAlign: "center", alignItems: "center" }}>
            <Typography
                component="h3"
                sx={{ fontSize: 24, lineHeight: "32px", fontWeight: 600 }}
            >
                {t("family_plan")}
            </Typography>
            <Typography
                sx={{
                    maxWidth: 360,
                    fontSize: 14,
                    lineHeight: "22px",
                    color: "text.muted",
                }}
            >
                {t("family_plan_description")}
            </Typography>
        </Stack>
        <FocusVisibleButton
            color="accent"
            fullWidth
            sx={{ ...v2SubmitButtonSx, flex: "none", fontWeight: 600 }}
            onClick={canCreate ? onContinue : onShowPlans}
        >
            {t(canCreate ? "add_family_member" : "view_plans")}
        </FocusVisibleButton>
    </Stack>
);

interface FamilyDashboardProps {
    userDetails: UserDetails;
    members: FamilyMember[];
    isAdmin: boolean;
    onInvite: () => void;
    onManage: (member: FamilyMember, anchor: HTMLElement) => void;
    onLeave: () => void;
}

const familyMemberColors = [
    "#df61bb",
    "#f24822",
    "#08c225",
    "#9610d6",
    "#087aff",
    "#f0a01e",
];
const familyStorageColors = [
    "#08c225",
    "#f08a1e",
    "#9610d6",
    "#087aff",
    "#df61bb",
    "#f0a01e",
];

const FamilyDashboard: React.FC<FamilyDashboardProps> = ({
    userDetails,
    members,
    isAdmin,
    onInvite,
    onManage,
    onLeave,
}) => {
    const used = familyUsage(userDetails);
    const total =
        (userDetails.familyData?.storage ?? 0) + userDetails.storageBonus;

    return (
        <Stack sx={{ gap: "14px" }}>
            <Box
                sx={{
                    px: "20px",
                    py: "16px",
                    bgcolor: "fill.faint",
                    borderRadius: "12px",
                }}
            >
                <Stack
                    direction="row"
                    sx={{
                        justifyContent: "space-between",
                        alignItems: "center",
                        gap: 1,
                        flexWrap: "wrap",
                    }}
                >
                    <Typography
                        sx={{
                            fontSize: 14,
                            lineHeight: "20px",
                            fontWeight: 600,
                        }}
                    >
                        {t("storage")}
                    </Typography>
                    <Typography
                        sx={{
                            fontSize: 12,
                            lineHeight: "16px",
                            fontWeight: 500,
                        }}
                    >
                        {t("family_storage_usage", {
                            used: formattedStorageByteSize(used),
                            total: formattedStorageByteSize(total),
                        })}
                    </Typography>
                </Stack>
                <Box
                    sx={{
                        display: "flex",
                        mt: 1.5,
                        height: 5,
                        bgcolor: "background.paper",
                        borderRadius: 1,
                        overflow: "hidden",
                    }}
                >
                    {members.map((member, index) =>
                        member.status == "INVITED" ? null : (
                            <Box
                                key={member.id}
                                sx={{
                                    flexShrink: 0,
                                    width: total
                                        ? `${Math.min(((member.usage ?? 0) / total) * 100, 100)}%`
                                        : 0,
                                    bgcolor: familyStorageColors[index],
                                    borderRadius: "35px",
                                }}
                            />
                        ),
                    )}
                </Box>
                <Stack
                    direction="row"
                    sx={{ mt: 1.5, gap: 1.25, flexWrap: "wrap" }}
                >
                    {members.map((member, index) =>
                        member.status == "INVITED" ? null : (
                            <Stack
                                key={member.id}
                                direction="row"
                                sx={{
                                    alignItems: "center",
                                    gap: "3px",
                                    minWidth: 0,
                                }}
                            >
                                <Box
                                    sx={{
                                        width: 7,
                                        height: 7,
                                        borderRadius: "50%",
                                        flexShrink: 0,
                                        bgcolor: familyStorageColors[index],
                                    }}
                                />
                                <Typography
                                    sx={{
                                        fontSize: 10,
                                        lineHeight: "14px",
                                        fontWeight: 500,
                                        color: "text.muted",
                                        overflowWrap: "anywhere",
                                    }}
                                >
                                    {member.status == "SELF"
                                        ? t("you")
                                        : member.email}
                                </Typography>
                            </Stack>
                        ),
                    )}
                </Stack>
            </Box>
            <Typography
                sx={{ fontSize: 14, lineHeight: "20px", fontWeight: 600 }}
            >
                {t("family_members")}
            </Typography>
            <Stack sx={{ gap: 1 }}>
                {members.map((member, index) => (
                    <FamilyMemberRow
                        key={member.id}
                        {...{ member, isAdmin, onManage }}
                        color={familyMemberColors[index]!}
                    />
                ))}
            </Stack>
            {isAdmin ? (
                members.length < 6 && (
                    <FocusVisibleButton
                        color="accent"
                        fullWidth
                        sx={{
                            ...v2SubmitButtonSx,
                            flex: "none",
                            fontWeight: 600,
                        }}
                        onClick={onInvite}
                    >
                        {t("add_member")}
                    </FocusVisibleButton>
                )
            ) : (
                <FocusVisibleButton color="critical" onClick={onLeave}>
                    {t("leave_family_plan")}
                </FocusVisibleButton>
            )}
        </Stack>
    );
};

const FamilyMemberRow: React.FC<{
    member: FamilyMember;
    isAdmin: boolean;
    color: string;
    onManage: (member: FamilyMember, anchor: HTMLElement) => void;
}> = ({ member, isAdmin, color, onManage }) => {
    const invited = member.status == "INVITED";
    const manageable = isAdmin && member.status != "SELF" && !member.isAdmin;
    const content = (
        <Stack
            direction="row"
            sx={{
                height: 60,
                boxSizing: "border-box",
                px: 1.5,
                py: 1.25,
                borderRadius: "20px",
                gap: 1.5,
                alignItems: "center",
            }}
        >
            <Box
                sx={{
                    width: 36,
                    display: "flex",
                    justifyContent: "center",
                    flexShrink: 0,
                }}
            >
                <Avatar
                    sx={{
                        width: 24,
                        height: 24,
                        bgcolor: color,
                        color: avatarTextColor,
                        fontSize: 12,
                        fontWeight: 500,
                    }}
                >
                    {member.email[0]?.toUpperCase()}
                </Avatar>
            </Box>
            <Stack sx={{ flex: 1, minWidth: 0, gap: 0.5 }}>
                <Typography
                    noWrap
                    sx={{ fontSize: 14, lineHeight: "20px", fontWeight: 500 }}
                >
                    {member.email}
                </Typography>
                <Typography
                    noWrap
                    sx={{
                        fontSize: 12,
                        lineHeight: "16px",
                        fontWeight: 500,
                        color: "text.muted",
                    }}
                >
                    {invited
                        ? t("family_invite_pending")
                        : member.storageLimit != undefined
                          ? t("family_storage_usage", {
                                used: formattedStorageByteSize(
                                    member.usage ?? 0,
                                ),
                                total: formattedStorageByteSize(
                                    member.storageLimit,
                                ),
                            })
                          : t("family_member_storage_used", {
                                usage: formattedStorageByteSize(
                                    member.usage ?? 0,
                                ),
                            })}
                </Typography>
            </Stack>
            {manageable && (
                <Box
                    sx={{
                        width: 48,
                        height: 36,
                        display: "grid",
                        placeItems: "center",
                        flexShrink: 0,
                    }}
                >
                    <HugeiconsIcon
                        icon={ArrowRight01Icon}
                        size={24}
                        aria-hidden
                    />
                </Box>
            )}
        </Stack>
    );

    return manageable ? (
        <FocusVisibleButton
            fullWidth
            aria-haspopup="menu"
            onClick={(event) => onManage(member, event.currentTarget)}
            sx={{
                display: "block",
                p: 0,
                color: "text.base",
                bgcolor: "transparent",
                textAlign: "left",
                textTransform: "none",
                borderRadius: "20px",
                "&:hover": { bgcolor: "fill.faintHover" },
            }}
        >
            {content}
        </FocusVisibleButton>
    ) : (
        content
    );
};

const MemberActionsMenu: React.FC<{
    anchorEl: HTMLElement | null;
    member?: FamilyMember;
    resending: boolean;
    onClose: () => void;
    onEdit: (member: FamilyMember) => void;
    onRemove: (member: FamilyMember) => void;
    onResend: (member: FamilyMember) => void;
}> = ({ anchorEl, member, resending, onClose, onEdit, onRemove, onResend }) => {
    const invited = member?.status == "INVITED";
    return (
        <ContextMenu
            sx={{ "& .MuiMenuItem-root": { fontSize: 14, lineHeight: "20px" } }}
            anchorEl={anchorEl}
            open={!!member}
            onClose={onClose}
            anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
            transformOrigin={{ vertical: "top", horizontal: "right" }}
            slotProps={{
                list: { "aria-label": member?.email, "aria-busy": resending },
            }}
        >
            <ContextMenuItem
                disabled={resending}
                onClick={() => {
                    if (member) {
                        if (invited) onResend(member);
                        else onEdit(member);
                    }
                }}
            >
                {t(invited ? "resend_family_invite" : "set_storage_limit")}
                {resending && <ActivityIndicator size="16px" sx={{ ml: 1 }} />}
            </ContextMenuItem>
            <ContextMenuItem
                disabled={resending}
                destructive
                onClick={() => {
                    if (member) onRemove(member);
                }}
            >
                {t(invited ? "revoke_family_invite" : "remove_family_member")}
            </ContextMenuItem>
        </ContextMenu>
    );
};

const InviteMemberDialog: React.FC<
    ModalVisibilityProps & { create: boolean }
> = ({ open, onClose, create }) => {
    const { onGenericError } = useBaseContext();
    const isSheet = useIsUploadSheet();
    const titleID = useId();
    const helperID = useId();
    const submitting = useRef(false);
    const [email, setEmail] = useState("");
    const [error, setError] = useState("");
    const [loading, setLoading] = useState(false);

    useEffect(() => {
        if (open) {
            setEmail("");
            setError("");
        }
    }, [open]);

    const submit = async () => {
        if (submitting.current) return;
        const normalizedEmail = email.trim().toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
            setError(t("enter_valid_email"));
            return;
        }
        submitting.current = true;
        setLoading(true);
        try {
            if (create) await createFamily();
            await inviteFamilyMember(normalizedEmail);
            onClose();
        } catch (e) {
            const errorKey = inviteErrorKey(e);
            if (errorKey) setError(t(errorKey));
            else onGenericError(e);
        } finally {
            submitting.current = false;
            setLoading(false);
        }
    };

    return (
        <Dialog
            open={open}
            onClose={loading ? undefined : onClose}
            aria-labelledby={titleID}
            aria-busy={loading}
            maxWidth={false}
            slots={isSheet ? { transition: SlideUpTransition } : undefined}
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(v2PaperSx) ? v2PaperSx : [v2PaperSx]),
                        {
                            width: "min(420px, calc(100svw - 32px))",
                            maxWidth: 420,
                            boxSizing: "border-box",
                        },
                        uploadSheetPaperSx,
                    ],
                },
            }}
        >
            <Stack
                component="form"
                noValidate
                onSubmit={(event) => {
                    event.preventDefault();
                    void submit();
                }}
                sx={{
                    p: "20px",
                    gap: "16px",
                    [uploadSheetMediaQuery]: {
                        pb: "calc(20px + env(safe-area-inset-bottom, 0px))",
                    },
                }}
            >
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <DialogTitle
                        id={titleID}
                        sx={{
                            "&&": { p: 0 },
                            fontFamily: "inherit",
                            fontSize: 20,
                            lineHeight: "28px",
                            fontWeight: 600,
                        }}
                    >
                        {t("add_family_member")}
                    </DialogTitle>
                    <IconButton
                        aria-label={t("close")}
                        disabled={loading}
                        onClick={onClose}
                        sx={v2CloseButtonSx}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={18} />
                    </IconButton>
                </Stack>
                <InputBase
                    autoFocus
                    name="email"
                    type="email"
                    autoComplete="email"
                    placeholder="name@example.com"
                    value={email}
                    disabled={loading}
                    error={!!error}
                    aria-label={t("enter_email")}
                    aria-describedby={helperID}
                    sx={[
                        ...(isSxArray(v2InputSx) ? v2InputSx : [v2InputSx]),
                        { boxSizing: "border-box", fontFamily: "inherit" },
                    ]}
                    onChange={(event) => {
                        setEmail(event.target.value);
                        setError("");
                    }}
                />
                <Typography
                    id={helperID}
                    aria-live="polite"
                    sx={[
                        v2HelperSx(!!error),
                        {
                            fontSize: 12,
                            lineHeight: "17px",
                            fontWeight: 400,
                            ...(!error && { color: "text.muted" }),
                        },
                    ]}
                >
                    {error || t("family_invite_hint")}
                </Typography>
                <Stack direction="row" sx={{ gap: "12px" }}>
                    <FocusVisibleButton
                        disabled={loading}
                        onClick={onClose}
                        sx={[
                            v2CancelButtonSx,
                            { minWidth: 0, fontWeight: 600 },
                        ]}
                    >
                        {t("cancel")}
                    </FocusVisibleButton>
                    <LoadingButton
                        type="submit"
                        disabled={loading}
                        loading={loading}
                        sx={{
                            ...v2SubmitButtonSx,
                            minWidth: 0,
                            fontWeight: 600,
                        }}
                    >
                        {t("invite")}
                    </LoadingButton>
                </Stack>
            </Stack>
        </Dialog>
    );
};

const inviteErrorKey = (error: unknown) => {
    if (isHTTPErrorWithStatus(error, 404)) return "family_user_not_found";
    if (isHTTPErrorWithStatus(error, 406)) return "family_already_member";
    if (isHTTPErrorWithStatus(error, 409)) return "family_paid_subscriber";
    if (isHTTPErrorWithStatus(error, 412)) return "family_size_limit";
    if (isHTTPErrorWithStatus(error, 402)) return "family_paid_plan_required";
    return undefined;
};

const StorageLimitDialog: React.FC<{
    member?: FamilyMember;
    color: string;
    totalStorage: number;
    onClose: () => void;
}> = ({ member, color, totalStorage, onClose }) => {
    const { onGenericError } = useBaseContext();
    const [value, setValue] = useState("");
    const [error, setError] = useState("");
    const [loading, setLoading] = useState(false);
    const [limited, setLimited] = useState(false);

    useEffect(() => {
        setLimited(member?.storageLimit != undefined);
        setValue(String((member?.storageLimit ?? totalStorage) / 1024 ** 3));
        setError("");
    }, [member, totalStorage]);

    const save = async () => {
        if (loading || !member) return;
        const storageLimit = limited
            ? Math.round(Number(value) * 1024 ** 3)
            : null;
        if (
            storageLimit != null &&
            (!value.trim() ||
                !Number.isFinite(storageLimit) ||
                storageLimit < (member.usage ?? 0) ||
                storageLimit > totalStorage)
        ) {
            setError(t("family_storage_limit_invalid"));
            return;
        }
        setLoading(true);
        try {
            await modifyFamilyMemberStorage(member.id, storageLimit);
            onClose();
        } catch (e) {
            if (isHTTPErrorWithStatus(e, 426))
                setError(t("family_storage_limit_invalid"));
            else onGenericError(e);
        } finally {
            setLoading(false);
        }
    };

    return (
        <Dialog
            open={!!member}
            onClose={loading ? undefined : onClose}
            aria-labelledby="storage-limit-title"
            maxWidth="xs"
            fullWidth
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(v2PaperSx) ? v2PaperSx : [v2PaperSx]),
                        {
                            width: 420,
                            maxWidth: "calc(100% - 32px)",
                            boxSizing: "border-box",
                            p: "20px",
                            gap: 2,
                        },
                    ],
                },
            }}
        >
            <Stack direction="row" sx={v2HeaderRowSx}>
                <DialogTitle
                    id="storage-limit-title"
                    sx={{
                        "&&": { p: 0 },
                        flex: 1,
                        fontSize: 20,
                        lineHeight: "28px",
                        fontWeight: 600,
                    }}
                >
                    {t("storage_limit")}
                </DialogTitle>
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    disabled={loading}
                    sx={v2CloseButtonSx}
                >
                    <HugeiconsIcon icon={Cancel01Icon} size={18} />
                </IconButton>
            </Stack>
            <Stack
                component="form"
                onSubmit={(event) => {
                    event.preventDefault();
                    void save();
                }}
                noValidate
                sx={{ gap: 2 }}
            >
                <Stack
                    direction="row"
                    sx={{
                        alignItems: "center",
                        gap: 1.5,
                        p: 1.5,
                        minHeight: 60,
                        borderRadius: "20px",
                        bgcolor: "background.paper",
                    }}
                >
                    <Box
                        sx={{
                            width: 36,
                            display: "flex",
                            justifyContent: "center",
                            flexShrink: 0,
                        }}
                    >
                        <Avatar
                            sx={{
                                width: 24,
                                height: 24,
                                bgcolor: color,
                                color: avatarTextColor,
                                fontSize: 12,
                                fontWeight: 500,
                            }}
                        >
                            {member?.email[0]?.toUpperCase()}
                        </Avatar>
                    </Box>
                    <Stack sx={{ minWidth: 0, gap: 0.5 }}>
                        <Typography
                            variant="small"
                            noWrap
                            sx={{
                                fontSize: 14,
                                fontWeight: 500,
                                lineHeight: "20px",
                            }}
                        >
                            {member?.email}
                        </Typography>
                        <Typography
                            variant="mini"
                            sx={{
                                color: "text.muted",
                                fontWeight: 500,
                                lineHeight: "16px",
                            }}
                        >
                            {t("family_member_using_storage", {
                                usage: formattedStorageByteSize(
                                    member?.usage ?? 0,
                                ),
                            })}
                        </Typography>
                    </Stack>
                </Stack>
                <RadioGroup
                    aria-labelledby="storage-limit-title"
                    name="storage-limit"
                    value={limited ? "limited" : "unlimited"}
                    onChange={(_, value) => {
                        setLimited(value == "limited");
                        setError("");
                    }}
                    sx={{
                        gap: 1.5,
                        "& .MuiFormControlLabel-root": { m: 0, gap: 1.5 },
                        "& .MuiFormControlLabel-label": {
                            fontSize: 14,
                            lineHeight: "20px",
                            fontWeight: 500,
                        },
                        "& .MuiRadio-root": {
                            p: 0,
                            "&.Mui-focusVisible": {
                                outline: "2px solid",
                                outlineColor: "accent.main",
                                outlineOffset: 3,
                            },
                        },
                    }}
                >
                    <FormControlLabel
                        value="unlimited"
                        disabled={loading}
                        control={
                            <Radio
                                icon={<StorageLimitRadioIcon />}
                                checkedIcon={<StorageLimitRadioIcon />}
                            />
                        }
                        label={t("no_limit")}
                        sx={{
                            p: "14px",
                            borderRadius: "20px",
                            bgcolor: "background.paper",
                        }}
                    />
                    <Stack
                        direction="row"
                        onClick={() => {
                            if (!loading) {
                                setLimited(true);
                                setError("");
                            }
                        }}
                        sx={{
                            alignItems: "center",
                            gap: 1.5,
                            px: "14px",
                            py: "6px",
                            borderRadius: "20px",
                            bgcolor: "background.paper",
                        }}
                    >
                        <FormControlLabel
                            value="limited"
                            disabled={loading}
                            control={
                                <Radio
                                    icon={<StorageLimitRadioIcon />}
                                    checkedIcon={<StorageLimitRadioIcon />}
                                />
                            }
                            label={t("storage_limit_up_to")}
                        />
                        <InputBase
                            type="number"
                            value={value}
                            disabled={loading}
                            error={!!error}
                            onFocus={() => setLimited(true)}
                            slotProps={{
                                input: {
                                    "aria-label": t("storage_limit_gb"),
                                    "aria-describedby": error
                                        ? "storage-limit-error"
                                        : undefined,
                                    min: (member?.usage ?? 0) / 1024 ** 3,
                                    max: totalStorage / 1024 ** 3,
                                    step: "any",
                                },
                            }}
                            onChange={(e) => {
                                setValue(e.target.value);
                                setError("");
                            }}
                            sx={[
                                ...(isSxArray(v2InputSx)
                                    ? v2InputSx
                                    : [v2InputSx]),
                                {
                                    width: 100,
                                    minWidth: 0,
                                    height: 36,
                                    boxSizing: "border-box",
                                    borderRadius: "12px",
                                    px: "12px",
                                    bgcolor: "fill.faint",
                                    borderColor: "stroke.muted",
                                    "& input::-webkit-inner-spin-button, & input::-webkit-outer-spin-button":
                                        { WebkitAppearance: "none", m: 0 },
                                    "& input": { MozAppearance: "textfield" },
                                },
                            ]}
                        />
                        <Typography
                            variant="small"
                            sx={{
                                color: "text.muted",
                                fontSize: 14,
                                fontWeight: 500,
                            }}
                        >
                            GB
                        </Typography>
                    </Stack>
                </RadioGroup>
                {!!error && (
                    <Typography
                        id="storage-limit-error"
                        role="alert"
                        variant="mini"
                        sx={v2HelperSx(true)}
                    >
                        {error}
                    </Typography>
                )}
                <Typography
                    variant="mini"
                    sx={{ color: "text.muted", lineHeight: "17px" }}
                >
                    {t("storage_limit_explanation")}
                </Typography>
                <Stack sx={{ gap: 1.5 }}>
                    <LoadingButton
                        fullWidth
                        type="submit"
                        loading={loading}
                        sx={{
                            ...v2SubmitButtonSx,
                            flex: "none",
                            fontWeight: 600,
                        }}
                    >
                        {t("save")}
                    </LoadingButton>
                    <FocusVisibleButton
                        fullWidth
                        disabled={loading}
                        onClick={onClose}
                        sx={[
                            v2CancelButtonSx,
                            { flex: "none", fontWeight: 600 },
                        ]}
                    >
                        {t("cancel")}
                    </FocusVisibleButton>
                </Stack>
            </Stack>
        </Dialog>
    );
};

const StorageLimitRadioIcon = styled("span")(({ theme }) => ({
    width: 16,
    height: 16,
    boxSizing: "border-box",
    border: "1px solid",
    borderColor: theme.vars.palette.text.faint,
    borderRadius: "50%",
    display: "grid",
    placeItems: "center",
    ".Mui-checked &": {
        borderColor: theme.vars.palette.accent.main,
        "&::after": {
            content: '""',
            width: 8,
            height: 8,
            borderRadius: "50%",
            backgroundColor: theme.vars.palette.accent.main,
        },
    },
    ".Mui-disabled &": { opacity: 0.5 },
}));
