import { authenticatedLegacySession } from "@/services/authenticated-session";
import { UserAdd01Icon } from "@hugeicons/core-free-icons";
import { CircularProgress } from "@mui/material";
import {
    LegacyDrawerContent,
    type LegacySuggestedUser,
} from "ente-contacts/legacy";
import { t } from "i18next";
import React from "react";
import { LockerSidebarCardButton } from "./LockerSidebarCardButton";
import {
    LockerTitledNestedSidebarDrawer,
    type LockerNestedSidebarDrawerVisibilityProps,
} from "./LockerSidebarShell";

export const LockerLegacyDrawer: React.FC<
    LockerNestedSidebarDrawerVisibilityProps & {
        suggestedUsers: LegacySuggestedUser[];
    }
> = ({ open, onClose, onRootClose, suggestedUsers }) => (
    <LockerTitledNestedSidebarDrawer
        {...{ open, onClose, onRootClose }}
        title={t("legacy")}
    >
        <LegacyDrawerContent
            intro={t("legacy_intro")}
            open={open}
            suggestedUsers={suggestedUsers}
            getSession={authenticatedLegacySession}
            renderAddContactButton={({ onClick, disabled, loading }) => (
                <LockerSidebarCardButton
                    icon={UserAdd01Icon}
                    iconNode={
                        loading ? (
                            <CircularProgress size={18} color="inherit" />
                        ) : undefined
                    }
                    label={t("add_trusted_contact")}
                    onClick={onClick}
                    disabled={disabled}
                />
            )}
        />
    </LockerTitledNestedSidebarDrawer>
);
