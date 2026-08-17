import {
    Box,
    Stack,
    styled,
    Typography,
    type TypographyProps,
} from "@mui/material";
import { isSxArray } from "ente-base/components/utils/sx";
import { t } from "i18next";
import React, { useEffect, useRef, useState } from "react";

interface GalleryItemsSummaryProps {
    name: string;
    description?: string;
    descriptionMaxWidth?: number;
    nameProps?: TypographyProps;
    fileCount: number;
    endIcon?: React.ReactNode;
    // This cannot be the only way to invoke the action; it is mouse-only.
    onNameClick?: () => void;
    onDescriptionHeightChange?: (height: number) => void;
}

export const GalleryItemsSummary: React.FC<GalleryItemsSummaryProps> = ({
    name,
    description,
    descriptionMaxWidth,
    nameProps,
    fileCount,
    endIcon,
    onNameClick,
    onDescriptionHeightChange,
}) => (
    <Box sx={{ minWidth: 0 }}>
        <Typography variant="h3" {...(nameProps ?? {})} onClick={onNameClick}>
            {name}
        </Typography>

        <Stack
            direction="row"
            sx={{
                gap: 1.5,
                // Keep the header height stable without an end icon.
                minHeight: "24px",
            }}
        >
            <Typography variant="small" sx={{ color: "text.muted" }}>
                {t("photos_count", { count: fileCount })}
            </Typography>
            {endIcon && (
                <Box sx={{ svg: { fontSize: "17px", color: "text.muted" } }}>
                    {endIcon}
                </Box>
            )}
        </Stack>

        <AlbumDescription
            description={description}
            sx={{
                pt: "4px",
                maxWidth: descriptionMaxWidth ?? 420,
                color: "text.faint",
            }}
            onHeightChange={onDescriptionHeightChange}
        />
    </Box>
);

interface AlbumDescriptionProps {
    description?: string;
    sx?: TypographyProps["sx"];
    onHeightChange?: (height: number) => void;
}

export const AlbumDescription: React.FC<AlbumDescriptionProps> = ({
    description,
    sx,
    onHeightChange,
}) => {
    const [expandedDescription, setExpandedDescription] = useState<string>();
    const expanded = expandedDescription === description;
    const textRef = useRef<HTMLButtonElement>(null);

    useEffect(() => {
        if (!onHeightChange) return;

        const text = textRef.current;
        if (!text) {
            onHeightChange(0);
            return;
        }

        const report = () => onHeightChange(text.offsetHeight);
        report();
        const observer = new ResizeObserver(report);
        observer.observe(text);
        return () => observer.disconnect();
    }, [description, onHeightChange]);

    if (!description) return null;

    const handleClick = () =>
        setExpandedDescription(expanded ? undefined : description);

    return (
        <Typography
            component="button"
            type="button"
            variant="small"
            ref={textRef}
            aria-expanded={expanded}
            onClick={handleClick}
            sx={[
                {
                    display: "-webkit-box",
                    overflow: "hidden",
                    WebkitBoxOrient: "vertical",
                    WebkitLineClamp: expanded ? "unset" : 1,
                    overflowWrap: "anywhere",
                    textWrap: "pretty",
                    width: "100%",
                    border: 0,
                    p: 0,
                    background: "none",
                    color: "inherit",
                    textAlign: "left",
                    cursor: "pointer",
                },
                ...(sx ? (isSxArray(sx) ? sx : [sx]) : []),
            ]}
        >
            {description}
        </Typography>
    );
};

export const GalleryItemsHeaderAdapter = styled("div")`
    width: 100%;
    margin-bottom: 12px;
`;
