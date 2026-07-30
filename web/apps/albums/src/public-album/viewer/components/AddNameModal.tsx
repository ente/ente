import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    CircularProgress,
    Dialog,
    IconButton,
    styled,
    TextField,
    Typography,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React, { useRef, useState } from "react";

// =============================================================================
// Icons
// =============================================================================

const LikeIllustration: React.FC = () => (
    <svg
        width="126"
        height="121"
        viewBox="0 0 126 121"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M84.7129 23.0781C96.7222 23.0784 105.29 32.8476 105.29 44.499C105.29 53.3449 99.7258 62.2116 93.4453 69.4932C87.0622 76.8936 79.4391 83.2238 74.3574 87.0557C69.973 90.3616 64.031 90.3614 59.6465 87.0557C54.5648 83.2238 46.9408 76.8937 40.5576 69.4932C34.2771 62.2116 28.7129 53.3449 28.7129 44.499C28.713 32.8474 37.2813 23.0781 49.291 23.0781C54.9545 23.0782 60.4297 24.9062 67.001 30.9004C73.5726 24.9056 79.0491 23.0781 84.7129 23.0781Z"
            fill="#08C225"
            stroke="#232323"
            strokeWidth="5.73358"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <mask
            id="mask0_add_name"
            style={{ maskType: "alpha" }}
            maskUnits="userSpaceOnUse"
            x="31"
            y="25"
            width="72"
            height="62"
        >
            <path
                d="M61.3721 84.7662C51.3787 77.2306 31.5801 60.0026 31.5801 44.4993C31.5801 34.2522 39.0372 25.9453 49.2909 25.9453C54.6041 25.9453 59.9173 27.7313 67.0016 34.8751C74.086 27.7313 79.3992 25.9453 84.7124 25.9453C94.9659 25.9453 102.423 34.2522 102.423 44.4993C102.423 60.0026 82.6247 77.2306 72.6312 84.7662C69.2683 87.3019 64.735 87.3019 61.3721 84.7662Z"
                fill="#08C225"
            />
        </mask>
        <g mask="url(#mask0_add_name)">
            <path
                d="M47.5975 41.0431C46.8515 39.3306 47.9859 37.1849 50.1312 36.2504C52.2765 35.316 54.6203 35.9467 55.3662 37.6591C56.1121 39.3716 54.9777 41.5173 52.8324 42.4518C50.6872 43.3862 48.3434 42.7555 47.5975 41.0431Z"
                fill="white"
            />
            <path
                d="M44.5677 45.0545C44.3136 44.4712 44.7025 43.7391 45.4364 43.4194C46.1704 43.0997 46.9713 43.3135 47.2254 43.8968C47.4795 44.4802 47.0906 45.2123 46.3567 45.532C45.6227 45.8517 44.8218 45.6379 44.5677 45.0545Z"
                fill="white"
            />
            <path
                d="M102.994 32.271C101.622 55.1395 78.9821 78.0073 50.9683 82.581C49.2531 88.2982 42.3926 93.7861 42.3926 95.1582C42.3926 96.5303 48.1097 107.926 50.9683 113.453L89.8447 101.447L115 66.5725C113.094 57.9969 106.196 31.3563 102.994 32.271Z"
                fill="#46A030"
            />
            <path
                d="M59.7039 28.2666C34.9591 23.1218 29.8137 47.7054 32.6723 55.1377L23.1143 51.7074C21.3992 47.3243 18.1976 37.9863 19.1123 35.6995C20.0271 33.4126 22.1615 16.833 23.1143 8.829L55.1302 3.68359L96.8651 13.9744C97.6274 18.1664 98.4659 26.8936 95.7217 28.2666C80.2855 22.5506 66.5644 33.9826 66.5644 33.4109C66.5644 32.9535 68.4701 30.5523 69.423 29.4089C66.3738 29.0281 60.1612 28.2666 59.7039 28.2666Z"
                fill="white"
            />
        </g>
        <path
            d="M20.9639 58.8477C14.9399 61.182 10.9104 66.0874 11.263 71.48C10.9104 66.0874 6.28324 61.7544 -9.80907e-05 60.2184C6.02383 57.884 10.0533 52.9787 9.70073 47.5861C10.0533 52.9787 14.6805 57.3117 20.9639 58.8477Z"
            fill="#08C225"
        />
        <path
            d="M119.579 91.9746C111.591 92.7003 105.114 97.1692 103.689 103.722C105.114 97.1692 101.077 90.4145 94.1117 86.438C102.099 85.7122 108.576 81.2434 110.001 74.6902C108.576 81.2434 112.613 87.9981 119.579 91.9746Z"
            fill="#08C225"
        />
        <path
            d="M112.728 9.21189C108.334 9.91374 104.912 12.6353 104.37 16.3181C104.912 12.6353 102.421 9.04853 98.4114 7.10627C102.806 6.40442 106.228 3.68284 106.77 7.55054e-05C106.228 3.68284 108.719 7.26962 112.728 9.21189Z"
            fill="#08C225"
        />
    </svg>
);

const CommentIllustration: React.FC = () => (
    <svg
        width="146"
        height="104"
        viewBox="0 0 146 104"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M62.4161 23.9825C69.5416 21.6377 77.2027 21.4587 84.4301 23.4677C91.6577 25.4768 98.1278 29.5846 103.021 35.2705C107.914 40.9564 111.011 47.9656 111.921 55.4117C112.83 62.8579 111.511 70.4066 108.131 77.1033C104.75 83.8 99.4603 89.3444 92.929 93.0344C86.3977 96.7244 78.9186 98.3952 71.438 97.8347C65.5124 97.3907 59.9955 95.6061 55.1766 92.7912L36.6137 95.1736C35.7803 95.2805 34.9485 94.962 34.4004 94.3252C33.8523 93.6882 33.6604 92.8183 33.8903 92.0101L39.0115 74.0065C36.9468 68.823 36.0051 63.1057 36.4493 57.1772C37.0098 49.6966 39.7764 42.5499 44.3984 36.6414C49.0204 30.733 55.2905 26.3274 62.4161 23.9825Z"
            fill="#08C225"
            stroke="#232323"
            strokeWidth="5"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <mask
            id="mask0_add_name_comment"
            style={{ maskType: "alpha" }}
            maskUnits="userSpaceOnUse"
            x="36"
            y="24"
            width="74"
            height="72"
        >
            <path
                d="M71.6249 95.341C78.6125 95.8645 85.5985 94.3043 91.6993 90.8575C97.8002 87.4107 102.742 82.2321 105.899 75.9768C109.057 69.7214 110.289 62.6702 109.439 55.7147C108.59 48.7592 105.696 42.2119 101.126 36.9007C96.5551 31.5895 90.512 27.753 83.7608 25.8763C77.0096 23.9996 69.8535 24.167 63.1974 26.3573C56.5414 28.5477 50.6843 32.6626 46.3669 38.1817C42.0494 43.7008 39.4656 50.3762 38.942 57.3639C38.5044 63.2051 39.5049 68.8185 41.6537 73.8587L36.2949 92.6938L55.7183 90.2015C60.382 93.0774 65.7876 94.9037 71.6249 95.341Z"
                fill="#08C225"
            />
        </mask>
        <g mask="url(#mask0_add_name_comment)">
            <path
                d="M90.785 29.2779C55.9844 19.5648 41.0889 44.5028 37.9912 58.186L34.2834 72.1186C32.1784 72.553 27.1513 72.4724 23.883 68.6747C19.7976 63.9275 7.9607 55.936 8.75491 45.336C9.54911 34.736 9.85699 18.7723 10.8726 17.072C11.6851 15.7117 48.8217 4.51972 67.2885 -0.90625L123.817 3.32912C127.307 16.0258 125.586 38.991 90.785 29.2779Z"
                fill="white"
            />
            <path
                d="M68.1126 36.8926C67.7871 34.8769 69.5702 32.9123 72.0953 32.5044C74.6204 32.0966 76.9313 33.4 77.2568 35.4157C77.5824 37.4313 75.7993 39.3959 73.2742 39.8038C70.7491 40.2116 68.4382 38.9082 68.1126 36.8926Z"
                fill="white"
            />
            <path
                d="M63.6068 40.3106C63.4959 39.624 64.1063 38.9542 64.9702 38.8147C65.834 38.6752 66.6242 39.1187 66.7351 39.8054C66.846 40.492 66.2356 41.1618 65.3718 41.3013C64.5079 41.4408 63.7177 40.9973 63.6068 40.3106Z"
                fill="white"
            />
            <path
                d="M35.0516 84.4974C50.0736 86.3458 84.2825 85.3953 100.941 66.8061C117.601 48.217 131.472 23.1618 129.517 33.958C128.008 42.824 108.57 103.778 97.3574 108.665C83.3409 114.774 55.5151 127.853 46.4893 128.205C37.4635 128.557 25.3268 115.992 24.0509 114.477C22.775 112.962 24.2879 103.196 26.2494 99.9921C27.959 97.1997 26.5317 91.4899 26.2742 90.6394C26.2622 90.6323 26.2542 90.6209 26.2503 90.6048C26.2237 90.4942 26.2362 90.514 26.2742 90.6394C26.7756 90.9343 34.2208 83.5106 35.0516 84.4974Z"
                fill="#24B41F"
            />
            <path
                d="M63.1172 64.2407C65.5626 64.2849 67.581 62.3384 67.6253 59.8929C67.6695 57.4475 65.723 55.4291 63.2775 55.3849C60.8321 55.3406 58.8137 57.2871 58.7694 59.7326C58.7252 62.1781 60.6717 64.1964 63.1172 64.2407Z"
                fill="#232323"
            />
            <path
                d="M75.293 64.4555C77.7384 64.4998 79.7568 62.5532 79.801 60.1078C79.8453 57.6623 77.8988 55.644 75.4533 55.5997C73.0078 55.5554 70.9895 57.502 70.9452 59.9474C70.901 62.3929 72.8475 64.4112 75.293 64.4555Z"
                fill="#232323"
            />
            <path
                d="M87.4707 64.6821C89.9162 64.7263 91.9345 62.7798 91.9788 60.3343C92.023 57.8889 90.0765 55.8705 87.631 55.8263C85.1856 55.782 83.1672 57.7285 83.123 60.174C83.0787 62.6195 85.0252 64.6378 87.4707 64.6821Z"
                fill="#232323"
            />
        </g>
        <path
            d="M20.1099 75.4512C14.3314 77.6905 10.4661 82.396 10.8043 87.5689C10.4661 82.396 6.02735 78.2395 0 76.7661C5.77852 74.5268 9.64385 69.8213 9.30562 64.6484C9.64385 69.8213 14.0826 73.9778 20.1099 75.4512Z"
            fill="#08C225"
        />
        <path
            d="M145.699 62.5334C138.037 63.2295 131.824 67.5164 130.457 73.8026C131.824 67.5164 127.951 61.0368 121.27 57.2223C128.932 56.5261 135.145 52.2393 136.512 45.9531C135.145 52.2393 139.017 58.7188 145.699 62.5334Z"
            fill="#08C225"
        />
        <path
            d="M51.1361 8.83653C46.9208 9.50979 43.6377 12.1205 43.1181 15.6532C43.6377 12.1205 41.2488 8.67983 37.4023 6.81669C41.6176 6.14343 44.9007 3.53273 45.4202 0C44.9007 3.53273 47.2896 6.97339 51.1361 8.83653Z"
            fill="#08C225"
        />
    </svg>
);

export interface AddNameModalProps extends ModalVisibilityProps {
    /**
     * Called when user submits their name.
     */
    onSubmit: (name: string) => void;
    /**
     * The type of action being performed (like or comment).
     * Defaults to 'like'.
     */
    actionType?: "like" | "comment";
    /**
     * Called after the modal's exit animation completes.
     */
    onExited?: () => void;
}

/**
 * Modal dialog for adding a name when liking or commenting on a photo anonymously.
 */
export const AddNameModal: React.FC<AddNameModalProps> = ({
    open,
    onClose,
    onSubmit,
    actionType = "like",
    onExited,
}) => {
    const [name, setName] = useState("");
    const [isSubmitting, setIsSubmitting] = useState(false);
    const isSubmittingRef = useRef(false);
    const isComment = actionType === "comment";

    const handleSubmit = () => {
        const trimmedName = name.trim();
        if (!trimmedName || isSubmittingRef.current) return;

        isSubmittingRef.current = true;
        setIsSubmitting(true);
        onSubmit(trimmedName);
    };

    const handleClose = () => {
        if (isSubmittingRef.current) return;
        onClose();
    };

    const keepInputFocusedOnSubmitButtonMouseDown = (
        e: React.MouseEvent<HTMLButtonElement>,
    ) => {
        e.preventDefault();
    };

    const handleExited = () => {
        setName("");
        isSubmittingRef.current = false;
        setIsSubmitting(false);
        onExited?.();
    };

    return (
        <StyledDialog
            open={open}
            onClose={handleClose}
            slotProps={{ transition: { onExited: handleExited } }}
        >
            <DialogWrapper>
                <CloseButton onClick={handleClose}>
                    <CloseIcon sx={{ fontSize: 20 }} />
                </CloseButton>

                <ContentContainer>
                    <IllustrationWrapper>
                        {isComment ? (
                            <CommentIllustration />
                        ) : (
                            <LikeIllustration />
                        )}
                    </IllustrationWrapper>

                    <TitleSection>
                        <Title>{t("set_your_name")}</Title>
                        <Subtitle>{t("set_your_name_subtitle")}</Subtitle>
                    </TitleSection>

                    <StyledTextField
                        fullWidth
                        placeholder={t("name_placeholder")}
                        variant="standard"
                        value={name}
                        className={isSubmitting ? "is-submitting" : undefined}
                        onChange={(e) => setName(e.target.value)}
                        onKeyDown={(e) => {
                            if (e.key === "Enter") {
                                e.preventDefault();
                                handleSubmit();
                            }
                        }}
                        autoFocus
                        slotProps={{
                            htmlInput: {
                                maxLength: 50,
                                readOnly: isSubmitting,
                                "aria-readonly": isSubmitting,
                            },
                        }}
                    />

                    <SubmitButton
                        variant="contained"
                        fullWidth
                        onClick={handleSubmit}
                        onMouseDown={keepInputFocusedOnSubmitButtonMouseDown}
                        hasName={!!name.trim()}
                        disabled={isSubmitting || !name.trim()}
                        aria-busy={isSubmitting}
                        aria-label={
                            isComment ? t("set_name") : t("set_name_and_like")
                        }
                    >
                        {isSubmitting ? (
                            <CircularProgress
                                size={18}
                                sx={{ color: "inherit" }}
                            />
                        ) : isComment ? (
                            t("set_name")
                        ) : (
                            t("set_name_and_like")
                        )}
                    </SubmitButton>
                </ContentContainer>
            </DialogWrapper>
        </StyledDialog>
    );
};

// =============================================================================
// Styled Components
// =============================================================================

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

const IllustrationWrapper = styled(Box)(() => ({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
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
    maxWidth: 295,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
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
    "&.is-submitting .MuiInput-root::after": { transform: "scaleX(1)" },
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

const SubmitButton = styled(Button)<{ hasName: boolean }>(
    ({ hasName, theme }) => ({
        display: "flex",
        padding: "20px 16px",
        minHeight: 64,
        justifyContent: "center",
        alignItems: "center",
        gap: 8,
        flex: "1 0 0",
        borderRadius: 20,
        backgroundColor: hasName ? "#08C225" : "rgba(0, 0, 0, 0.04)",
        fontSize: 16,
        fontWeight: 500,
        lineHeight: "24px",
        textTransform: "none",
        color: hasName ? "#fff" : "#999",
        boxShadow: "none",
        "&:hover": {
            backgroundColor: hasName ? "#07A820" : "rgba(0, 0, 0, 0.08)",
            boxShadow: "none",
        },
        "&.Mui-disabled": {
            backgroundColor: hasName ? "#08C225" : "rgba(0, 0, 0, 0.04)",
            color: hasName ? "#fff" : "#999",
        },
        ...theme.applyStyles("dark", {
            backgroundColor: hasName ? "#08C225" : "rgba(255, 255, 255, 0.08)",
            color: hasName ? "#fff" : "rgba(255, 255, 255, 0.5)",
            "&:hover": {
                backgroundColor: hasName
                    ? "#07A820"
                    : "rgba(255, 255, 255, 0.12)",
            },
            "&.Mui-disabled": {
                backgroundColor: hasName
                    ? "#08C225"
                    : "rgba(255, 255, 255, 0.08)",
                color: hasName ? "#fff" : "rgba(255, 255, 255, 0.5)",
            },
        }),
    }),
);
