import {
    Key02Icon,
    Mail01Icon,
    PasswordValidationIcon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, { useEffect, useState } from "react";
import { LockerAuthenticateUser } from "../auth/LockerAuthenticateUser";
import { LockerRecoveryKeyDrawer } from "./LockerRecoveryKeyDrawer";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

type AuthenticatedAccountAction =
    | "recoveryKey"
    | "changePassword"
    | "changeEmail";

export const LockerAccountDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const router = useRouter();
    const [isRecoveryKeyOpen, setIsRecoveryKeyOpen] = useState(false);
    const [authenticatedAction, setAuthenticatedAction] =
        useState<AuthenticatedAccountAction>();

    useEffect(() => {
        if (!open) {
            setIsRecoveryKeyOpen(false);
            setAuthenticatedAction(undefined);
        }
    }, [open]);

    const handleRootClose = () => {
        setIsRecoveryKeyOpen(false);
        setAuthenticatedAction(undefined);
        onClose();
        onRootClose();
    };

    const authenticateBefore = (action: AuthenticatedAccountAction) => {
        setAuthenticatedAction(action);
    };

    const handleNavigate = (path: string) => {
        handleRootClose();
        void router.push(path);
    };

    const handleAuthenticatedAction = () => {
        switch (authenticatedAction) {
            case "recoveryKey":
                setIsRecoveryKeyOpen(true);
                break;
            case "changePassword":
                handleNavigate("/change-password");
                break;
            case "changeEmail":
                handleNavigate("/change-email");
                break;
        }
        setAuthenticatedAction(undefined);
    };

    return (
        <>
            <LockerTitledNestedSidebarDrawer
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("account")}
            >
                <LockerSidebarCardButton
                    icon={Mail01Icon}
                    label={t("change_email")}
                    endIcon={<ChevronRightIcon />}
                    onClick={() => authenticateBefore("changeEmail")}
                />
                <LockerSidebarCardButton
                    icon={Key02Icon}
                    label={t("recovery_key")}
                    endIcon={<ChevronRightIcon />}
                    onClick={() => authenticateBefore("recoveryKey")}
                />
                <LockerSidebarCardButton
                    icon={PasswordValidationIcon}
                    label={t("change_password")}
                    endIcon={<ChevronRightIcon />}
                    onClick={() => authenticateBefore("changePassword")}
                />
            </LockerTitledNestedSidebarDrawer>

            <LockerAuthenticateUser
                open={!!authenticatedAction}
                onClose={() => setAuthenticatedAction(undefined)}
                onAuthenticate={handleAuthenticatedAction}
            />

            <LockerRecoveryKeyDrawer
                open={isRecoveryKeyOpen}
                onClose={() => setIsRecoveryKeyOpen(false)}
                onRootClose={handleRootClose}
            />
        </>
    );
};
