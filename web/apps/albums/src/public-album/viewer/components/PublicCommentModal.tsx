import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Button,
    Dialog,
    IconButton,
    styled,
    Typography,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { t } from "i18next";
import React from "react";

// =============================================================================
// Icons
// =============================================================================

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
            id="mask0_737_21326"
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
        <g mask="url(#mask0_737_21326)">
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

// =============================================================================
// Types
// =============================================================================

export interface PublicCommentModalProps extends ModalVisibilityProps {
    /**
     * Called when user clicks "Comment anonymously".
     */
    onCommentAnonymously: () => void;
    /**
     * Called when user clicks "Join album and comment".
     */
    onJoinAlbumToComment: () => void;
    /**
     * Whether the "Join album" option is enabled for this public link.
     * When false, the "Join album and comment" button will be hidden.
     */
    enableJoin?: boolean;
}

/**
 * Modal dialog for commenting on a photo in a public album.
 * Shows options to comment anonymously or sign in to comment.
 */
export const PublicCommentModal: React.FC<PublicCommentModalProps> = ({
    open,
    onClose,
    onCommentAnonymously,
    onJoinAlbumToComment,
    enableJoin = true,
}) => {
    return (
        <StyledDialog open={open} onClose={onClose}>
            <DialogWrapper>
                <CloseButton onClick={onClose}>
                    <CloseIcon sx={{ fontSize: 20 }} />
                </CloseButton>

                <ContentContainer>
                    <IllustrationWrapper>
                        <CommentIllustration />
                    </IllustrationWrapper>

                    <TitleSection>
                        <Title>{t("say_something_nice")}</Title>
                        {enableJoin && (
                            <Subtitle>{t("public_comment_subtitle")}</Subtitle>
                        )}
                    </TitleSection>

                    <ButtonsSection sx={!enableJoin ? { mt: 4 } : undefined}>
                        {enableJoin ? (
                            <AnonymousButton
                                variant="outlined"
                                fullWidth
                                onClick={onCommentAnonymously}
                            >
                                {t("comment_anonymously")}
                            </AnonymousButton>
                        ) : (
                            <SignInButton
                                variant="contained"
                                fullWidth
                                onClick={onCommentAnonymously}
                            >
                                {t("comment_anonymously")}
                            </SignInButton>
                        )}
                        {enableJoin && (
                            <SignInButton
                                variant="contained"
                                fullWidth
                                onClick={onJoinAlbumToComment}
                            >
                                {t("join_album_and_comment")}
                            </SignInButton>
                        )}
                    </ButtonsSection>
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
    maxWidth: 240,
    ...theme.applyStyles("dark", { color: "rgba(255, 255, 255, 0.7)" }),
}));

const ButtonsSection = styled(Box)(() => ({
    width: "100%",
    display: "flex",
    flexDirection: "column",
    gap: 12,
}));

const AnonymousButton = styled(Button)(({ theme }) => ({
    display: "flex",
    padding: "20px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 8,
    flex: "1 0 0",
    borderRadius: 20,
    backgroundColor: "rgba(0, 0, 0, 0.04)",
    border: "none",
    fontSize: 16,
    fontWeight: 500,
    textTransform: "none",
    color: "#000",
    "&:hover": { backgroundColor: "rgba(0, 0, 0, 0.08)", border: "none" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255, 255, 255, 0.08)",
        color: "#fff",
        "&:hover": { backgroundColor: "rgba(255, 255, 255, 0.12)" },
    }),
}));

const SignInButton = styled(Button)(() => ({
    display: "flex",
    padding: "20px 16px",
    justifyContent: "center",
    alignItems: "center",
    gap: 8,
    flex: "1 0 0",
    borderRadius: 20,
    backgroundColor: "#08C225",
    fontSize: 16,
    fontWeight: 500,
    textTransform: "none",
    color: "#fff",
    "&:hover": { backgroundColor: "#07A820" },
}));
