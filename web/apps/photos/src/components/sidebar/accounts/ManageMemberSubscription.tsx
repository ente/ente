import { Cancel01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Avatar, Dialog, IconButton, Stack, Typography } from "@mui/material";
import {
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2PaperSx,
} from "ente-base/components/SingleInput.styles";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import { useBaseContext } from "ente-base/context";
import {
    uploadSheetMediaQuery,
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import {
    familyAdminEmail,
    leaveFamily,
    type UserDetails,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import React, { useId } from "react";

type ManageMemberSubscriptionProps = ModalVisibilityProps & {
    userDetails: UserDetails;
};

export const ManageMemberSubscription: React.FC<
    ManageMemberSubscriptionProps
> = ({ open, onClose, userDetails }) => {
    const { showMiniDialog } = useBaseContext();
    const isSheet = useIsUploadSheet();
    const titleID = useId();
    const adminEmail = familyAdminEmail(userDetails) ?? "";

    const confirmLeaveFamily = () =>
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

    return (
        <Dialog
            {...{ open, onClose }}
            maxWidth={false}
            aria-labelledby={titleID}
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
                sx={{
                    p: "20px",
                    gap: "20px",
                    [uploadSheetMediaQuery]: {
                        pb: "calc(20px + env(safe-area-inset-bottom, 0px))",
                    },
                }}
            >
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <Typography
                        component="h2"
                        id={titleID}
                        sx={{
                            fontSize: 20,
                            lineHeight: "28px",
                            fontWeight: 600,
                        }}
                    >
                        {t("subscription")}
                    </Typography>
                    <IconButton
                        aria-label={t("close")}
                        onClick={onClose}
                        sx={v2CloseButtonSx}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={18} />
                    </IconButton>
                </Stack>
                <Typography
                    sx={{
                        fontSize: 12,
                        lineHeight: "18px",
                        color: "text.muted",
                    }}
                >
                    {t("family_plan")}
                </Typography>
                <Stack
                    direction="row"
                    sx={(theme) => ({
                        alignItems: "center",
                        gap: 1.5,
                        p: 2,
                        borderRadius: "16px",
                        bgcolor: "background.paper",
                        ...theme.applyStyles("dark", { bgcolor: "#282828" }),
                    })}
                >
                    <Avatar
                        sx={(theme) => ({
                            width: 36,
                            height: 36,
                            fontSize: 14,
                            bgcolor: "#f5d4ee",
                            color: "text.base",
                            ...theme.applyStyles("dark", {
                                bgcolor: "#55334e",
                            }),
                        })}
                    >
                        {adminEmail[0]?.toUpperCase()}
                    </Avatar>
                    <Stack sx={{ minWidth: 0, gap: 0.5 }}>
                        <Typography
                            sx={{
                                fontSize: 12,
                                lineHeight: "18px",
                                color: "text.muted",
                            }}
                        >
                            {t("subscription_info_family")}
                        </Typography>
                        <Typography
                            sx={{
                                fontSize: 14,
                                lineHeight: "20px",
                                fontWeight: 500,
                                overflowWrap: "anywhere",
                            }}
                        >
                            {adminEmail}
                        </Typography>
                    </Stack>
                </Stack>
                <Stack sx={{ gap: 1.5 }}>
                    <FocusVisibleButton
                        fullWidth
                        onClick={confirmLeaveFamily}
                        sx={(theme) => ({
                            height: 52,
                            borderRadius: "20px",
                            fontSize: 14,
                            lineHeight: "20px",
                            fontWeight: 600,
                            color: "critical.main",
                            bgcolor: "background.paper",
                            "&:hover": { bgcolor: "fill.faintHover" },
                            ...theme.applyStyles("dark", {
                                bgcolor: "#282828",
                            }),
                        })}
                    >
                        {t("leave_family_plan")}
                    </FocusVisibleButton>
                </Stack>
            </Stack>
        </Dialog>
    );
};
