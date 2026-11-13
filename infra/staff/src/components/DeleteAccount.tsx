import React from "react";
import { deleteAccount } from "../services/admin-user";
import { useStaffSession } from "../services/session";
import { ConfirmationDialog } from "./ConfirmationDialog";

interface DeleteAccountProps {
    open: boolean;
    handleClose: () => void;
}

export const DeleteAccount: React.FC<DeleteAccountProps> = ({
    open,
    handleClose,
}) => {
    const session = useStaffSession();

    const handleDelete = async () => {
        try {
            await deleteAccount(session);
            handleClose();
        } catch (error) {
            if (error instanceof Error) {
                alert("Failed to delete the account: " + error.message);
            } else {
                alert("An error occurred while deleting the account");
            }
        }
    };

    return (
        <ConfirmationDialog
            open={open}
            onClose={handleClose}
            title="Delete Account?"
            actions={[
                {
                    label: "Delete",
                    onClick: () => {
                        handleDelete().catch((error: unknown) =>
                            console.error("Fetch data error:", error),
                        );
                    },
                },
            ]}
        >
            Are you sure you want to delete the account?
        </ConfirmationDialog>
    );
};
