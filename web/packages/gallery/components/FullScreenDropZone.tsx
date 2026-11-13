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
    message?: string;
    disabled?: boolean;
    onDrop: (files: FileWithPath[]) => void;
}

export const FullScreenDropZone: React.FC<
    React.PropsWithChildren<FullScreenDropZoneProps>
> = ({ message, disabled, onDrop, children }) => {
    const { getRootProps, getInputProps } = useDropzone({
        noClick: true,
        noKeyboard: true,
        disabled,
        onDrop(acceptedFiles) {
            setIsDropPending(false);
            if (acceptedFiles.length) {
                onDrop([...acceptedFiles]);
            }
        },
    });

    const [isDragActive, setIsDragActive] = useState(false);
    const [isDropPending, setIsDropPending] = useState(false);

    const handleDragEnter = useCallback(
        (event: React.DragEvent<HTMLElement>) => {
            if (disabled || !hasDraggedFiles(event.dataTransfer)) return;
            setIsDragActive(true);
        },
        [disabled],
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
                sx={{ flex: 1, minHeight: 0 }}
                {...getRootProps({ onDragEnter: handleDragEnter })}
            >
                {!disabled && (isDragActive || isDropPending) && (
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
    z-index: calc(var(--mui-zIndex-tooltip) + 1);
`,
);

const CloseButton = styled(IconButton)`
    position: absolute;
    top: 10px;
    right: 10px;
`;
