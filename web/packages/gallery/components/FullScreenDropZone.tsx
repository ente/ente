import CloseIcon from "@mui/icons-material/Close";
import { IconButton, Stack, styled, Typography } from "@mui/material";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { t } from "i18next";
import React, { useCallback, useEffect, useState } from "react";
import { type FileWithPath, useDropzone } from "react-dropzone";

const hasDraggedFiles = (
    dataTransfer: DataTransfer | null | undefined,
): boolean => {
    if (!dataTransfer) return false;

    for (const item of Array.from(dataTransfer.items)) {
        if (item.kind == "file") return true;
    }

    for (const type of Array.from(dataTransfer.types)) {
        if (type == "Files") return true;
    }

    return false;
};

export interface FullScreenDropZoneProps {
    /**
     * Optional override to the message show to the user when a drag is in
     * progress.
     *
     * Default: t("upload_dropzone_hint")
     */
    message?: string;
    /**
     * If `true`, then drag and drop functionality is disabled.
     */
    disabled?: boolean;
    /**
     * Callback invoked when the user drags and drops files.
     *
     * It will only be called if there is at least one file in {@link files}.
     */
    onDrop: (files: FileWithPath[]) => void;
}

/**
 * A full screen container that accepts drag and drop of files, and also shows a
 * visual overlay to the user while a drag is in progress.
 *
 * It can serves as the root component of the gallery pages as the container
 * itself is a stack with flex 1, and so will fill all the height (and width)
 * available to it. The other contents of the screen can then be placed as its
 * children.
 *
 * It is meant to be used in tandem with "react-dropzone"; specifically, it
 * requires the `getRootProps` function returned by a call to
 * {@link useDropzone}.
 */
export const FullScreenDropZone: React.FC<
    React.PropsWithChildren<FullScreenDropZoneProps>
> = ({ message, disabled, onDrop, children }) => {
    const {
        // A function to call to get the props we should apply to the container,
        getRootProps,
        // ... the props we should apply to the <input> element,
        getInputProps,
    } = useDropzone({
        noClick: true,
        noKeyboard: true,
        disabled,
        onDrop(acceptedFiles) {
            setIsDropPending(false);
            // Invoked the `onDrop` callback only if there is at least 1 file.
            if (acceptedFiles.length) {
                // Create a regular array from the readonly array returned by
                // dropzone.
                onDrop([...acceptedFiles]);
            }
        },
    });

    const [isDragActive, setIsDragActive] = useState(false);
    const [isDropPending, setIsDropPending] = useState(false);

    const handleDragEnter = useCallback(
        (event: React.DragEvent<HTMLElement>) => {
            if (!hasDraggedFiles(event.dataTransfer)) return;
            setIsDragActive(true);
        },
        [],
    );

    const handleOverlayDrop = useCallback(
        (event: React.DragEvent<HTMLElement>) => {
            if (!hasDraggedFiles(event.dataTransfer)) {
                setIsDropPending(false);
                setIsDragActive(false);
                return;
            }
            setIsDropPending(true);
            setIsDragActive(false);
        },
        [],
    );

    const handleDragLeave = useCallback(() => {
        setIsDragActive(false);
    }, []);

    useEffect(() => {
        const handleKeydown = (event: KeyboardEvent) => {
            if (event.code == "Escape" && !isDropPending) handleDragLeave();
        };

        window.addEventListener("keydown", handleKeydown);
        return () => window.removeEventListener("keydown", handleKeydown);
    }, [isDropPending, handleDragLeave]);

    return (
        <>
            <input {...getInputProps()} />
            <Stack
                sx={{ flex: 1 }}
                {...getRootProps({ onDragEnter: handleDragEnter })}
            >
                {(isDragActive || isDropPending) && (
                    <DropZoneOverlay
                        onDrop={handleOverlayDrop}
                        onDragLeave={handleDragLeave}
                    >
                        <CloseButton
                            disabled={isDropPending}
                            onClick={handleDragLeave}
                        >
                            <CloseIcon />
                        </CloseButton>
                        <Typography variant="h3">
                            {isDropPending ? (
                                <ActivityIndicator />
                            ) : (
                                (message ?? t("upload_dropzone_hint"))
                            )}
                        </Typography>
                    </DropZoneOverlay>
                )}
                {children}
            </Stack>
        </>
    );
};

const DropZoneOverlay = styled(Stack)(
    ({ theme }) => `
    position: absolute;
    left: 0;
    top: 0;
    height: 100%;
    width: 100%;
    outline: none;
    justify-content: center;
    align-items: center;
    transition: border 0.24s ease-in-out;
    border-width: 5px;
    border-style: solid;
    border-color: ${theme.vars.palette.accent.light};
    background-color: ${theme.vars.palette.backdrop.base};
    backdrop-filter: blur(10px);
    /* Above the highest possible MUI z-index, that of the MUI tooltip
       See: https://mui.com/material-ui/customization/default-theme/ */
    z-index: calc(var(--mui-zIndex-tooltip) + 1);
`,
);

const CloseButton = styled(IconButton)`
    position: absolute;
    top: 10px;
    right: 10px;
`;
