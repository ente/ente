import AddIcon from "@mui/icons-material/Add";
import { Stack, styled, Typography } from "@mui/material";
import { CenteredFill, Overlay } from "ente-base/components/containers";
import type { ButtonishProps } from "ente-base/components/mui";
import log from "ente-base/log";
import { downloadManager } from "ente-gallery/services/download";
import type { EnteFile } from "ente-media/file";
import {
    LoadingThumbnail,
    StaticThumbnail,
} from "ente-new/photos/components/PlaceholderThumbnails";
import React, { useEffect, useState } from "react";
import { faceCrop } from "../services/ml";
import { UnstyledButton } from "./UnstyledButton";

interface ItemCardProps {
    TileComponent: React.FC<React.PropsWithChildren>;
    coverFile?: EnteFile | undefined;
    // This face must belong to coverFile.
    coverFaceID?: string | undefined;
    // The downloader uses this to adjust thumbnail priority.
    isScrolling?: boolean;
    onClick?: () => void;
}

export const ItemCard: React.FC<React.PropsWithChildren<ItemCardProps>> = ({
    TileComponent,
    coverFile,
    coverFaceID,
    isScrolling,
    onClick,
    children,
}) => {
    const [coverImageURL, setCoverImageURL] = useState<string | undefined>();

    useEffect(() => {
        if (!coverFile) return undefined;

        let didCancel = false;

        if (coverFaceID) {
            void faceCrop(coverFaceID, coverFile).then(
                (url) => !didCancel && setCoverImageURL(url),
            );
        } else {
            void downloadManager
                .renderableThumbnailURL(coverFile, isScrolling)
                .then((url) => !didCancel && setCoverImageURL(url))
                .catch((e: unknown) => {
                    log.warn("Failed to fetch thumbnail", e);
                });
        }

        return () => {
            didCancel = true;
        };
    }, [coverFile, coverFaceID, isScrolling]);

    return (
        <TileComponent {...{ onClick }}>
            {coverFile?.metadata.hasStaticThumbnail ? (
                <StaticThumbnail fileType={coverFile.metadata.fileType} />
            ) : coverImageURL ? (
                <img src={coverImageURL} />
            ) : (
                <LoadingThumbnail />
            )}
            {children}
        </TileComponent>
    );
};

const BaseTile = styled("div")`
    display: flex;
    position: relative;
    border-radius: 4px;
    overflow: hidden;
    cursor: pointer;
    & > img {
        object-fit: cover;
        width: 100%;
        height: 100%;
        pointer-events: none;
    }
    user-select: none;
`;

export const PreviewItemTile = styled(BaseTile)`
    width: 48px;
    height: 48px;
`;

export const DuplicateItemTile = styled(BaseTile)`
    cursor: initial;
`;

export const BaseTileButton = styled(UnstyledButton)`
    color: inherit;
    text-align: inherit;

    display: flex;
    position: relative;
    border-radius: 4px;
    overflow: hidden;
    & > img {
        object-fit: cover;
        width: 100%;
        height: 100%;
        pointer-events: none;
    }
`;

export const LargeTileButton = styled(BaseTileButton)`
    width: 150px;
    height: 150px;
`;

export const LargeTileTextOverlay = styled(Overlay)`
    padding: 8px;
    color: white;
    background: linear-gradient(
        -10deg,
        rgba(0, 0, 0, 0.1) 0%,
        rgba(0, 0, 0, 0.2) 50%,
        rgba(0, 0, 0, 0.4) 60%,
        rgba(0, 0, 0, 0.6) 100%
    );
`;

export const LargeTileCreateNewButton: React.FC<
    React.PropsWithChildren<ButtonishProps>
> = ({ onClick, children }) => (
    <LargeTileButton onClick={onClick}>
        <Stack
            sx={{
                flex: 1,
                height: "100%",
                border: "1px dashed",
                borderColor: "stroke.muted",
                borderRadius: "4px",
                padding: 1,
            }}
        >
            <Typography>{children}</Typography>
            <CenteredFill>
                <AddIcon />
            </CenteredFill>
        </Stack>
    </LargeTileButton>
);

export const TileBottomTextOverlay = styled(Overlay)`
    display: flex;
    justify-content: center;
    align-items: flex-end;
    padding: 6px;
    background: linear-gradient(transparent 30%, 80%, rgba(0 0 0 / 0.7));
    color: white;
`;

export const LargeFileTileOverlay = styled(Overlay)`
    display: flex;
    pointer-events: none;
`;
