import { Album02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";

export const SpacePostPhotosBadge = ({
    count,
    inset = 10,
}: {
    count: number;
    inset?: number;
}) =>
    count > 1 ? (
        <Box
            component="span"
            aria-label={`${count} photos`}
            sx={{
                alignItems: "center",
                color: "#FFFFFF",
                display: "flex",
                filter: "drop-shadow(0 1px 2px rgba(0, 0, 0, 0.5))",
                height: 30,
                justifyContent: "center",
                opacity: 0.8,
                pointerEvents: "none",
                position: "absolute",
                right: inset,
                top: inset,
                width: 30,
                zIndex: 2,
            }}
        >
            <HugeiconsIcon icon={Album02Icon} size={18} strokeWidth={1.6} />
        </Box>
    ) : null;
