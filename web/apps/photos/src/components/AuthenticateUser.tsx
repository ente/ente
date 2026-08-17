import { VerifyMasterPasswordForm } from "ente-accounts/components/VerifyMasterPasswordForm";
import { checkSessionValidity } from "ente-accounts/services/session";
import {
    ensureLocalUser,
    ensureSavedKeyAttributes,
    type KeyAttributes,
    type LocalUser,
} from "ente-accounts/services/user";
import {
    TitledMiniDialog,
    type MiniDialogAttributes,
} from "ente-base/components/MiniDialog";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { t } from "i18next";
import { useCallback, useEffect, useState } from "react";

type AuthenticateUserProps = ModalVisibilityProps & {
    onAuthenticate: () => void;
};

export const AuthenticateUser: React.FC<AuthenticateUserProps> = ({
    open,
    onClose,
    ...rest
}) => (
    <TitledMiniDialog
        open={open}
        onClose={onClose}
        sx={{ position: "absolute" }}
        title={t("password")}
    >
        <AuthenticateUserDialogContents {...{ open, onClose }} {...rest} />
    </TitledMiniDialog>
);

const AuthenticateUserDialogContents: React.FC<AuthenticateUserProps> = ({
    open,
    onClose,
    onAuthenticate,
}) => {
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

    if (!user || !keyAttributes) return <></>;

    return (
        <VerifyMasterPasswordForm
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
