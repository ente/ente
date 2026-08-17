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
import React, { useCallback, useEffect, useState } from "react";

type LockerAuthenticateUserProps = ModalVisibilityProps & {
    onAuthenticate: () => void;
};

export const LockerAuthenticateUser: React.FC<LockerAuthenticateUserProps> = ({
    open,
    onClose,
    onAuthenticate,
}) => (
    <TitledMiniDialog open={open} onClose={onClose} title={t("password")}>
        <LockerAuthenticateUserDialogContents
            {...{ open, onClose, onAuthenticate }}
        />
    </TitledMiniDialog>
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
