import { accentGreen } from "@/theme/buttons";
import {
    dialogDescriptionSx,
    dialogHeaderSx,
    dialogTitleSx,
} from "@/theme/dialogs";
import { Box, LinearProgress, Typography } from "@mui/material";
import { useEffect, useRef } from "react";
import { BookIcon, SuccessIcon, UploadIcon } from "./icons";

export type CheckoutProgress =
    | { stage: "preparing" | "uploading"; percent: number }
    | { stage: "opening" };

const preparationShare = 42;

const stages = {
    preparing: {
        Icon: BookIcon,
        title: "Preparing your book",
        description:
            "We’re putting your photos and pages together for print. The upload will start automatically.",
    },
    uploading: {
        Icon: UploadIcon,
        title: "Uploading your book",
        description:
            "Keep this tab open. Checkout will open automatically when the upload finishes.",
    },
    opening: {
        Icon: SuccessIcon,
        title: "Opening checkout",
        description:
            "Your photobook is ready. We’ll take you to the checkout page in a moment.",
    },
};

export default function CheckoutProgressContent({
    progress,
}: {
    progress: CheckoutProgress;
}) {
    const { Icon, title, description } = stages[progress.stage];
    const titleRef = useRef<HTMLHeadingElement>(null);
    useEffect(() => {
        titleRef.current?.focus({ preventScroll: true });
    }, []);
    let percent = 100;
    if (progress.stage === "preparing") {
        percent = Math.round((preparationShare * progress.percent) / 100);
    } else if (progress.stage === "uploading") {
        percent =
            preparationShare +
            Math.round(((100 - preparationShare) * progress.percent) / 100);
    }

    return (
        <Box
            sx={{
                gridArea: "1 / 1",
                alignSelf: "center",
                minHeight: 300,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                p: "34px 16px 16px",
                "@media (prefers-reduced-motion: no-preference)": {
                    animation:
                        "checkout-content-in 150ms ease-out 70ms backwards",
                    "@keyframes checkout-content-in": {
                        from: { opacity: 0 },
                        to: { opacity: 1 },
                    },
                },
            }}
        >
            <Icon aria-hidden strokeWidth={1.65} sx={{ fontSize: 56 }} />
            <Box sx={{ ...dialogHeaderSx, mt: "22px" }} aria-live="polite">
                <Typography
                    component="h2"
                    ref={titleRef}
                    tabIndex={-1}
                    id="checkout-progress-title"
                    sx={{ ...dialogTitleSx, outline: "none" }}
                >
                    {title}
                </Typography>
                <Typography
                    id="checkout-progress-description"
                    sx={{ ...dialogDescriptionSx, maxWidth: 306 }}
                >
                    {description}
                </Typography>
            </Box>
            <Box
                sx={{
                    width: "100%",
                    mt: "auto",
                    display: "flex",
                    alignItems: "center",
                    gap: "12px",
                    minHeight: 56,
                    px: "17px",
                    borderRadius: "20px",
                    bgcolor: "#2c2c2c",
                }}
            >
                <LinearProgress
                    aria-label="Book preparation and upload"
                    variant="determinate"
                    value={percent}
                    sx={{
                        flex: 1,
                        height: 6,
                        borderRadius: "3px",
                        bgcolor: "#454545",
                        "& .MuiLinearProgress-bar": {
                            bgcolor: accentGreen,
                            borderRadius: "inherit",
                        },
                    }}
                />
                <Typography
                    component="span"
                    aria-hidden
                    sx={{
                        minWidth: "4ch",
                        textAlign: "right",
                        color: "white",
                        fontSize: 14,
                        fontWeight: 500,
                        fontVariantNumeric: "tabular-nums",
                    }}
                >
                    {percent}%
                </Typography>
            </Box>
        </Box>
    );
}
