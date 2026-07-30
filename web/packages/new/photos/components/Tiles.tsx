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
    /**
     * One of the *Tile components to use as the top level element.
     */
    TileComponent: React.FC<React.PropsWithChildren>;
    /**
     * Optional file whose thumbnail (if any) should be should be shown.
     */
    coverFile?: EnteFile | undefined;
    /**
     * Optional ID of a specific face within {@link coverFile} to show.
     *
     * Precondition: {@link faceID} must be an ID of a face that belongs to the
     * given {@link coverFile}.
     */
    coverFaceID?: string | undefined;
    /**
     * Optional boolean indicating if the user is currently scrolling.
     *
     * This is used as a hint by the file downloader to prioritize downloads.
     */
    isScrolling?: boolean;
    /**
     * Optional click handler.
     */
    onClick?: () => void;
}

/**
 * A generic card that can be be used to represent collections, files, people -
 * anything that (usually) has an associated "cover photo".
 *
 * Usually, we provide it a {@link coverFile} prop to set the file whose
 * thumbnail should be shown in the card. However, an additional
 * {@link coverFaceID} prop can be used to show the face crop for that specific
 * face within the cover file.
 *
 * Note that while the common use case is to use this with a cover photo (and an
 * additional cover faceID), both of these are optional and the item card can
 * also be used as a static component without an associated cover image by
 * covering it with an opaque overlay.
 */
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

/**
 * A generic "base" tile, meant to be used (after setting dimensions) as the
 * {@link TileComponent} provided to an {@link ItemCard}.
 *
 * Use {@link Overlay} (usually via one of its presets) to overlay content on
 * top of the tile.
 */
const BaseTile = styled("div")`
    display: flex;
    /* Act as container for the absolutely positioned 'Overlay's. */
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

/**
 * A 48x48 TileComponent used in search result dropdown's preview files and
 * other places.
 */
export const PreviewItemTile = styled(BaseTile)`
    width: 48px;
    height: 48px;
`;

/**
 * A rectangular, TV-ish tile used in the gallery bar.
 */
export const BarItemTile = styled(BaseTile)`
    width: 90px;
    height: 64px;
    color: white;
`;

/**
 * A square tile used on the duplicates listing.
 */
export const DuplicateItemTile = styled(BaseTile)`
    /* The thumbnails are not interactable, reset the pointer */
    cursor: initial;
`;

/**
 * A variant of {@link BaseTile} meant for use when the tile is interactable.
 */
export const BaseTileButton = styled(UnstyledButton)`
    /* Buttons reset this to the special token buttontext */
    color: inherit;
    /* Buttons reset this to center */
    text-align: inherit;

    /* Rest of this is mostly verbatim from BaseTile ... */

    display: flex;
    /* Act as container for the absolutely positioned 'Overlay's. */
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

/**
 * A large 150x150 TileComponent used when, for example, when showing the list
 * of collections in the all collections view and in the collection selector.
 */
export const LargeTileButton = styled(BaseTileButton)`
    width: 150px;
    height: 150px;
`;

/**
 * An {@link Overlay} suitable for hosting textual content at the top left of
 * small and medium sized tiles.
 */
export const TileTextOverlay = styled(Overlay)`
    padding: 4px;
    background: linear-gradient(
        0deg,
        rgba(0, 0, 0, 0.1) 0%,
        rgba(0, 0, 0, 0.5) 86.46%
    );
`;

/**
 * A variation of {@link TileTextOverlay} for use with larger tiles like the
 * {@link CollectionTile}.
 */
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

/**
 * A {@link LargeTileButton} suitable for use as the trigger for creating a new
 * entry (e.g. creating new album, or a new person).
 *
 * It is styled to go well with other {@link LargeTileButton}s that display
 * existing entries, except this one can allow the user to create a new item.
 *
 * The child is expected to be a text, it'll be wrapped in a {@link Typography}
 * and shown at the top left of the button.
 */
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

/**
 * An {@link Overlay} suitable for showing text at the bottom center of the
 * tile. Used by the tiles in trash (for showing the days until deletion) and
 * duplicate listing (for showing the collection name).
 */
export const TileBottomTextOverlay = styled(Overlay)`
    display: flex;
    justify-content: center;
    align-items: flex-end;
    padding: 6px;
    background: linear-gradient(transparent 30%, 80%, rgba(0 0 0 / 0.7));
    color: white;
`;

/**
 * An {@link Overlay} for use with large file tiles, providing a container
 * for selection indicators and file size labels.
 */
export const LargeFileTileOverlay = styled(Overlay)`
    display: flex;
    pointer-events: none;
`;
