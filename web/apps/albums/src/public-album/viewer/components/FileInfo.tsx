import {
    ArrowLeft01Icon,
    Calendar04Icon,
    Camera01Icon,
    CameraLensIcon,
    Cancel01Icon,
    Image01Icon,
    Location01Icon,
    Video02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Divider, IconButton, Link, Stack, Typography } from "@mui/material";
import { LinkButtonUndecorated } from "ente-base/components/LinkButton";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { formattedDate, formattedTime } from "ente-base/i18n-date";
import type { Location } from "ente-base/types";
import {
    CopyButton,
    FileInfoHeader,
    FileInfoSection,
    FileInfoSidebar,
    InfoItem,
    RawExif,
} from "ente-gallery/components/FileInfoComponents";
import { tagNumericValue, type RawExifTags } from "ente-gallery/services/exif";
import { formattedByteSize } from "ente-gallery/utils/units";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationPhotoDate,
    fileFileName,
    fileLocation,
    type ParsedMetadata,
} from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { t } from "i18next";
import React, { useMemo } from "react";

export interface FileInfoExif {
    tags: RawExifTags | undefined;
    parsed: ParsedMetadata | undefined;
}

type FileInfoAnnotatedExif = Required<FileInfoExif> & {
    resolution?: string;
    megaPixels?: string;
    takenOnDevice?: string;
    fNumber?: string;
    exposureTime?: string;
    iso?: string;
};

export type FileInfoProps = ModalVisibilityProps & {
    file: EnteFile;
    exif: FileInfoExif | undefined;
};

export const FileInfo: React.FC<FileInfoProps> = ({
    open,
    onClose,
    file,
    exif,
}) => {
    const { show: showRawExif, props: rawExifVisibilityProps } =
        useModalVisibility();

    const caption =
        file.pubMagicMetadata?.data.caption ?? exif?.parsed?.description;
    const location = fileLocation(file) ?? exif?.parsed?.location;
    const uploaderName = file.pubMagicMetadata?.data.uploaderName;
    const annotatedExif = useMemo(() => annotateExif(exif), [exif]);

    return (
        <FileInfoSidebar {...{ open, onClose }}>
            <FileInfoHeader>
                <IconButton aria-label={t("go_back")} onClick={onClose}>
                    <HugeiconsIcon
                        icon={ArrowLeft01Icon}
                        size={20}
                        strokeWidth={1.8}
                    />
                </IconButton>
                <Typography
                    component="h2"
                    variant="h5"
                    sx={{ flex: 1, lineHeight: "28px" }}
                >
                    {t("details")}
                </Typography>
                <IconButton aria-label={t("close")} onClick={onClose}>
                    <HugeiconsIcon icon={Cancel01Icon} size={20} />
                </IconButton>
            </FileInfoHeader>
            <Stack sx={{ pb: 3, gap: 2 }}>
                {caption && (
                    <Typography
                        sx={{
                            p: "10px 12px",
                            color: "text.muted",
                            fontSize: 14,
                            lineHeight: "20px",
                            whiteSpace: "pre-wrap",
                            overflowWrap: "anywhere",
                        }}
                    >
                        {caption}
                    </Typography>
                )}
                <Stack sx={{ gap: "2px" }}>
                    <CreationTime file={file} />
                    <FileName file={file} annotatedExif={annotatedExif} />
                    {annotatedExif?.takenOnDevice && (
                        <InfoItem
                            icon={
                                <HugeiconsIcon icon={Camera01Icon} size={18} />
                            }
                            title={annotatedExif.takenOnDevice}
                            caption={createMultipartCaption(
                                annotatedExif.fNumber,
                                annotatedExif.exposureTime,
                                annotatedExif.iso,
                            )}
                        />
                    )}
                </Stack>
                {location && (
                    <FileInfoSection title={t("location")}>
                        <InfoItem
                            icon={
                                <HugeiconsIcon
                                    icon={Location01Icon}
                                    size={18}
                                />
                            }
                            captionVariant="small"
                            caption={
                                <Link
                                    href={openStreetMapLink(location)}
                                    target="_blank"
                                    rel="noopener"
                                    sx={{ fontWeight: "medium" }}
                                >
                                    {t("view_on_map")}
                                </Link>
                            }
                            trailingButton={
                                <CopyButton
                                    size="small"
                                    text={openStreetMapLink(location)}
                                />
                            }
                        />
                    </FileInfoSection>
                )}
                <Divider sx={{ borderColor: "stroke.faint" }} />
                <InfoItem
                    icon={<HugeiconsIcon icon={CameraLensIcon} size={18} />}
                    title={t("exif")}
                    caption={
                        !exif ? (
                            <ActivityIndicator size={12} />
                        ) : !exif.tags ? (
                            t("no_exif")
                        ) : (
                            <LinkButtonUndecorated onClick={showRawExif}>
                                {t("view_exif")}
                            </LinkButtonUndecorated>
                        )
                    }
                />
                {uploaderName && (
                    <Typography
                        variant="small"
                        sx={{
                            fontSize: 12,
                            lineHeight: "16px",
                            textAlign: "right",
                            color: "text.muted",
                            overflowWrap: "anywhere",
                        }}
                    >
                        {t("added_by_name", { name: uploaderName })}
                    </Typography>
                )}
            </Stack>
            <RawExif
                {...rawExifVisibilityProps}
                tags={exif?.tags}
                fileName={fileFileName(file)}
            />
        </FileInfoSidebar>
    );
};

const annotateExif = (
    fileInfoExif: FileInfoExif | undefined,
): FileInfoAnnotatedExif | undefined => {
    if (!fileInfoExif?.tags || !fileInfoExif.parsed) {
        return undefined;
    }

    const annotatedExif: FileInfoAnnotatedExif = { ...fileInfoExif };
    const { width, height } = fileInfoExif.parsed;
    if (width && height) {
        annotatedExif.resolution = `${width} x ${height}`;
        const megaPixels = Math.round((width * height) / 1_000_000);
        if (megaPixels) annotatedExif.megaPixels = `${megaPixels}MP`;
    }

    const { exif } = fileInfoExif.tags;
    if (!exif) return annotatedExif;

    if (exif.Make && exif.Model) {
        annotatedExif.takenOnDevice = `${exif.Make.description} ${exif.Model.description}`;
    }
    const fNumber = exif.FNumber;
    if (fNumber && fNumber.value[1] != 0) {
        annotatedExif.fNumber = fNumber.description;
    }
    if (exif.ExposureTime) {
        annotatedExif.exposureTime = exif.ExposureTime.description;
    }
    if (exif.ISOSpeedRatings) {
        annotatedExif.iso = `ISO${tagNumericValue(exif.ISOSpeedRatings)}`;
    }

    return annotatedExif;
};

const CreationTime: React.FC<{ file: EnteFile }> = ({ file }) => {
    const date = fileCreationPhotoDate(file);
    return (
        <InfoItem
            icon={<HugeiconsIcon icon={Calendar04Icon} size={18} />}
            title={formattedDate(date)}
            caption={formattedTime(date)}
        />
    );
};

const FileName: React.FC<{
    file: EnteFile;
    annotatedExif: FileInfoAnnotatedExif | undefined;
}> = ({ file, annotatedExif }) => {
    const icon =
        file.metadata.fileType === FileType.video ? (
            <HugeiconsIcon icon={Video02Icon} size={18} />
        ) : (
            <HugeiconsIcon icon={Image01Icon} size={18} />
        );
    const fileSize = file.info?.fileSize;

    return (
        <InfoItem
            icon={icon}
            title={fileFileName(file)}
            caption={createMultipartCaption(
                annotatedExif?.megaPixels,
                annotatedExif?.resolution,
                fileSize ? formattedByteSize(fileSize) : undefined,
            )}
        />
    );
};

const createMultipartCaption = (
    p1: string | undefined,
    p2: string | undefined,
    p3: string | undefined,
) => (
    <Stack direction="row" sx={{ gap: 1, flexWrap: "wrap" }}>
        {p1 && <div>{p1}</div>}
        {p2 && <div>{p2}</div>}
        {p3 && <div>{p3}</div>}
    </Stack>
);

const openStreetMapLink = ({ latitude, longitude }: Location) =>
    `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=15/${latitude}/${longitude}`;
