import React, { useState } from "react";
import { closeFamily } from "../services/admin-user";
import { useStaffSession } from "../services/session";
import { ConfirmationDialog } from "./ConfirmationDialog";

interface CloseFamilyProps {
    open: boolean;
    handleClose: () => void;
    handleCloseFamily: () => void;
}

export const CloseFamily: React.FC<CloseFamilyProps> = ({
    open,
    handleClose,
    handleCloseFamily,
}) => {
    const [loading, setLoading] = useState(false);
    const session = useStaffSession();

    const handleClosure = async () => {
        try {
            setLoading(true);
            await closeFamily(session);
            handleCloseFamily();
            handleClose();
        } catch (error) {
            if (error instanceof Error) {
                alert(error.message);
            } else {
                alert("Failed to close family");
            }
        } finally {
            setLoading(false);
        }
    };

    return (
        <ConfirmationDialog
            open={open}
            onClose={handleClose}
            title="Close Family?"
            actions={[
                {
                    label: "Close",
                    loadingLabel: "Closing...",
                    loading,
                    onClick: () => {
                        handleClosure().catch((error: unknown) =>
                            console.error(error),
                        );
                    },
                },
            ]}
        >
            Are you sure you want to close family relations for this account?
        </ConfirmationDialog>
    );
};
