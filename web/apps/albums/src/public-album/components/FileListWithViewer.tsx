import type {
    FileViewerInitialSidebar,
    FileViewerProps,
} from "@/public-album/viewer/components/FileViewer";
import {
    LazyFileViewer,
    scheduleFileViewerPreload,
} from "@/public-album/viewer/lib/lazy";
import { styled } from "@mui/material";
import { isSameDay } from "ente-base/date";
import { formattedDate } from "ente-base/i18n-date";
import type { AddSaveGroup } from "ente-gallery/components/utils/save-groups";
import type { EnteFile } from "ente-media/file";
import { fileCreationPhotoDate, fileFileName } from "ente-media/file-metadata";
import { t } from "i18next";
import { useCallback, useEffect, useMemo, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    FileList,
    type FileListAnnotatedFile,
    type FileListProps,
} from "./FileList";

export type FileListWithViewerProps = {
    files: EnteFile[];
    enableDownload?: boolean;
    pendingFileIndex?: number;
    pendingFileSidebar?: FileViewerInitialSidebar;
    pendingHighlightCommentID?: string;
    pendingAnonUserNames?: Map<string, string>;
    onPendingNavigationConsumed?: () => void;
    onAddSaveGroup: AddSaveGroup;
} & Pick<
    FileListProps,
    | "layout"
    | "disableGrouping"
    | "header"
    | "footer"
    | "enableSelect"
    | "selected"
    | "setSelected"
    | "activeCollectionID"
    | "emptyStateAction"
> &
    Pick<
        FileViewerProps,
        | "publicAlbumsCredentials"
        | "collectionKey"
        | "onJoinAlbum"
        | "enableComment"
        | "enableJoin"
    >;

export const FileListWithViewer: React.FC<FileListWithViewerProps> = ({
    layout,
    disableGrouping,
    header,
    footer,
    files,
    enableDownload,
    enableSelect,
    selected,
    setSelected,
    activeCollectionID,
    emptyStateAction,
    onAddSaveGroup,
    pendingFileIndex,
    pendingFileSidebar,
    pendingHighlightCommentID,
    pendingAnonUserNames,
    onPendingNavigationConsumed,
    publicAlbumsCredentials,
    collectionKey,
    onJoinAlbum,
    enableComment,
    enableJoin,
}) => {
    const [openFileViewer, setOpenFileViewer] = useState(false);
    const [currentIndex, setCurrentIndex] = useState(0);
    const [initialSidebar, setInitialSidebar] = useState<
        FileViewerInitialSidebar | undefined
    >(undefined);
    const [highlightCommentID, setHighlightCommentID] = useState<
        string | undefined
    >(undefined);
    const [initialAnonUserNames, setInitialAnonUserNames] = useState<
        Map<string, string> | undefined
    >(undefined);

    useEffect(() => {
        if (pendingFileIndex !== undefined) {
            setCurrentIndex(pendingFileIndex);
            setInitialSidebar(pendingFileSidebar);
            setHighlightCommentID(pendingHighlightCommentID);
            setInitialAnonUserNames(
                pendingAnonUserNames
                    ? new Map(pendingAnonUserNames)
                    : undefined,
            );
            setOpenFileViewer(true);
            onPendingNavigationConsumed?.();
        }
    }, [
        pendingFileIndex,
        pendingFileSidebar,
        pendingHighlightCommentID,
        pendingAnonUserNames,
        onPendingNavigationConsumed,
    ]);

    const handleCloseFileViewerInternal = useCallback(() => {
        setInitialSidebar(undefined);
        setHighlightCommentID(undefined);
        setInitialAnonUserNames(undefined);
        setOpenFileViewer(false);
    }, []);

    useEffect(() => {
        if (files.length === 0) return;
        return scheduleFileViewerPreload();
    }, [files.length]);

    const annotatedFiles = useMemo(
        (): FileListAnnotatedFile[] =>
            files.map((file) => ({
                file,
                timelineDateString: fileTimelineDateString(file),
            })),
        [files],
    );

    const handleThumbnailClick = useCallback((index: number) => {
        setCurrentIndex(index);
        setOpenFileViewer(true);
    }, []);

    const handleDownload = useCallback(
        async (file: EnteFile) => {
            const { downloadAndSaveFiles } =
                await import("@/public-album/download/services/save");
            return downloadAndSaveFiles(
                [file],
                fileFileName(file),
                onAddSaveGroup,
            );
        },
        [onAddSaveGroup],
    );

    const shouldRenderFileViewer =
        openFileViewer || pendingFileIndex !== undefined;

    return (
        <Container>
            <AutoSizer>
                {({ height, width }) => (
                    <FileList
                        {...{ width, height, annotatedFiles }}
                        {...{
                            layout,
                            disableGrouping,
                            header,
                            footer,
                            enableSelect,
                            selected,
                            setSelected,
                            activeCollectionID,
                            emptyStateAction,
                        }}
                        onItemClick={handleThumbnailClick}
                    />
                )}
            </AutoSizer>
            {shouldRenderFileViewer && (
                <LazyFileViewer
                    open={openFileViewer}
                    onClose={handleCloseFileViewerInternal}
                    initialIndex={currentIndex}
                    initialSidebar={initialSidebar}
                    highlightCommentID={highlightCommentID}
                    initialAnonUserNames={initialAnonUserNames}
                    disableDownload={!enableDownload}
                    {...{
                        files,
                        publicAlbumsCredentials,
                        collectionKey,
                        onJoinAlbum,
                        enableComment,
                        enableJoin,
                    }}
                    onDownload={handleDownload}
                    activeCollectionID={activeCollectionID}
                />
            )}
        </Container>
    );
};

const Container = styled("div")`
    flex: 1;
    width: 100%;
`;

const fileTimelineDateString = (file: EnteFile) => {
    const date = fileCreationPhotoDate(file);
    return isSameDay(date, new Date())
        ? t("today")
        : isSameDay(date, new Date(Date.now() - 24 * 60 * 60 * 1000))
          ? t("yesterday")
          : formattedDate(date);
};
