import React, { useState } from "react";
import { disablePasskeys } from "../services/admin-user";
import { useStaffSession } from "../services/session";
import { ConfirmationDialog } from "./ConfirmationDialog";

interface DisablePasskeysProps {
    open: boolean;
    handleClose: () => void;
    handleDisablePasskeys: () => void;
}

export const DisablePasskeys: React.FC<DisablePasskeysProps> = ({
    open,
    handleClose,
    handleDisablePasskeys,
}) => {
    const [loading, setLoading] = useState(false);
    const session = useStaffSession();

    const handleDisabling = async () => {
        try {
            setLoading(true);
            await disablePasskeys(session);
            handleDisablePasskeys();
            handleClose();
        } catch (error) {
            if (error instanceof Error) {
                alert(error.message);
            } else {
                alert("Failed to disable passkeys");
            }
        } finally {
            setLoading(false);
        }
    };

    return (
        <ConfirmationDialog
            open={open}
            onClose={handleClose}
            title="Disable Passkeys?"
            actions={[
                {
                    label: "Disable",
                    loadingLabel: "Disabling...",
                    loading,
                    onClick: () => {
                        handleDisabling().catch((error: unknown) =>
                            console.error(error),
                        );
                    },
                },
            ]}
        >
            Are you sure you want to disable passkeys for this account?
        </ConfirmationDialog>
    );
};
