import { Box } from "@mui/material";

export const SpacePostPhotosBadge = ({
    count,
    inset = 10,
    subtle = false,
}: {
    count: number;
    inset?: number;
    subtle?: boolean;
}) =>
    count > 1 ? (
        <Box
            component="span"
            aria-label={`${count} items`}
            sx={{
                alignItems: "center",
                color: "#FFFFFF",
                display: "flex",
                filter: "drop-shadow(0 1px 2px rgba(0, 0, 0, 0.5))",
                height: 24,
                justifyContent: "center",
                pointerEvents: "none",
                position: "absolute",
                right: inset,
                top: inset,
                width: 24,
                zIndex: 2,
            }}
        >
            <svg
                aria-hidden
                width={subtle ? 15 : 18}
                height={subtle ? 15 : 18}
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth={1.6}
                strokeLinecap="round"
                strokeLinejoin="round"
                style={{ transform: "scaleX(-1)" }}
            >
                <path
                    d="M13 3H15C17.8284 3 19.2426 3 20.1213 3.87868C21 4.75736 21 6.17157 21 9V11C21 13.8284 21 15.2426 20.1213 16.1213C19.2426 17 17.8284 17 15 17H13C10.1716 17 8.75736 17 7.87868 16.1213C7 15.2426 7 13.8284 7 11V9C7 6.17157 7 4.75736 7.87868 3.87868C8.75736 3 10.1716 3 13 3Z"
                    fill="currentColor"
                />
                <path d="M16 20.1213C15.1213 21 13.7071 21 10.8787 21H9C6.17157 21 4.75736 21 3.87868 20.1213C3 19.2426 3 17.8284 3 15V13.1213C3 10.2929 3 8.87868 3.87868 8" />
            </svg>
        </Box>
    ) : null;

export const SpacePostVideoBadge = ({
    durationMs,
    size,
}: {
    durationMs?: number;
    size?: number;
}) =>
    durationMs == undefined ? null : (
        <Box
            component="span"
            aria-label="Video"
            sx={{
                position: "absolute",
                left: "50%",
                top: "50%",
                transform: "translate(-50%, -50%)",
                zIndex: 2,
                pointerEvents: "none",
                color: "#FFFFFF",
                display: "flex",
                filter: "drop-shadow(0 1px 3px rgba(0, 0, 0, 0.65))",
                aspectRatio: "1",
                width: size ?? "clamp(14px, 14%, 28px)",
            }}
        >
            <svg
                aria-hidden
                width="100%"
                height="100%"
                viewBox="0 0 24 24"
                fill="currentColor"
            >
                <path d="M6 3v18l15-9z" />
            </svg>
        </Box>
    );
