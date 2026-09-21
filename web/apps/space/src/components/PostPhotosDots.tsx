import { Box } from "@mui/material";

export const SpacePostPhotosDots = ({
    index,
    count,
}: {
    index: number;
    count: number;
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
                        bgcolor:
                            photoIndex == index
                                ? "#FFFFFF"
                                : "rgba(255, 255, 255, 0.4)",
                        borderRadius: "50%",
                        boxShadow: "0 1px 2px rgba(0, 0, 0, 0.4)",
                        height: 5,
                        width: 5,
                    }}
                />
            ))}
        </Box>
    ) : null;
