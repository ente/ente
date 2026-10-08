import { Box } from "@mui/material";

export const SpacePostPhotosDots = ({
    index,
    count,
    activeColor = "#08C225",
}: {
    index: number;
    count: number;
    activeColor?: string;
}) =>
    count > 1 ? (
        <Box
            component="span"
            aria-hidden
            sx={{
                alignItems: "center",
                alignSelf: "center",
                display: "inline-flex",
                flexShrink: 0,
                gap: "6px",
                pointerEvents: "none",
            }}
        >
            {Array.from({ length: count }, (_, photoIndex) => (
                <Box
                    key={photoIndex}
                    component="span"
                    sx={{
                        bgcolor: photoIndex == index ? activeColor : "#FFFFFF",
                        borderRadius: "50%",
                        boxShadow: "0 1px 2px rgba(0, 0, 0, 0.4)",
                        height: photoIndex == index ? 6 : 5,
                        width: photoIndex == index ? 6 : 5,
                    }}
                />
            ))}
        </Box>
    ) : null;
