import type { MiniDialogAttributes } from "ente-base/components/MiniDialog";
import { createContext, useContext } from "react";
import { genericErrorDialogAttributes } from "./components/utils/dialog";
import log from "./log";

export interface BaseContextT {
    logout: () => void;
    showMiniDialog: (attributes: MiniDialogAttributes) => void;
    onGenericError: (error: unknown) => void;
}

export const BaseContext = createContext<BaseContextT | undefined>(undefined);

export const useBaseContext = (): BaseContextT => useContext(BaseContext)!;

export const deriveBaseContext = ({
    logout,
    showMiniDialog,
}: Omit<BaseContextT, "onGenericError">): BaseContextT => {
    const onGenericError = (e: unknown) => {
        log.error(e);
        // Let a dialog action close its dialog before showing the error dialog.
        setTimeout(() => {
            showMiniDialog(genericErrorDialogAttributes());
        }, 0);
    };

    return { logout, showMiniDialog, onGenericError };
};
