import { recoveryKeyMnemonic } from "@/services/authenticated-session";
import {
    Box,
    Button,
    CircularProgress,
    Stack,
    Typography,
} from "@mui/material";
import { CopyButton } from "ente-accounts/components/CodeBlock";
import {
    RecoveryKeyContents,
    type RecoveryKeyPresentationProps,
} from "ente-accounts/components/RecoveryKey";
import { useBaseContext } from "ente-base/context";
import { t } from "i18next";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";
import {
    bodyBoldSx,
    fillDarkSx,
    miniSx,
    textBaseSx,
    textLightSx,
} from "./locker-sidebar-styles";

export function LockerRecoveryKeyDrawer({
    open,
    onClose,
    onRootClose,
}: LockerNestedSidebarDrawerVisibilityProps) {
    const { showMiniDialog } = useBaseContext();
    return (
        <LockerTitledNestedSidebarDrawer
            {...{ open, onClose, onRootClose }}
            title={t("recovery_key")}
        >
            <RecoveryKeyContents
                {...{ open, onClose, showMiniDialog }}
                getRecoveryKeyMnemonic={recoveryKeyMnemonic}
                presentation={LockerRecoveryKeyPresentation}
            />
        </LockerTitledNestedSidebarDrawer>
    );
}

function LockerRecoveryKeyPresentation({
    recoveryKey,
    onClose,
    onSave,
}: RecoveryKeyPresentationProps) {
    return (
        <Stack sx={{ flex: 1 }}>
            <Typography sx={[miniSx, textLightSx]}>
                {t("recovery_key_description")}
            </Typography>
            <Box
                sx={{
                    mt: 3,
                    borderRadius: "16px",
                    bgcolor: "accent.main",
                    color: "#fff",
                    p: "24px 64px 24px 22px",
                    position: "relative",
                }}
            >
                {recoveryKey === undefined ? (
                    <Box
                        sx={{
                            display: "flex",
                            justifyContent: "center",
                            mr: "-42px",
                        }}
                    >
                        <CircularProgress size={24} color="inherit" />
                    </Box>
                ) : (
                    <>
                        <Typography
                            sx={{
                                fontFamily: "ui-monospace, Menlo, monospace",
                                fontSize: 14,
                                lineHeight: "21px",
                                letterSpacing: ".5px",
                                textAlign: "justify",
                            }}
                        >
                            {recoveryKey}
                        </Typography>
                        <Box
                            sx={{
                                position: "absolute",
                                right: 8,
                                top: 8,
                                width: 40,
                                height: 40,
                                display: "grid",
                                placeItems: "center",
                                color: "#fff",
                                "& .MuiIconButton-root, & svg": {
                                    color: "inherit",
                                },
                            }}
                        >
                            <CopyButton code={recoveryKey} />
                        </Box>
                    </>
                )}
            </Box>
            <Typography sx={[miniSx, textLightSx, { mt: "20px" }]}>
                {t("key_not_stored_note")}
            </Typography>
            <Stack sx={{ mt: "auto", pt: 3, gap: 1 }}>
                <Button
                    fullWidth
                    disableElevation
                    variant="contained"
                    color="accent"
                    disabled={recoveryKey === undefined}
                    onClick={onSave}
                    sx={[
                        bodyBoldSx,
                        {
                            height: 52,
                            borderRadius: "20px",
                            bgcolor: "accent.main",
                            color: "#fff",
                        },
                    ]}
                >
                    {t("save_key")}
                </Button>
                <Button
                    fullWidth
                    disableElevation
                    onClick={onClose}
                    sx={[
                        bodyBoldSx,
                        fillDarkSx,
                        textBaseSx,
                        { height: 52, borderRadius: "20px" },
                    ]}
                >
                    {t("do_this_later")}
                </Button>
            </Stack>
        </Stack>
    );
}
