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

export interface MiniDialogAttributes {
    title?: React.ReactNode;
    icon?: React.ReactNode;
    message?: React.ReactNode;
    nonClosable?: boolean;
    nonReplaceable?: boolean;
    continue?: {
        text?: string;
        color?: ButtonProps["color"];
        autoFocus?: ButtonProps["autoFocus"];
        action?: () => void | Promise<void>;
    };
    secondary?: {
        text: string;
        color?: ButtonProps["color"];
        action?: () => void | Promise<void>;
    };
    cancel?: string | false | { text: string; action: () => void };
    buttonDirection?: "row" | "column";
}

type MiniDialogProps = Pick<DialogProps, "open" | "sx"> & {
    onClose: () => void;
    attributes?: MiniDialogAttributes;
};

export const AttributedMiniDialog: React.FC<
    React.PropsWithChildren<MiniDialogProps>
> = ({ open, onClose, attributes, children, sx }) => {
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
            {...{ open, sx }}
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
                            sx={{ "&&&": { padding: 0 }, flexShrink: 1 }}
                        >
                            {attributes.title}
                        </DialogTitle>
                    )}
                    {attributes.icon}
                </Stack>
            ) : (
                <Box sx={{ height: "8px" }} />
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
    title?: React.ReactNode;
    paperMaxWidth?: string;
};

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
