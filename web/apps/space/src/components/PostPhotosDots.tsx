import { Box } from "@mui/material";
import { photoDotStep } from "components/post-photos-dots";

export const SpacePostPhotosDots = ({
    index,
    count,
    activeColor = "#08C225",
    stretches = false,
}: {
    index: number;
    count: number;
    activeColor?: string;
    stretches?: boolean;
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
                position: "relative",
            }}
        >
            {Array.from({ length: count }, (_, photoIndex) => {
                const isActive = !stretches && photoIndex == index;
                return (
                    <Box
                        key={photoIndex}
                        component="span"
                        sx={{
                            bgcolor: isActive ? activeColor : "#FFFFFF",
                            borderRadius: "50%",
                            boxShadow: "0 1px 2px rgba(0, 0, 0, 0.4)",
                            height: isActive ? 6 : 5,
                            width: isActive ? 6 : 5,
                        }}
                    />
                );
            })}
            {stretches && (
                <Box
                    component="span"
                    data-space-photo-dots-indicator
                    style={{
                        transform: `translate(${index * photoDotStep - 0.5}px, -50%)`,
                        width: 6,
                    }}
                    sx={{
                        bgcolor: activeColor,
                        borderRadius: "3px",
                        boxShadow: "0 1px 2px rgba(0, 0, 0, 0.4)",
                        height: 6,
                        left: 0,
                        position: "absolute",
                        top: "50%",
                    }}
                />
            )}
        </Box>
    ) : null;
