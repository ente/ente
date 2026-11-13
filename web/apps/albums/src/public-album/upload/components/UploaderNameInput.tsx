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

const ENTER_NAME_ILLUSTRATION_SRC = new URL(
    "./enter-name.svg",
    import.meta.url,
).toString();

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
                    <Illustration
                        src={ENTER_NAME_ILLUSTRATION_SRC}
                        alt=""
                        aria-hidden
                        draggable={false}
                    />

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

const Illustration = styled("img")(() => ({
    display: "block",
    width: 126,
    height: 121,
    marginBottom: 8,
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
