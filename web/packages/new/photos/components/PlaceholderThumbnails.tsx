import PhotoOutlinedIcon from "@mui/icons-material/PhotoOutlined";
import PlayCircleOutlineOutlinedIcon from "@mui/icons-material/PlayCircleOutlineOutlined";
import { styled } from "@mui/material";
import { Overlay } from "ente-base/components/containers";
import { FileType } from "ente-media/file-type";
import React from "react";

export const LoadingThumbnail = () => (
    <Overlay sx={{ backgroundColor: "fill.faint", borderRadius: "4px" }} />
);

interface StaticThumbnailProps {
    fileType: number;
}

export const StaticThumbnail: React.FC<StaticThumbnailProps> = ({
    fileType,
}) => (
    <CenteredOverlay
        sx={{
            backgroundColor: "fill.faint",
            borderWidth: "1px",
            borderStyle: "solid",
            borderColor: "stroke.faint",
            borderRadius: "4px",
            "& > svg": { color: "stroke.muted", fontSize: "50px" },
        }}
    >
        {fileType != FileType.video ? (
            <PhotoOutlinedIcon />
        ) : (
            <PlayCircleOutlineOutlinedIcon />
        )}
    </CenteredOverlay>
);

const CenteredOverlay = styled(Overlay)`
    display: flex;
    justify-content: center;
    align-items: center;
`;
