import React, { useState } from "react";
import { updateEmailMFA } from "../services/admin-user";
import { useStaffSession } from "../services/session";
import { ConfirmationDialog } from "./ConfirmationDialog";

interface ToggleEmailMFAProps {
    open: boolean;
    handleClose: () => void;
    handleToggleEmailMFA: (status: boolean) => void;
}

export const ToggleEmailMFA: React.FC<ToggleEmailMFAProps> = ({
    open,
    handleClose,
    handleToggleEmailMFA,
}) => {
    const [loading, setLoading] = useState(false);
    const session = useStaffSession();

    const handleToggle = async (enable: boolean) => {
        try {
            setLoading(true);
            await updateEmailMFA(session, enable);
            handleToggleEmailMFA(enable);
            handleClose();
        } catch (error) {
            if (error instanceof Error) {
                alert(error.message);
            } else {
                alert("Failed to update Email MFA");
            }
        } finally {
            setLoading(false);
        }
    };

    return (
        <ConfirmationDialog
            open={open}
            onClose={handleClose}
            title="Toggle Email MFA"
            actions={[
                {
                    label: "Enable Email MFA",
                    loadingLabel: "Processing...",
                    loading,
                    tone: "success",
                    onClick: () => {
                        handleToggle(true).catch((error: unknown) =>
                            console.error(error),
                        );
                    },
                },
                {
                    label: "Disable Email MFA",
                    loadingLabel: "Processing...",
                    loading,
                    onClick: () => {
                        handleToggle(false).catch((error: unknown) =>
                            console.error(error),
                        );
                    },
                },
            ]}
        >
            Do you want to enable or disable Email MFA for this account?
        </ConfirmationDialog>
    );
};
