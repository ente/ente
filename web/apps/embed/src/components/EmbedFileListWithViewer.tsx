import { Box, styled, Typography } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { SpacedRow } from "ente-base/components/containers";
import { isSameDay } from "ente-base/date";
import { formattedDate } from "ente-base/i18n-date";
import { FileViewer } from "ente-gallery/components/viewer/FileViewer";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoDate } from "ente-media/file-metadata";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import { t } from "i18next";
import { useCallback, useMemo, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    EmbedFileList,
    type EmbedFileListAnnotatedFile,
} from "./EmbedFileList";

export interface EmbedFileListWithViewerProps {
    files: EnteFile[];
    publicCollection: Collection;
    onRemotePull?: () => Promise<void>;
}

export const EmbedFileListWithViewer: React.FC<
    EmbedFileListWithViewerProps
> = ({ files, publicCollection, onRemotePull }) => {
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentIndex, setCurrentIndex] = useState(0);

    const annotatedFiles = useMemo(
        (): EmbedFileListAnnotatedFile[] =>
            files.map((file) => ({
                file,
                timelineDateString: fileTimelineDateString(file),
            })),
        [files],
    );

    const handleThumbnailClick = useCallback(
        (index: number) => {
            setCurrentIndex(index);
            setOpenFileViewer(true);
        },
        // eslint-disable-next-line react-hooks/exhaustive-deps
        [files.length],
    );

    const handleCloseFileViewer = useCallback(() => {
        setOpenFileViewer(false);
    }, []);

    const handleTriggerRemotePull = useCallback(
        () => void onRemotePull?.(),
        [onRemotePull],
    );

    const header = useMemo(
        () => (
            <GalleryItemsHeaderAdapter
                sx={{ boxSizing: "border-box", p: "12px", pb: "4px", mb: 0 }}
            >
                <SpacedRow>
                    <GalleryItemsSummary
                        name={publicCollection.name}
                        fileCount={files.length}
                    />
                    <Typography
                        variant="small"
                        sx={{
                            color: "text.muted",
                            display: "flex",
                            flexDirection: "column",
                            alignItems: "flex-end",
                            marginRight: "4px",
                            fontSize: "0.8em",
                        }}
                    >
                        <span style={{ whiteSpace: "nowrap" }}>powered by</span>
                        <Box
                            component="a"
                            href="https://ente.com"
                            target="_blank"
                            rel="noopener"
                            sx={{
                                transition: "color 0.2s ease",
                                color: "inherit",
                                textDecoration: "none",
                                "&:visited": { color: "inherit" },
                                "&:hover": { color: "#1db954" },
                            }}
                        >
                            <EnteLogo height={14} />
                        </Box>
                    </Typography>
                </SpacedRow>
            </GalleryItemsHeaderAdapter>
        ),
        [publicCollection.name, files.length],
    );

    return (
        <Container>
            {header}
            <ListArea>
                <AutoSizer>
                    {({ height, width }) => (
                        <EmbedFileList
                            width={width}
                            height={height}
                            annotatedFiles={annotatedFiles}
                            onItemClick={handleThumbnailClick}
                        />
                    )}
                </AutoSizer>
            </ListArea>
            {openFileViewer && (
                <FileViewer
                    open={openFileViewer}
                    onClose={handleCloseFileViewer}
                    initialIndex={currentIndex}
                    files={files}
                    disableDownload={true}
                    showFullscreenButton={true}
                    enableComment={false}
                    onTriggerRemotePull={handleTriggerRemotePull}
                    onVisualFeedback={() => {
                        // Visual feedback requested
                    }}
                />
            )}
        </Container>
    );
};

const Container = styled("div")({
    display: "flex",
    flex: 1,
    flexDirection: "column",
    minHeight: 0,
    width: "100%",
});

const ListArea = styled("div")({ flex: 1, minHeight: 0 });

const fileTimelineDateString = (file: EnteFile) => {
    const date = fileCreationPhotoDate(file);
    return isSameDay(date, new Date())
        ? t("today")
        : isSameDay(date, new Date(Date.now() - 24 * 60 * 60 * 1000))
          ? t("yesterday")
          : formattedDate(date);
};
