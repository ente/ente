import CloseIcon from "@mui/icons-material/Close";
import type { ButtonProps } from "@mui/material";
import {
    Box,
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    Stack,
    Typography,
    type DialogProps,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { useId, useState } from "react";
import log from "../log";
import { InlineErrorIndicator } from "./ErrorIndicator";

export interface MiniDialogAttributes {
    kind?: "info" | "warning" | "error";
    title?: React.ReactNode;
    icon?: React.ReactNode;
    illustration?: React.ReactNode;
    message?: React.ReactNode;
    nonClosable?: boolean;
    nonReplaceable?: boolean;
    dismissOnRouteChange?: boolean;
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
    appearance?: "default" | "centered";
    // A new request remounts the content to reset pending/error state.
    dialogID?: number;
    onClose: () => void;
    attributes?: MiniDialogAttributes;
};

export const AttributedMiniDialog: React.FC<
    React.PropsWithChildren<MiniDialogProps>
> = ({ dialogID, ...props }) => <MiniDialogContent key={dialogID} {...props} />;

const MiniDialogContent: React.FC<React.PropsWithChildren<MiniDialogProps>> = ({
    open,
    onClose,
    attributes,
    children,
    sx,
    appearance = "default",
}) => {
    const titleID = useId();
    const messageID = useId();
    const [phase, setPhase] = useState<
        "loading" | "secondary-loading" | "failed" | undefined
    >();

    if (!attributes) {
        return <></>;
    }

    const centered = appearance === "centered";
    const busy = phase === "loading" || phase === "secondary-loading";
    const artwork =
        attributes.illustration ??
        (centered && attributes.kind ? (
            <Box
                component="img"
                src={`/images/warning-${attributes.kind === "warning" ? "red" : "grey"}.png`}
                alt=""
                sx={{
                    width: 68,
                    height: 64,
                    objectFit: "contain",
                    display: "block",
                }}
            />
        ) : undefined) ??
        attributes.icon;

    const resetPhaseAndClose = () => {
        setPhase(undefined);
        onClose();
    };

    const handleClose = () => {
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
            aria-labelledby={attributes.title ? titleID : undefined}
            aria-describedby={attributes.message ? messageID : undefined}
            aria-busy={busy}
            slotProps={{
                paper: {
                    sx: centered
                        ? {
                              maxWidth: "440px",
                              borderRadius: "24px",
                              position: "relative",
                              textAlign: "center",
                              fontFamily: '"Inter Variable", sans-serif',
                              "& .MuiDialogContent-root, & .MuiDialogContent-root .MuiTypography-root":
                                  {
                                      fontSize: "14px",
                                      lineHeight: "20px",
                                      fontWeight: 500,
                                      letterSpacing: 0,
                                  },
                              "& .MuiButton-root": {
                                  fontFamily: "inherit",
                                  fontSize: "14px",
                                  lineHeight: "20px",
                                  letterSpacing: 0,
                                  fontWeight: 500,
                                  minHeight: "48px",
                                  padding: "14px 24px",
                                  borderRadius: "20px",
                              },
                          }
                        : { maxWidth: "360px" },
                },
            }}
        >
            {centered && !attributes.nonClosable && (
                <IconButton
                    aria-label={t("close")}
                    disabled={busy}
                    onClick={handleClose}
                    sx={{
                        position: "absolute",
                        top: 16,
                        right: 16,
                        width: 36,
                        height: 36,
                        backgroundColor: "fill.faint",
                    }}
                >
                    <CloseIcon sx={{ fontSize: 20 }} />
                </IconButton>
            )}
            {centered ? (
                <Stack
                    sx={{
                        alignItems: "center",
                        pt: artwork ? "38px" : "64px",
                        px: 3.5,
                    }}
                >
                    {artwork && (
                        <Box
                            sx={{
                                mb: 3,
                                "& > svg": {
                                    fontSize: 48,
                                    color: "stroke.faint",
                                },
                            }}
                        >
                            {artwork}
                        </Box>
                    )}
                    {attributes.title && (
                        <DialogTitle
                            id={titleID}
                            sx={{
                                "&&&": { p: 0 },
                                fontFamily: '"Outfit Variable", sans-serif',
                                fontSize: "24px",
                                lineHeight: "32px",
                                fontWeight: 600,
                                letterSpacing: 0,
                            }}
                        >
                            {attributes.title}
                        </DialogTitle>
                    )}
                </Stack>
            ) : (attributes.icon ?? attributes.title) ? (
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
                            id={titleID}
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
            <DialogContent
                sx={centered ? { padding: "16px 28px 24px" } : undefined}
            >
                {attributes.message && (
                    <Typography
                        id={messageID}
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
                    {phase == "failed" &&
                        (centered ? (
                            <Box
                                sx={{
                                    display: "flex",
                                    justifyContent: "center",
                                }}
                            >
                                <InlineErrorIndicator />
                            </Box>
                        ) : (
                            <InlineErrorIndicator />
                        ))}
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
