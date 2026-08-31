import { keyframes } from "@mui/material/styles";

export const spacePostLikePopDurationMs = 520;
export const spacePostLikePopTiming = "cubic-bezier(0.2, 0.82, 0.22, 1)";

export const spacePostLikeButtonPop = keyframes`
    0% {
        transform: scale(1);
    }

    36% {
        transform: scale(1.045);
    }

    68% {
        transform: scale(0.99);
    }

    100% {
        transform: scale(1);
    }
`;

export const spacePostLikeHeartPop = keyframes`
    0% {
        opacity: 0.72;
        transform: scale(0.58);
    }

    44% {
        opacity: 1;
        transform: scale(1.38);
    }

    72% {
        transform: scale(0.93);
    }

    100% {
        opacity: 1;
        transform: scale(1);
    }
`;
