import { generatePasskeyRecovery } from "@/services/authenticated-session";
import {
    ComputerPhoneSyncIcon,
    Key01Icon,
    SecurityCheckIcon,
} from "@hugeicons/core-free-icons";
import ChevronRightIcon from "@mui/icons-material/ChevronRight";
import { openAccountsManagePasskeysPage } from "ente-accounts/services/passkey";
import { useBaseContext } from "ente-base/context";
import { t } from "i18next";
import React, { useEffect, useState } from "react";
import { LockerAuthenticateUser } from "../auth/LockerAuthenticateUser";
import { LockerSessionsDrawer } from "./LockerSessionsDrawer";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";
import { LockerTwoFactorDrawer } from "./LockerTwoFactorDrawer";

export const LockerSecurityDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps
> = ({ open, onClose, onRootClose }) => {
    const { onGenericError } = useBaseContext();
    const [isSessionsOpen, setIsSessionsOpen] = useState(false);
    const [isTwoFactorOpen, setIsTwoFactorOpen] = useState(false);
    const [authenticatedAction, setAuthenticatedAction] =
        useState<"activeSessions">();

    useEffect(() => {
        if (!open) {
            setIsSessionsOpen(false);
            setIsTwoFactorOpen(false);
            setAuthenticatedAction(undefined);
        }
    }, [open]);

    const handleRootClose = () => {
        setIsSessionsOpen(false);
        setIsTwoFactorOpen(false);
        setAuthenticatedAction(undefined);
        onClose();
        onRootClose();
    };

    const handleAuthenticatedAction = () => {
        if (authenticatedAction === "activeSessions") {
            setIsSessionsOpen(true);
        }
        setAuthenticatedAction(undefined);
    };

    const handleOpenPasskeys = async () => {
        handleRootClose();
        try {
            await openAccountsManagePasskeysPage(generatePasskeyRecovery);
        } catch (e) {
            onGenericError(e);
        }
    };

    return (
        <>
            <LockerTitledNestedSidebarDrawer
                {...{ open, onClose }}
                onRootClose={handleRootClose}
                title={t("security")}
            >
                <LockerSidebarCardButton
                    icon={SecurityCheckIcon}
                    label={t("two_factor")}
                    endIcon={<ChevronRightIcon />}
                    onClick={() => setIsTwoFactorOpen(true)}
                />
                <LockerSidebarCardButton
                    icon={Key01Icon}
                    label={t("passkeys")}
                    endIcon={<ChevronRightIcon />}
                    onClick={handleOpenPasskeys}
                />
                <LockerSidebarCardButton
                    icon={ComputerPhoneSyncIcon}
                    label={t("active_sessions")}
                    endIcon={<ChevronRightIcon />}
                    onClick={() => setAuthenticatedAction("activeSessions")}
                />
            </LockerTitledNestedSidebarDrawer>
            <LockerSessionsDrawer
                open={isSessionsOpen}
                onClose={() => setIsSessionsOpen(false)}
                onRootClose={handleRootClose}
            />
            <LockerTwoFactorDrawer
                open={isTwoFactorOpen}
                onClose={() => setIsTwoFactorOpen(false)}
                onRootClose={handleRootClose}
            />
            <LockerAuthenticateUser
                open={!!authenticatedAction}
                onClose={() => setAuthenticatedAction(undefined)}
                onAuthenticate={handleAuthenticatedAction}
            />
        </>
    );
};
