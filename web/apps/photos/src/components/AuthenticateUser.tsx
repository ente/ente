import { useAuthPageConfig } from "ente-accounts/components/auth/AuthPageProvider";
import { checkSessionValidity } from "ente-accounts/services/session";
import {
    ensureLocalUser,
    ensureSavedKeyAttributes,
    type KeyAttributes,
    type LocalUser,
} from "ente-accounts/services/user";
import { verifyMasterPassword } from "ente-accounts/services/verify-master-password";
import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
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

    return (
        <SingleInputDialog
            open={open}
            onClose={onClose}
            title={t("password")}
            label={t("password")}
            inputType="password"
            autoComplete="current-password"
            username={user?.email}
            disabled={!user || !keyAttributes}
            submitButtonTitle={t("authenticate")}
            onSubmit={async (password, setFieldError) => {
                try {
                    await verifyMasterPassword(
                        { decryptBox, keyAttributes, onVerify: onAuthenticate },
                        password,
                        setFieldError,
                    );
                } catch (error) {
                    log.error("Failed to verify password", error);
                    setFieldError(t("generic_error"));
                }
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
