import type { ButtonProps, ModalProps } from "@mui/material";
import {
    Box,
    Dialog,
    DialogContent,
    DialogTitle,
    Stack,
    Typography,
    type DialogProps,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { useState } from "react";
import log from "../log";
import { InlineErrorIndicator } from "./ErrorIndicator";

/**
 * Customize the contents of an {@link AttributedMiniDialog}.
 */
export interface MiniDialogAttributes {
    /**
     * The dialog's title.
     *
     * This will be usually be a string, but the prop accepts any React node to
     * allow passing a i18next <Trans /> component.
     */
    title?: React.ReactNode;
    /**
     * An optional component shown next to the title.
     */
    icon?: React.ReactNode;
    /**
     * The dialog's message.
     *
     * This will be usually be a string, but the prop accepts any React node to
     * allow passing a i18next <Trans /> component.
     */
    message?: React.ReactNode;
    /**
     * If `true`, then the dialog cannot be closed (e.g. with the ESC key, or
     * clicking on the backdrop) except through one of the explicitly provided
     * actions.
     */
    nonClosable?: boolean;
    /**
     * If `true`, then the dialog cannot be replaced by another dialog while it
     * is being displayed.
     *
     * The app uses a single component to render mini dialogs, and it is
     * possible that new dialog contents might preempt and replace contents in a
     * dialog that is already being shown. Usually if such preemption is
     * expected then both dialogs use differing mechanisms, but it can happen in
     * rare unforeseen cases.
     *
     * This flag allow a dialog to indicate that it should not be preempted, as
     * it contains some critical information.
     *
     * Use this flag sparingly.
     */
    nonReplaceable?: boolean;
    /**
     * Customize the primary action button shown in the dialog.
     *
     * This is provided by boxes which serve as some sort of confirmation. If
     * not provided, only the {@link cancel} button is shown, unless that too is
     * explicitly disabled.
     */
    continue?: {
        /**
         * The string to use as the label for the primary action button.
         *
         * Default is `t("ok")`.
         */
        text?: string;
        /**
         * The color of the button.
         *
         * Default is "accent".
         */
        color?: ButtonProps["color"];
        /**
         * If `true`, the primary action button is auto focused when the dialog
         * is opened, allowing the user to confirm just by pressing ENTER.
         */
        autoFocus?: ButtonProps["autoFocus"];
        /**
         * The function to call when the user activates the button.
         *
         * If this function returns a promise, then an activity indicator will
         * be shown on the button until the promise settles.
         *
         * If this function is not provided, or if the function completes /
         * fulfills, then then the dialog is automatically closed.
         *
         * Otherwise (that is, if the provided function throws), the dialog
         * remains open, showing a generic error.
         *
         * That's quite a mouthful, here's a flowchart:
         *
         * - Not provided: Close
         * - Provided sync:
         *   - Success: Close
         *   - Failure: Remain open, showing generic error
         * - Provided async:
         *   - Success: Close
         *   - Failure: Remain open, showing generic error
         */
        action?: () => void | Promise<void>;
    };
    /**
     * Customize the secondary action button shown in the dialog.
     *
     * This is rarely needed. When provided, these attributes behave similar to
     * the {@link continue} attributes, except this button is shown below the
     * primary button.
     *
     * This is not supported when button direction is "row".
     */
    secondary?: {
        /**
         * The string to use as the label for the secondary action button.
         *
         * Must be provided.
         */
        text: string;
        /**
         * The color of the button.
         *
         * Default is "primary".
         */
        color?: ButtonProps["color"];
        /**
         * The function to call when the user activates the button.
         *
         * The behaviour of this function is exactly the same as that of the
         * primary {@link action} provided via the {@link continue} attributes.
         */
        action?: () => void | Promise<void>;
    };
    /**
     * The string to use as the label for the cancel button.
     *
     * Default is `t("cancel")`.
     *
     * Set this to `false` to omit the cancel button altogether.
     *
     * The object form allows providing both the button title and the action
     * handler (synchronous). The dialog is always closed on clicks.
     */
    cancel?: string | false | { text: string; action: () => void };
    /** The direction in which the buttons are stacked. Default is "column". */
    buttonDirection?: "row" | "column";
}

type MiniDialogProps = Pick<DialogProps, "open"> & {
    onClose: () => void;
    attributes?: MiniDialogAttributes;
};

/**
 * A small, mostly predefined, MUI {@link Dialog} that can be used to notify the
 * user, or ask for confirmation before actions.
 *
 * The rendered dialog can be customized by modifying the {@link attributes}
 * prop. If you find yourself wanting to customize it further, consider either
 * using a {@link TitledMiniDialog} or {@link Dialog}.
 */
export const AttributedMiniDialog: React.FC<
    React.PropsWithChildren<MiniDialogProps>
> = ({ open, onClose, attributes, children }) => {
    const [phase, setPhase] = useState<
        "loading" | "secondary-loading" | "failed" | undefined
    >();

    if (!attributes) {
        return <></>;
    }

    const resetPhaseAndClose = () => {
        setPhase(undefined);
        onClose();
    };

    const handleClose: ModalProps["onClose"] = () => {
        if (attributes.nonClosable) return;
        // Ignore modal close requests while processing the user request.
        if (phase == "loading" || phase == "secondary-loading") return;
        resetPhaseAndClose();
    };

    const [cancelTitle, handleCancel] = ((
        c: MiniDialogAttributes["cancel"],
    ) => {
        if (c === false) return [undefined, undefined];
        if (c === undefined) return [t("cancel"), resetPhaseAndClose];
        if (typeof c == "string") return [c, resetPhaseAndClose];
        return [
            c.text,
            () => {
                resetPhaseAndClose();
                c.action();
            },
        ];
    })(attributes.cancel);

    const loadingButton = attributes.continue && (
        <LoadingButton
            loading={phase == "loading"}
            disabled={phase == "secondary-loading"}
            fullWidth
            color={attributes.continue.color ?? "accent"}
            autoFocus={attributes.continue.autoFocus}
            onClick={async () => {
                setPhase("loading");
                try {
                    await attributes.continue?.action?.();
                    resetPhaseAndClose();
                } catch (e) {
                    log.error(e);
                    setPhase("failed");
                }
            }}
        >
            {attributes.continue.text ?? t("ok")}
        </LoadingButton>
    );

    const secondaryLoadingButton = attributes.secondary?.text && (
        <LoadingButton
            disabled={phase == "loading"}
            loading={phase == "secondary-loading"}
            fullWidth
            color={attributes.secondary.color ?? "primary"}
            onClick={async () => {
                setPhase("secondary-loading");
                try {
                    await attributes.secondary?.action?.();
                    resetPhaseAndClose();
                } catch (e) {
                    log.error(e);
                    setPhase("failed");
                }
            }}
        >
            {attributes.secondary.text}
        </LoadingButton>
    );

    if (secondaryLoadingButton && attributes.buttonDirection == "row")
        throw new Error("Unsupported combination");

    const cancelButton = cancelTitle && (
        <FocusVisibleButton
            fullWidth
            color="secondary"
            disabled={phase == "loading" || phase == "secondary-loading"}
            onClick={handleCancel}
        >
            {cancelTitle}
        </FocusVisibleButton>
    );

    return (
        <Dialog
            {...{ open }}
            onClose={handleClose}
            fullWidth
            slotProps={{ paper: { sx: { maxWidth: "360px" } } }}
        >
            {(attributes.icon ?? attributes.title) ? (
                <Stack
                    direction="row"
                    sx={[
                        {
                            justifyContent: "space-between",
                            alignItems: "center",
                            "& > svg": {
                                fontSize: "32px",
                                color: "stroke.faint",
                            },
                        },
                        attributes.icon && attributes.title
                            ? { padding: "20px 16px 0px 16px" }
                            : { padding: "24px 16px 4px 16px" },
                    ]}
                >
                    {attributes.title && (
                        <DialogTitle
                            sx={{
                                "&&&": { padding: 0 },
                                // Wrap the title to the next line if there
                                // isn't sufficient space to make it fit in one.
                                flexShrink: 1,
                            }}
                        >
                            {attributes.title}
                        </DialogTitle>
                    )}
                    {attributes.icon}
                </Stack>
            ) : (
                <Box sx={{ height: "8px" }} /> /* Spacer */
            )}
            <DialogContent>
                {attributes.message && (
                    <Typography
                        component={
                            typeof attributes.message == "string" ? "p" : "div"
                        }
                        sx={{ color: "text.muted" }}
                    >
                        {attributes.message}
                    </Typography>
                )}
                {children}
                <Stack
                    sx={{ pt: 3, gap: 1 }}
                    direction={attributes.buttonDirection ?? "column"}
                >
                    {phase == "failed" && <InlineErrorIndicator />}
                    {attributes.buttonDirection == "row" ? (
                        <>
                            {cancelButton}
                            {loadingButton}
                        </>
                    ) : (
                        <>
                            {loadingButton}
                            {secondaryLoadingButton}
                            {cancelButton}
                        </>
                    )}
                </Stack>
            </DialogContent>
        </Dialog>
    );
};

type TitledMiniDialogProps = Pick<DialogProps, "open" | "onClose" | "sx"> & {
    /**
     * The dialog's title.
     */
    title?: React.ReactNode;
    /**
     * Optional max width of the underlying MUI {@link Paper}.
     *
     * Default: 360px (same as {@link AttributedMiniDialog}).
     */
    paperMaxWidth?: string;
};

/**
 * MiniDialog in a "shell" form.
 *
 * This is a {@link Dialog} for use at places which need more customization than
 * what {@link AttributedMiniDialog} provides, but wish to retain a similar look
 * and feel without duplicating code.
 *
 * It does three things:
 *
 * - Sets a fixed size and padding similar to {@link AttributedMiniDialog}.
 * - Takes the title as a prop, and wraps it in a {@link DialogTitle}.
 * - Wraps children in a scrollable {@link DialogContent}.
 */
export const TitledMiniDialog: React.FC<
    React.PropsWithChildren<TitledMiniDialogProps>
> = ({ open, onClose, sx, paperMaxWidth, title, children }) => (
    <Dialog
        {...{ open, sx }}
        onClose={onClose}
        fullWidth
        slotProps={{ paper: { sx: { maxWidth: paperMaxWidth ?? "360px" } } }}
    >
        <DialogTitle sx={{ "&&&": { paddingBlock: "24px 16px" } }}>
            {title}
        </DialogTitle>
        <DialogContent>{children}</DialogContent>
    </Dialog>
);
