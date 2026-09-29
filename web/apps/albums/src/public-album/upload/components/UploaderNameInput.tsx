import { User03Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    Dialog,
    IconButton,
    styled,
    TextField,
    Typography,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { useFormik } from "formik";
import { t } from "i18next";
import React from "react";

const SparkleTopRight: React.FC = () => (
    <svg
        width="14"
        height="16"
        viewBox="0 0 20 22"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ position: "absolute", top: 0, right: 8 }}
    >
        <path
            d="M19.728 9.21189C15.334 9.91374 11.912 12.6353 11.37 16.3181C11.912 12.6353 9.421 9.04853 5.4114 7.10627C9.806 6.40442 13.228 3.68284 13.77 7.55054e-05C13.228 3.68284 15.719 7.26962 19.728 9.21189Z"
            fill="#08C225"
        />
    </svg>
);

const SparkleBottomRight: React.FC = () => (
    <svg
        width="22"
        height="26"
        viewBox="0 0 32 36"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ position: "absolute", bottom: 0, right: -8 }}
    >
        <path
            d="M31.579 17.9746C23.591 18.7003 17.114 23.1692 15.689 29.722C17.114 23.1692 13.077 16.4145 6.1117 12.438C14.099 11.7122 20.576 7.2434 22.001 0.6902C20.576 7.2434 24.613 13.9981 31.579 17.9746Z"
            fill="#08C225"
        />
    </svg>
);

const SparkleBottomLeft: React.FC = () => (
    <svg
        width="18"
        height="16"
        viewBox="0 0 26 22"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        style={{ position: "absolute", bottom: 8, left: -8 }}
    >
        <path
            d="M25.9639 10.8477C19.9399 13.182 15.9104 18.0874 16.263 23.48C15.9104 18.0874 11.2832 13.7544 4.99991 12.2184C11.0238 9.884 15.0533 4.9787 14.7007 -0.4139C15.0533 4.9787 19.6805 9.3117 25.9639 10.8477Z"
            fill="#08C225"
        />
    </svg>
);

type UploaderNameInputProps = ModalVisibilityProps & {
    uploaderName: string;
    uploadFileCount: number;
    onSubmit: (name: string) => void | Promise<void>;
};

export const UploaderNameInput: React.FC<UploaderNameInputProps> = ({
    open,
    onClose,
    uploaderName,
    uploadFileCount,
    onSubmit,
}) => {
    return (
        <StyledDialog open={open} onClose={onClose}>
            <DialogWrapper>
                <CloseButton onClick={onClose}>
                    <CloseIcon sx={{ fontSize: 20 }} />
                </CloseButton>

                <ContentContainer>
                    <IllustrationContainer>
                        <SparkleTopRight />
                        <SparkleBottomRight />
                        <SparkleBottomLeft />
                        <IllustrationWrapper>
                            <HugeiconsIcon
                                icon={User03Icon}
                                size={28}
                                color="#fff"
                                strokeWidth={1.8}
                            />
                        </IllustrationWrapper>
                    </IllustrationContainer>

                    <TitleSection>
                        <Title>{t("enter_name")}</Title>
                        <Subtitle>{t("uploader_name_hint")}</Subtitle>
                    </TitleSection>

                    <UploaderNameInputForm
                        {...{
                            onClose,
                            uploaderName,
                            uploadFileCount,
                            onSubmit,
                        }}
                    />
                </ContentContainer>
            </DialogWrapper>
        </StyledDialog>
    );
};

const UploaderNameInputForm: React.FC<Omit<UploaderNameInputProps, "open">> = ({
    onClose,
    uploaderName,
    uploadFileCount,
    onSubmit,
}) => {
    const formik = useFormik({
        initialValues: { value: uploaderName },
        onSubmit: async (values, { setFieldError }) => {
            const value = values.value;
            const setValueFieldError = (message: string) =>
                setFieldError("value", message);

            if (!value) {
                setValueFieldError(t("required"));
                return;
            }
            try {
                await onSubmit(value);
                onClose();
            } catch (e) {
                log.error("Failed to submit uploader name", e);
                setValueFieldError(t("generic_error"));
            }
        },
    });

    return (
        <FormContainer onSubmit={formik.handleSubmit}>
            <StyledTextField
                name="value"
                value={formik.values.value}
                onChange={formik.handleChange}
                type="text"
                variant="standard"
                fullWidth
                autoFocus
                hiddenLabel
                aria-label={t("name")}
                placeholder={t("name_placeholder")}
                disabled={formik.isSubmitting}
                error={!!formik.errors.value}
                helperText={formik.errors.value}
            />
            <ButtonsSection>
                <SubmitButton
                    type="submit"
                    variant="contained"
                    disabled={
                        formik.isSubmitting || !formik.values.value.trim()
                    }
                    hasName={!!formik.values.value.trim()}
                >
                    {formik.isSubmitting
                        ? t("loading")
                        : t("add_photos_count", { count: uploadFileCount })}
                </SubmitButton>
            </ButtonsSection>
        </FormContainer>
    );
};

const StyledDialog = styled(Dialog)(({ theme }) => ({
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

const IllustrationContainer = styled(Box)(() => ({
    position: "relative",
    width: 100,
    height: 70,
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    marginBottom: 8,
}));

const IllustrationWrapper = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    width: 52,
    height: 52,
    borderRadius: "50%",
    backgroundColor: "#08C225",
}));

const TitleSection = styled(Box)(() => ({
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    gap: 9,
    textAlign: "center",
    marginBottom: 8,
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
    maxWidth: "75%",
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const FormContainer = styled("form")(() => ({
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: 16,
}));

const StyledTextField = styled(TextField)(({ theme }) => ({
    "& .MuiInput-root": {
        height: 54,
        backgroundColor: "#FAFAFA",
        borderRadius: 12,
        "&::before": { borderBottom: "1px solid #E0E0E0" },
        "&::after": { borderBottom: "2px solid #08C225" },
        "&:hover:not(.Mui-disabled)::before": {
            borderBottom: "1px solid #BDBDBD",
        },
    },
    "& .MuiInputBase-input": {
        padding: "0 16px",
        height: "100%",
        boxSizing: "border-box",
        fontSize: 16,
        color: "#000",
        "&::placeholder": { color: "#999", opacity: 1 },
    },
    ...theme.applyStyles("dark", {
        "& .MuiInput-root": {
            backgroundColor: "rgba(255, 255, 255, 0.08)",
            "&::before": { borderBottom: "1px solid rgba(255, 255, 255, 0.3)" },
            "&:hover:not(.Mui-disabled)::before": {
                borderBottom: "1px solid rgba(255, 255, 255, 0.5)",
            },
        },
        "& .MuiInputBase-input": {
            color: "#fff",
            "&::placeholder": { color: "rgba(255, 255, 255, 0.5)" },
        },
    }),
}));

const ButtonsSection = styled(Box)(() => ({
    width: "100%",
    display: "flex",
    flexDirection: "row",
    gap: 12,
}));

const SubmitButton = styled(Button)<{ hasName: boolean }>(
    ({ hasName, theme }) => ({
        display: "flex",
        padding: "16px",
        justifyContent: "center",
        alignItems: "center",
        gap: 8,
        flex: 1,
        borderRadius: 20,
        backgroundColor: hasName ? "#08C225" : "rgba(0, 0, 0, 0.04)",
        fontSize: 16,
        fontWeight: 500,
        textTransform: "none",
        color: hasName ? "#fff" : "#999",
        boxShadow: "none",
        "&:hover": {
            backgroundColor: hasName ? "#07A820" : "rgba(0, 0, 0, 0.08)",
            boxShadow: "none",
        },
        ...theme.applyStyles("dark", {
            backgroundColor: hasName ? "#08C225" : "rgba(255, 255, 255, 0.08)",
            color: hasName ? "#fff" : "rgba(255, 255, 255, 0.5)",
            "&:hover": {
                backgroundColor: hasName
                    ? "#07A820"
                    : "rgba(255, 255, 255, 0.12)",
            },
        }),
    }),
);
