import { Box, Dialog, DialogContent, Stack } from "@mui/material";
import Typography from "@mui/material/Typography";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import {
    familyAdminEmail,
    leaveFamily,
    type UserDetails,
} from "ente-new/photos/services/user-details";
import { t } from "i18next";
import React from "react";

type ManageMemberSubscriptionProps = ModalVisibilityProps & {
    userDetails: UserDetails;
};

export const ManageMemberSubscription: React.FC<
    ManageMemberSubscriptionProps
> = ({ open, onClose, userDetails }) => {
    const { showMiniDialog } = useBaseContext();
    const fullScreen = useIsSmallWidth();

    const confirmLeaveFamily = () =>
        showMiniDialog({
            title: t("leave_family_plan"),
            message: t("leave_family_plan_confirm"),
            continue: {
                text: t("leave"),
                color: "critical",
                action: leaveFamily,
            },
        });

    return (
        <Dialog
            {...{ open, onClose, fullScreen }}
            maxWidth="xs"
            fullWidth
            aria-labelledby="member-subscription-title"
            slotProps={{
                paper: { sx: { borderRadius: fullScreen ? 0 : "20px" } },
            }}
        >
            <SpacedRow
                sx={{
                    p: "24px 16px 16px 24px",
                    "& .MuiIconButton-root": { color: "text.muted" },
                }}
            >
                <Stack sx={{ gap: 0.5 }}>
                    <Typography variant="h2" id="member-subscription-title">
                        {t("subscription")}
                    </Typography>
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        {t("family_plan")}
                    </Typography>
                </Stack>
                <DialogCloseIconButton {...{ onClose }} />
            </SpacedRow>
            <DialogContent sx={{ "&&": { p: "8px 24px 24px" } }}>
                <Stack sx={{ gap: 3 }}>
                    <Box
                        sx={{
                            p: 2,
                            borderRadius: "16px",
                            bgcolor: "fill.faint",
                        }}
                    >
                        <Typography sx={{ color: "text.muted" }}>
                            {t("subscription_info_family")}
                        </Typography>
                        <Typography sx={{ mt: 0.5, overflowWrap: "anywhere" }}>
                            {familyAdminEmail(userDetails) ?? ""}
                        </Typography>
                    </Box>
                    <FocusVisibleButton
                        fullWidth
                        variant="contained"
                        color="critical"
                        onClick={confirmLeaveFamily}
                        sx={{ borderRadius: "20px", minHeight: 48 }}
                    >
                        {t("leave_family_plan")}
                    </FocusVisibleButton>
                </Stack>
            </DialogContent>
        </Dialog>
    );
};
