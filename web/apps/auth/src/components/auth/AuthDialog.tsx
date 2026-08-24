import {
    Dialog,
    GlobalStyles,
    Slide,
    styled,
    type ModalProps,
} from "@mui/material";
import type { TransitionProps } from "@mui/material/transitions";
import React, { forwardRef } from "react";
import {
    authBodyTypography,
    authColorVariables,
    authDisplayFontFamily,
    authMobileMediaQuery,
} from "./styles";

interface AuthDialogProps extends React.PropsWithChildren {
    open: boolean;
    onClose: ModalProps["onClose"];
    ariaLabelledby?: string;
}

const SlideUpTransition = forwardRef(function SlideUpTransition(
    props: TransitionProps & { children: React.ReactElement },
    ref: React.Ref<unknown>,
) {
    return <Slide direction="up" ref={ref} {...props} />;
});

export const AuthDialog: React.FC<AuthDialogProps> = ({
    open,
    onClose,
    ariaLabelledby,
    children,
}) => (
    <DialogRoot
        open={open}
        onClose={onClose}
        slots={{ transition: SlideUpTransition }}
        slotProps={{
            backdrop: { sx: { backgroundColor: "rgba(0, 0, 0, 0.4)" } },
        }}
        maxWidth={false}
        aria-labelledby={ariaLabelledby}
    >
        <GlobalStyles styles={authColorVariables} />
        <SheetHandle />
        {children}
    </DialogRoot>
);

export const AuthDialogHeader = styled("div")({
    display: "flex",
    flexDirection: "column",
    gap: "6px",
});

export const AuthDialogTitle = styled("h2")({
    margin: 0,
    fontFamily: authDisplayFontFamily,
    fontSize: "22px",
    fontWeight: 600,
    lineHeight: "30px",
    color: "var(--auth-app-text)",
    [authMobileMediaQuery]: { fontSize: "20px", lineHeight: "28px" },
});

export const AuthDialogText = styled("p")({
    ...authBodyTypography,
    margin: 0,
    color: "var(--auth-app-text-muted)",
    textWrap: "pretty",
});

const DialogRoot = styled(Dialog)(({ theme }) => ({
    "& .MuiDialog-paper": {
        width: "456px",
        maxWidth: "calc(100% - 32px)",
        margin: "16px",
        padding: "32px",
        boxSizing: "border-box",
        borderRadius: "24px",
        backgroundColor: "#fff",
        backgroundImage: "none",
        boxShadow: "0 4px 16px rgba(0, 0, 0, 0.14)",
        ...theme.applyStyles("dark", { backgroundColor: "#252525" }),
    },
    [authMobileMediaQuery]: {
        "& .MuiDialog-container": { alignItems: "flex-end" },
        "& .MuiDialog-paper": {
            width: "100%",
            maxWidth: "100%",
            margin: 0,
            padding: "12px 24px 28px",
            borderRadius: "24px 24px 0 0",
        },
    },
}));

const SheetHandle = styled("div")({
    display: "none",
    [authMobileMediaQuery]: {
        display: "block",
        width: "36px",
        height: "4px",
        flexShrink: 0,
        margin: "0 auto 20px",
        borderRadius: "999px",
        backgroundColor: "var(--auth-app-fill-active)",
    },
});
