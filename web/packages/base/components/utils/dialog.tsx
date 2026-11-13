import ErrorOutlinedIcon from "@mui/icons-material/ErrorOutlined";
import { t } from "i18next";
import { useCallback, useReducer } from "react";
import type { MiniDialogAttributes } from "../MiniDialog";
import { miniDialogReducer } from "./mini-dialog-state";

export const useAttributedMiniDialog = () => {
    const [dialog, dispatch] = useReducer(miniDialogReducer, {
        open: false,
        id: 0,
    });

    const showMiniDialog = useCallback(
        (newAttributes: MiniDialogAttributes) => {
            dispatch({ type: "show", attributes: newAttributes });
        },
        [],
    );

    const handleClose = useCallback(() => {
        dispatch({ type: "close", id: dialog.id });
    }, [dialog.id]);

    const dismissRouteScopedMiniDialog = useCallback(() => {
        dispatch({ type: "routeChange" });
    }, []);

    return {
        showMiniDialog,
        dismissRouteScopedMiniDialog,
        miniDialogProps: {
            dialogID: dialog.id,
            open: dialog.open,
            onClose: handleClose,
            attributes: dialog.attributes,
        },
    };
};

export const errorDialogAttributes = (
    messageOrTitle: string,
    optionalMessage?: string,
): MiniDialogAttributes => {
    const title = optionalMessage ? messageOrTitle : t("error");
    const message = optionalMessage ?? messageOrTitle;

    return {
        kind: "error",
        title,
        icon: <ErrorOutlinedIcon />,
        message,
        continue: { color: "critical" },
        cancel: false,
    };
};

export const genericErrorDialogAttributes = () =>
    errorDialogAttributes(t("generic_error"));

export const genericRetriableErrorDialogAttributes = () =>
    errorDialogAttributes(t("generic_error_retry"));
