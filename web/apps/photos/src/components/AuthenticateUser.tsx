import CloseIcon from "@mui/icons-material/Close";
import {
    ButtonBase,
    Dialog,
    DialogTitle,
    IconButton,
    Input,
    InputBase,
    Stack,
    Typography,
} from "@mui/material";
import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
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
import { ShowHidePasswordInputAdornment } from "ente-base/components/mui/PasswordInputAdornment";
import {
    peopleActionFocusSx,
    v2CancelButtonSx,
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2HelperSx,
    v2InputSx,
    v2LabelSx,
    v2PaperSx,
    v2SubmitButtonSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useId, useState } from "react";

type AuthenticateUserProps = ModalVisibilityProps & {
    onAuthenticate: () => void;
};

export const AuthenticateUser: React.FC<AuthenticateUserProps> = ({
    open,
    onClose,
    ...rest
}) => (
    <Dialog
        open={open}
        onClose={onClose}
        maxWidth={false}
        slotProps={{ paper: { sx: v2PaperSx } }}
    >
        <Stack sx={{ p: "20px", gap: "20px" }}>
            <Stack direction="row" sx={v2HeaderRowSx}>
                <DialogTitle
                    sx={{
                        ...v2TitleSx,
                        fontSize: "20px",
                        lineHeight: "28px",
                        "&&": { p: 0 },
                    }}
                >
                    {t("password")}
                </DialogTitle>
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    sx={v2CloseButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 18 }} />
                </IconButton>
            </Stack>
            <AuthenticateUserDialogContents {...{ open, onClose }} {...rest} />
        </Stack>
    </Dialog>
);

const AuthenticateUserDialogContents: React.FC<AuthenticateUserProps> = ({
    open,
    onClose,
    onAuthenticate,
}) => {
    const { decryptBox } = useAuthPageConfig();
    const { logout, showMiniDialog } = useBaseContext();

    const [user, setUser] = useState<LocalUser | undefined>();
    const [keyAttributes, setKeyAttributes] = useState<
        KeyAttributes | undefined
    >(undefined);

    // Reauthentication must not overwrite local state.
    const validateSession = useCallback(async () => {
        try {
            const session = await checkSessionValidity();
            if (session.status != "valid") {
                onClose();
                showMiniDialog(
                    passwordChangedElsewhereDialogAttributes(logout),
                );
            }
        } catch (e) {
            // A transient validation failure must not log the user out.
            log.warn("Ignoring error when determining session validity", e);
        }
    }, [logout, showMiniDialog, onClose]);

    useEffect(() => {
        setUser(ensureLocalUser());
        setKeyAttributes(ensureSavedKeyAttributes());
    }, []);

    useEffect(() => {
        if (open) void validateSession();
    }, [open, validateSession]);

    const presentation = useCallback(
        (props: VerifyMasterPasswordPresentationProps) => (
            <AuthenticateUserForm {...props} onCancel={onClose} />
        ),
        [onClose],
    );

    if (!user || !keyAttributes) return <></>;

    return (
        <VerifyMasterPasswordForm
            presentation={presentation}
            decryptBox={decryptBox}
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

const AuthenticateUserForm: React.FC<
    VerifyMasterPasswordPresentationProps & { onCancel: () => void }
> = ({
    userEmail,
    password,
    passwordError,
    isSubmitting,
    submitButtonTitle,
    onPasswordChange,
    onSubmit,
    onCancel,
}) => {
    const inputID = useId();
    const helperID = useId();
    const [showPassword, setShowPassword] = useState(false);
    return (
        <Stack component="form" onSubmit={onSubmit} sx={{ gap: "20px" }}>
            <Input
                sx={{ display: "none" }}
                name="email"
                autoComplete="username"
                type="email"
                value={userEmail}
            />
            <Stack sx={{ gap: "8px" }}>
                <Typography component="label" htmlFor={inputID} sx={v2LabelSx}>
                    {t("password")}
                </Typography>
                <InputBase
                    id={inputID}
                    name="password"
                    value={password}
                    onChange={onPasswordChange}
                    type={showPassword ? "text" : "password"}
                    autoComplete="current-password"
                    autoFocus
                    disabled={isSubmitting}
                    error={!!passwordError}
                    sx={v2InputSx}
                    inputProps={{
                        "aria-describedby": passwordError
                            ? helperID
                            : undefined,
                        "aria-invalid": !!passwordError,
                    }}
                    endAdornment={
                        <ShowHidePasswordInputAdornment
                            showPassword={showPassword}
                            onToggle={() => setShowPassword((show) => !show)}
                        />
                    }
                />
                <Typography
                    id={helperID}
                    aria-live="polite"
                    sx={v2HelperSx(!!passwordError)}
                >
                    {passwordError ?? ""}
                </Typography>
            </Stack>
            <Stack direction="row" sx={{ gap: "12px" }}>
                <ButtonBase
                    onClick={onCancel}
                    disabled={isSubmitting}
                    sx={[v2CancelButtonSx, peopleActionFocusSx]}
                >
                    {t("cancel")}
                </ButtonBase>
                <LoadingButton
                    type="submit"
                    loading={isSubmitting}
                    sx={{ ...v2SubmitButtonSx, p: 0 }}
                >
                    {submitButtonTitle}
                </LoadingButton>
            </Stack>
        </Stack>
    );
};
