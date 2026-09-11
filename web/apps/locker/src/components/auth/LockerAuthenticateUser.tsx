import CloseIcon from "@mui/icons-material/Close";
import VisibilityIcon from "@mui/icons-material/Visibility";
import VisibilityOffIcon from "@mui/icons-material/VisibilityOff";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    InputAdornment,
    Stack,
} from "@mui/material";
import {
    VerifyMasterPasswordForm,
    type VerifyMasterPasswordPresentationProps,
} from "ente-accounts/components/VerifyMasterPasswordForm";
import { checkSessionValidity } from "ente-accounts/services/session";
import {
    ensureLocalUser,
    ensureSavedKeyAttributes,
    type KeyAttributes,
    type LocalUser,
} from "ente-accounts/services/user";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";

import { FormField } from "@/components/ui/FormField";
import {
    lockerSheetContainerSx,
    lockerSheetPaperSx,
} from "../../styles/dialog";
import {
    lockerColorSx,
    lockerTextBodyBoldSx,
    lockerTextH2Sx,
} from "../../styles/tokens";

type LockerAuthenticateUserProps = ModalVisibilityProps & {
    onAuthenticate: () => void;
};

export const LockerAuthenticateUser: React.FC<LockerAuthenticateUserProps> = ({
    open,
    onClose,
    onAuthenticate,
}) => (
    <Dialog
        open={open}
        onClose={onClose}
        fullWidth
        maxWidth="xs"
        aria-labelledby="locker-authenticate-title"
        slotProps={{
            paper: { sx: lockerSheetPaperSx },
            container: { sx: lockerSheetContainerSx },
        }}
    >
        <DialogTitle
            id="locker-authenticate-title"
            sx={{
                ...lockerTextH2Sx,
                "&&&": { p: 0 },
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                mb: 2.5,
            }}
        >
            {t("password")}
            <IconButton
                aria-label={t("close")}
                onClick={onClose}
                sx={(theme) => ({
                    width: 36,
                    height: 36,
                    p: 0,
                    borderRadius: "50%",
                    ...lockerColorSx(theme, {
                        backgroundColor: "fillLight",
                        color: "iconColor",
                    }),
                    "&:hover": lockerColorSx(theme, {
                        backgroundColor: "fillHover",
                    }),
                })}
            >
                <CloseIcon sx={{ fontSize: 18 }} />
            </IconButton>
        </DialogTitle>
        <DialogContent sx={{ "&&&": { p: 0 } }}>
            <LockerAuthenticateUserDialogContents
                {...{ open, onClose, onAuthenticate }}
            />
        </DialogContent>
    </Dialog>
);

const LockerAuthenticateUserDialogContents: React.FC<
    LockerAuthenticateUserProps
> = ({ open, onClose, onAuthenticate }) => {
    const { logout, showMiniDialog } = useBaseContext();

    const [user, setUser] = useState<LocalUser | undefined>();
    const [keyAttributes, setKeyAttributes] = useState<
        KeyAttributes | undefined
    >();

    const validateSession = useCallback(async () => {
        try {
            const session = await checkSessionValidity();
            if (session.status !== "valid") {
                onClose();
                showMiniDialog(
                    passwordChangedElsewhereDialogAttributes(logout),
                );
            }
        } catch (error) {
            log.warn("Ignoring error when determining session validity", error);
        }
    }, [logout, onClose, showMiniDialog]);

    useEffect(() => {
        if (!open) {
            return;
        }

        setUser(ensureLocalUser());
        setKeyAttributes(ensureSavedKeyAttributes());
        void validateSession();
    }, [open, validateSession]);

    if (!user || !keyAttributes) {
        return <></>;
    }

    return (
        <VerifyMasterPasswordForm
            presentation={LockerPasswordForm}
            userEmail={user.email}
            keyAttributes={keyAttributes}
            submitButtonTitle={t("authenticate")}
            onVerify={() => {
                onAuthenticate();
                onClose();
            }}
        />
    );
};

const passwordChangedElsewhereDialogAttributes = (
    onLogin: () => void,
): MiniDialogAttributes => ({
    title: t("password_changed_elsewhere"),
    message: t("password_changed_elsewhere_message"),
    continue: { text: t("login"), action: onLogin },
    cancel: false,
});

const LockerPasswordForm: React.FC<VerifyMasterPasswordPresentationProps> = ({
    userEmail,
    password,
    passwordError,
    isSubmitting,
    submitButtonTitle,
    onPasswordChange,
    onSubmit,
}) => {
    const [showPassword, setShowPassword] = useState(false);
    return (
        <Stack component="form" onSubmit={onSubmit} sx={{ gap: 3 }}>
            <input
                name="email"
                type="email"
                autoComplete="username"
                value={userEmail}
                readOnly
                hidden
            />
            <FormField
                name="password"
                label={t("password")}
                type={showPassword ? "text" : "password"}
                autoComplete="current-password"
                autoFocus
                value={password}
                onChange={onPasswordChange}
                disabled={isSubmitting}
                error={!!passwordError}
                helperText={passwordError}
                slotProps={{
                    input: {
                        endAdornment: (
                            <InputAdornment position="end">
                                <IconButton
                                    aria-label={t("show_or_hide_password")}
                                    aria-pressed={showPassword}
                                    onClick={() =>
                                        setShowPassword((show) => !show)
                                    }
                                    onMouseDown={(event) =>
                                        event.preventDefault()
                                    }
                                    edge="end"
                                    sx={(theme) => ({
                                        color: "inherit",
                                        "&&": {
                                            backgroundColor: "transparent",
                                        },
                                        "&&:hover": lockerColorSx(theme, {
                                            backgroundColor: "fillHover",
                                        }),
                                    })}
                                >
                                    {showPassword ? (
                                        <VisibilityOffIcon
                                            sx={{ fontSize: 20 }}
                                        />
                                    ) : (
                                        <VisibilityIcon sx={{ fontSize: 20 }} />
                                    )}
                                </IconButton>
                            </InputAdornment>
                        ),
                    },
                }}
            />
            <LoadingButton
                fullWidth
                type="submit"
                color="primary"
                loading={isSubmitting}
                sx={(theme) => ({
                    ...lockerTextBodyBoldSx,
                    minHeight: 52,
                    borderRadius: "20px",
                    textTransform: "none",
                    ...lockerColorSx(theme, {
                        backgroundColor: "primary",
                        color: "specialWhite",
                    }),
                    "&:hover": lockerColorSx(theme, {
                        backgroundColor: "primaryDark",
                    }),
                })}
            >
                {submitButtonTitle}
            </LoadingButton>
        </Stack>
    );
};
