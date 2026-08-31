import {
    deletePasskey,
    getPasskeys,
    registerPasskey,
    renamePasskey,
    type Passkey,
} from "@/services/passkey";
import CalendarTodayIcon from "@mui/icons-material/CalendarToday";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import DeleteIcon from "@mui/icons-material/Delete";
import EditIcon from "@mui/icons-material/Edit";
import InfoIcon from "@mui/icons-material/Info";
import KeyIcon from "@mui/icons-material/Key";
import {
    Box,
    Paper,
    Stack,
    TextField,
    Typography,
    styled,
} from "@mui/material";
import { CenteredFill } from "ente-base/components/containers";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    SidebarDrawer,
    SidebarDrawerTitlebar,
} from "ente-base/components/mui/SidebarDrawer";
import { NavbarBase } from "ente-base/components/Navbar";
import {
    RowButton,
    RowButtonDivider,
    RowButtonGroup,
} from "ente-base/components/RowButton";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { errorDialogAttributes } from "ente-base/components/utils/dialog";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { isNamedError } from "ente-base/error";
import { formattedDateTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";

const AccountsPagePaper = styled(Paper)(({ theme }) => ({
    marginBlock: theme.spacing(2),
    padding: theme.spacing(5, 3),
    [theme.breakpoints.up("sm")]: { padding: theme.spacing(5) },
    width: "min(420px, 85vw)",
    display: "flex",
    flexDirection: "column",
    gap: theme.spacing(4),
    boxShadow: "none",
    borderRadius: "20px",
}));

const Page: React.FC = () => {
    const { showMiniDialog } = useBaseContext();

    const [token, setToken] = useState<string | undefined>();
    const [passkeys, setPasskeys] = useState<Passkey[]>([]);
    const [showPasskeyDrawer, setShowPasskeyDrawer] = useState(false);
    const [selectedPasskey, setSelectedPasskey] = useState<
        Passkey | undefined
    >();

    const showPasskeyFetchFailedErrorDialog = useCallback(() => {
        showMiniDialog(errorDialogAttributes(t("passkey_fetch_failed")));
    }, [showMiniDialog]);

    useEffect(() => {
        const urlParams = new URLSearchParams(window.location.search);

        const token = urlParams.get("token");
        if (token) {
            setToken(token);
        } else {
            log.error("Missing accounts token");
            showPasskeyFetchFailedErrorDialog();
        }
    }, [showPasskeyFetchFailedErrorDialog]);

    const refreshPasskeys = useCallback(async () => {
        try {
            const { accountsUrl, passkeys } = await getPasskeys(token!);

            const accountsURL = accountsUrl ? new URL(accountsUrl) : undefined;
            if (accountsURL && accountsURL.origin !== window.location.origin) {
                const redirectURL = new URL(accountsURL.href);
                if (!redirectURL.pathname.endsWith("/")) {
                    redirectURL.pathname += "/";
                }
                redirectURL.pathname += "passkeys";
                redirectURL.search = new URLSearchParams({
                    token: token!,
                }).toString();
                window.location.href = redirectURL.toString();
                return;
            }

            setPasskeys(passkeys);
        } catch (e) {
            log.error("Failed to fetch passkeys", e);
            showPasskeyFetchFailedErrorDialog();
        }
    }, [token, showPasskeyFetchFailedErrorDialog]);

    useEffect(() => {
        if (token) {
            void refreshPasskeys();
        }
    }, [token, refreshPasskeys]);

    const handleSelectPasskey = (passkey: Passkey) => {
        setSelectedPasskey(passkey);
        setShowPasskeyDrawer(true);
    };

    const handleDrawerClose = () => {
        setShowPasskeyDrawer(false);
        // The selected passkey is deliberately not cleared here so that the
        // drawer close animation looks right. The next open overwrites it.
    };

    const handleUpdateOrDeletePasskey = () => {
        setShowPasskeyDrawer(false);
        setSelectedPasskey(undefined);
        void refreshPasskeys();
    };

    return (
        <Stack
            sx={[
                { minHeight: "100svh", bgcolor: "#f5f5f5" },
                (theme) =>
                    theme.applyStyles("dark", {
                        bgcolor: "background.default",
                    }),
            ]}
        >
            <NavbarBase
                sx={{
                    boxShadow: "none",
                    borderBottom: "none",
                    bgcolor: "transparent",
                }}
            >
                <EnteLogo />
            </NavbarBase>
            <CenteredFill
                sx={[
                    { bgcolor: "#f5f5f5" },
                    (theme) =>
                        theme.applyStyles("dark", {
                            bgcolor: "background.default",
                        }),
                ]}
            >
                <AccountsPagePaper>
                    <Stack sx={{ gap: 2, alignItems: "flex-start" }}>
                        <InfoIcon
                            sx={[
                                { color: "text.secondary", fontSize: 40 },
                                (theme) =>
                                    theme.applyStyles("dark", {
                                        color: "text.muted",
                                    }),
                            ]}
                        />
                        <Typography
                            sx={[
                                { color: "text.secondary" },
                                (theme) =>
                                    theme.applyStyles("dark", {
                                        color: "text.muted",
                                    }),
                            ]}
                        >
                            {t("passkeys_description")}
                        </Typography>
                    </Stack>
                    <AddPasskeyForm
                        token={token!}
                        onRefreshPasskeys={refreshPasskeys}
                    />
                    <PasskeysList
                        passkeys={passkeys}
                        onSelectPasskey={handleSelectPasskey}
                    />
                </AccountsPagePaper>
            </CenteredFill>

            <ManagePasskeyDrawer
                open={showPasskeyDrawer}
                onClose={handleDrawerClose}
                passkey={selectedPasskey}
                token={token}
                onUpdateOrDeletePasskey={handleUpdateOrDeletePasskey}
            />
        </Stack>
    );
};

export default Page;

interface AddPasskeyFormProps {
    token: string;
    onRefreshPasskeys: () => Promise<void>;
}

const AddPasskeyForm: React.FC<AddPasskeyFormProps> = ({
    token,
    onRefreshPasskeys,
}) => {
    const formik = useFormik({
        initialValues: { value: "" },
        onSubmit: async (values, { setFieldError, resetForm }) => {
            const value = values.value;
            const setValueFieldError = (message: string) =>
                setFieldError("value", message);

            if (!value) {
                setValueFieldError(t("required"));
                return;
            }

            try {
                await registerPasskey(token, value);
            } catch (e) {
                log.error("Failed to register a new passkey", e);
                // The browser throws an error named "NotAllowedError" when the
                // user cancels the operation, and shows its own error dialog
                // for other failures, so "NotAllowedError" is ignored here.
                if (!isNamedError(e, "NotAllowedError")) {
                    setValueFieldError(t("passkey_add_failed"));
                }
                return;
            }
            await onRefreshPasskeys();
            resetForm();
        },
    });

    return (
        <form onSubmit={formik.handleSubmit}>
            <TextField
                name="value"
                value={formik.values.value}
                onChange={formik.handleChange}
                type="text"
                fullWidth
                margin="normal"
                disabled={formik.isSubmitting}
                error={!!formik.errors.value}
                helperText={formik.errors.value ?? " "}
                label={t("enter_passkey_name")}
            />
            <LoadingButton
                fullWidth
                color="accent"
                type="submit"
                loading={formik.isSubmitting}
            >
                {t("add_passkey")}
            </LoadingButton>
        </form>
    );
};

interface PasskeysListProps {
    passkeys: Passkey[];
    onSelectPasskey: (passkey: Passkey) => void;
}

const PasskeysList: React.FC<PasskeysListProps> = ({
    passkeys,
    onSelectPasskey,
}) => {
    return (
        <RowButtonGroup>
            {passkeys.map((passkey, i) => (
                <React.Fragment key={passkey.id}>
                    <PasskeyListItem
                        passkey={passkey}
                        onClick={onSelectPasskey}
                    />
                    {i < passkeys.length - 1 && <RowButtonDivider />}
                </React.Fragment>
            ))}
        </RowButtonGroup>
    );
};

interface PasskeyListItemProps {
    passkey: Passkey;
    onClick: (passkey: Passkey) => void;
}

const PasskeyListItem: React.FC<PasskeyListItemProps> = ({
    passkey,
    onClick,
}) => (
    <RowButton
        startIcon={<KeyIcon />}
        endIcon={<ChevronRightIcon />}
        label={
            <PasskeyLabel>
                <Typography sx={{ fontWeight: "medium" }}>
                    {passkey.friendlyName}
                </Typography>
            </PasskeyLabel>
        }
        onClick={() => onClick(passkey)}
    />
);

const PasskeyLabel = styled("div")`
    white-space: normal;
`;

interface ManagePasskeyDrawerProps {
    open: boolean;
    onClose: () => void;
    // Both token and passkey are guaranteed to be defined when open is true.
    token: string | undefined;
    passkey: Passkey | undefined;
    onUpdateOrDeletePasskey: () => void;
}

const ManagePasskeyDrawer: React.FC<ManagePasskeyDrawerProps> = ({
    open,
    onClose,
    token,
    passkey,
    onUpdateOrDeletePasskey,
}) => {
    const { showMiniDialog } = useBaseContext();

    const { show: showRenameDialog, props: renameDialogVisibilityProps } =
        useModalVisibility();

    const handleRenamePasskeySubmit = useCallback(
        async (inputValue: string) => {
            await renamePasskey(token!, passkey!.id, inputValue);
            onUpdateOrDeletePasskey();
        },
        [token, passkey, onUpdateOrDeletePasskey],
    );

    const showDeleteConfirmationDialog = useCallback(
        () =>
            showMiniDialog({
                title: t("delete_passkey"),
                message: t("delete_passkey_confirmation"),
                continue: {
                    text: t("delete"),
                    color: "critical",
                    action: async () => {
                        await deletePasskey(token!, passkey!.id);
                        onUpdateOrDeletePasskey();
                    },
                },
            }),
        [showMiniDialog, token, passkey, onUpdateOrDeletePasskey],
    );

    return (
        <>
            <SidebarDrawer anchor="right" {...{ open, onClose }}>
                {token && passkey && (
                    <Stack sx={{ gap: "4px", py: "12px" }}>
                        <SidebarDrawerTitlebar
                            onClose={onClose}
                            title={t("manage_passkey")}
                            onRootClose={onClose}
                        />
                        <CreatedAtEntry>
                            {formattedDateTime(passkey.createdAt)}
                        </CreatedAtEntry>
                        <RowButtonGroup sx={{ m: 1 }}>
                            <RowButton
                                startIcon={<EditIcon />}
                                label={t("rename_passkey")}
                                onClick={showRenameDialog}
                            />
                            <RowButtonDivider />
                            <RowButton
                                color="critical"
                                startIcon={<DeleteIcon />}
                                label={t("delete_passkey")}
                                onClick={showDeleteConfirmationDialog}
                            />
                        </RowButtonGroup>
                    </Stack>
                )}
            </SidebarDrawer>
            {token && passkey && (
                <SingleInputDialog
                    {...renameDialogVisibilityProps}
                    title={t("rename_passkey")}
                    label={t("name")}
                    placeholder={t("enter_passkey_name")}
                    initialValue={passkey.friendlyName}
                    submitButtonTitle={t("rename")}
                    onSubmit={handleRenamePasskeySubmit}
                />
            )}
        </>
    );
};

const CreatedAtEntry: React.FC<React.PropsWithChildren> = ({ children }) => (
    <Stack direction="row" sx={{ alignItems: "center", gap: 0.5, pb: 1 }}>
        <CalendarTodayIcon color="secondary" sx={{ m: "16px" }} />
        <Box sx={{ py: 0.5 }}>
            <Typography>{t("created_at")}</Typography>
            <Typography variant="small" sx={{ color: "text.muted" }}>
                {children}
            </Typography>
        </Box>
    </Stack>
);
