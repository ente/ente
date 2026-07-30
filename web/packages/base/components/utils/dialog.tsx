import ErrorOutlinedIcon from "@mui/icons-material/ErrorOutlined";
import { t } from "i18next";
import { useCallback, useState } from "react";
import type { MiniDialogAttributes } from "../MiniDialog";

/**
 * A React hook for simplifying the provisioning of a {@link showMiniDialog}
 * function to inject in app contexts, and of the other props that are needed to
 * be passed to the {@link AttributedMiniDialog}.
 */
export const useAttributedMiniDialog = () => {
    const [attributes, setAttributes] = useState<
        MiniDialogAttributes | undefined
    >(undefined);

    const [open, setOpen] = useState(false);

    const showMiniDialog = useCallback(
        (newAttributes: MiniDialogAttributes) => {
            setAttributes((attributes) =>
                attributes?.nonReplaceable ? attributes : newAttributes,
            );
            setOpen(true);
        },
        [],
    );

    const handleClose = useCallback(() => setOpen(false), []);

    return {
        showMiniDialog,
        miniDialogProps: { open, onClose: handleClose, attributes },
    };
};

/**
 * A convenience function to construct {@link MiniDialogAttributes} for showing
 * error dialogs.
 *
 * It takes one or two arguments.
 *
 * - If both are provided, then the first one is taken as the title and the
 *   second one as the message.
 *
 * - Otherwise it sets a default title and use the only argument as the message.
 */
export const errorDialogAttributes = (
    messageOrTitle: string,
    optionalMessage?: string,
): MiniDialogAttributes => {
    const title = optionalMessage ? messageOrTitle : t("error");
    const message = optionalMessage ?? messageOrTitle;

    return {
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
