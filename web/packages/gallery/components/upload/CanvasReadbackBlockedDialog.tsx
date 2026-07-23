import CloseIcon from "@mui/icons-material/Close";
import ErrorOutlineRoundedIcon from "@mui/icons-material/ErrorOutlineRounded";
import {
    Box,
    Dialog,
    IconButton,
    Link,
    styled,
    Typography,
    type DialogProps,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React from "react";

export type CanvasReadbackBlockedDialogProps = ModalVisibilityProps;

export const CanvasReadbackBlockedDialog: React.FC<
    CanvasReadbackBlockedDialogProps
> = ({ open, onClose }) => (
    <StyledDialog open={open} onClose={onClose}>
        <DialogWrapper>
            <CloseButton onClick={onClose}>
                <CloseIcon sx={{ fontSize: 20 }} />
            </CloseButton>
            <ContentContainer>
                <IllustrationWrapper>
                    <ErrorIconContainer>
                        <ErrorOutlineRoundedIcon sx={{ fontSize: 48 }} />
                    </ErrorIconContainer>
                </IllustrationWrapper>

                <TitleSection>
                    <Title>{t("canvas_blocked_upload_failed_title")}</Title>
                    <Subtitle>
                        {t("canvas_blocked_upload_failed_description")}{" "}
                        <HelpLink
                            href="https://ente.com/help/photos/faq/troubleshooting#thumbnails"
                            target="_blank"
                            rel="noopener"
                        >
                            {t("learn_how")}
                        </HelpLink>
                        .
                    </Subtitle>
                </TitleSection>
            </ContentContainer>
        </DialogWrapper>
    </StyledDialog>
);

const StyledDialog = styled(Dialog)<DialogProps>(({ theme }) => ({
    "& .MuiDialog-paper": {
        width: 381,
        maxWidth: "calc(100% - 32px)",
        borderRadius: 28,
        backgroundColor: "#fff",
        padding: 0,
        margin: 16,
        overflow: "visible",
        boxShadow: "none",
        border: "1px solid #E0E0E0",
        ...theme.applyStyles("dark", {
            backgroundColor: "#1b1b1b",
            border: "1px solid rgba(255, 255, 255, 0.18)",
        }),
    },
    "& .MuiBackdrop-root": { backgroundColor: "rgba(0, 0, 0, 0.5)" },
}));

const DialogWrapper = styled(Box)(() => ({
    position: "relative",
    padding: "48px 16px 16px 16px",
}));

const CloseButton = styled(IconButton)(({ theme }) => ({
    position: "absolute",
    top: 11,
    right: 12,
    backgroundColor: "#FAFAFA",
    color: "#000",
    padding: 10,
    "&:hover": { backgroundColor: "#F0F0F0" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.12)",
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.16)" },
    }),
}));

const ContentContainer = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 16,
}));

const IllustrationWrapper = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    marginBottom: 8,
}));

const ErrorIconContainer = styled(Box)(({ theme }) => ({
    width: 92,
    height: 92,
    borderRadius: 56,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "rgba(229, 57, 53, 0.12)",
    color: "#E53935",
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 138, 128, 0.15)",
        color: "#FF8A80",
    }),
}));

const TitleSection = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 9,
    width: "100%",
    textAlign: "center",
    marginBottom: 16,
}));

const Title = styled(Typography)(({ theme }) => ({
    fontWeight: 600,
    fontSize: 24,
    lineHeight: "28px",
    letterSpacing: "-0.48px",
    color: "#000",
    ...theme.applyStyles("dark", { color: "#fff" }),
}));

const Subtitle = styled(Typography)(({ theme }) => ({
    fontWeight: 500,
    fontSize: 14,
    lineHeight: "20px",
    color: "#666666",
    width: "100%",
    padding: "0 8px",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const HelpLink = styled(Link)(({ theme }) => ({
    fontWeight: "inherit",
    fontSize: 14,
    lineHeight: "20px",
    color: "#08C225",
    textDecorationColor: "#08C225",
    "&:hover": { color: "#07A820", textDecorationColor: "#07A820" },
    ...theme.applyStyles("dark", {
        color: "#22D840",
        textDecorationColor: "#22D840",
        "&:hover": { color: "#4BE066", textDecorationColor: "#4BE066" },
    }),
}));
