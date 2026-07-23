import CalendarTodayIcon from "@mui/icons-material/CalendarToday";
import CameraOutlinedIcon from "@mui/icons-material/CameraOutlined";
import LocationOnOutlinedIcon from "@mui/icons-material/LocationOnOutlined";
import PhotoOutlinedIcon from "@mui/icons-material/PhotoOutlined";
import TextSnippetOutlinedIcon from "@mui/icons-material/TextSnippetOutlined";
import VideocamOutlinedIcon from "@mui/icons-material/VideocamOutlined";
import {
    Box,
    Link,
    Stack,
    styled,
    Typography,
    type DialogProps,
} from "@mui/material";
import { LinkButtonUndecorated } from "ente-base/components/LinkButton";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import {
    SidebarDrawer,
    SidebarDrawerTitlebar,
} from "ente-base/components/mui/SidebarDrawer";
import { EllipsizedTypography } from "ente-base/components/Typography";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { formattedDate, formattedTime } from "ente-base/i18n-date";
import type { Location } from "ente-base/types";
import { CopyButton } from "ente-gallery/components/FileInfoComponents";
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
            <SidebarDrawerTitlebar
                onClose={onClose}
                onRootClose={onClose}
                title={t("info")}
            />
            <Stack sx={{ pt: 1, pb: 3, gap: "20px" }}>
                {caption ? (
                    <Box sx={{ px: 1 }}>
                        <Typography
                            sx={{
                                whiteSpace: "pre-wrap",
                                wordBreak: "break-word",
                            }}
                        >
                            {caption}
                        </Typography>
                    </Box>
                ) : (
                    <Box sx={{ minHeight: 2 }} />
                )}
                <CreationTime file={file} />
                <FileName file={file} annotatedExif={annotatedExif} />
                {annotatedExif?.takenOnDevice && (
                    <InfoItem
                        icon={<CameraOutlinedIcon />}
                        title={annotatedExif.takenOnDevice}
                        caption={createMultipartCaption(
                            annotatedExif.fNumber,
                            annotatedExif.exposureTime,
                            annotatedExif.iso,
                        )}
                    />
                )}
                {location && (
                    <InfoItem
                        icon={<LocationOnOutlinedIcon />}
                        title={t("location")}
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
                                size="medium"
                                text={openStreetMapLink(location)}
                            />
                        }
                    />
                )}
                <InfoItem
                    icon={<TextSnippetOutlinedIcon />}
                    title={t("details")}
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
                        sx={{ m: 2, textAlign: "right", color: "text.muted" }}
                    >
                        {t("added_by_name", { name: uploaderName })}
                    </Typography>
                )}
            </Stack>
            <RawExif
                {...rawExifVisibilityProps}
                onInfoClose={onClose}
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
    if (exif.FNumber) annotatedExif.fNumber = exif.FNumber.description;
    if (exif.ExposureTime) {
        annotatedExif.exposureTime = exif.ExposureTime.description;
    }
    if (exif.ISOSpeedRatings) {
        annotatedExif.iso = `ISO${tagNumericValue(exif.ISOSpeedRatings)}`;
    }

    return annotatedExif;
};

const FileInfoSidebar = styled(
    (props: Pick<DialogProps, "open" | "onClose" | "children">) => (
        <SidebarDrawer
            {...props}
            anchor="right"
            disableRestoreFocus={true}
            closeAfterTransition={true}
        />
    ),
)(({ theme }) => ({
    "& .MuiDrawer-paper": { overflowX: "hidden" },
    ...theme.applyStyles("light", {
        ".MuiBackdrop-root": {
            backgroundColor: theme.vars.palette.backdrop.faint,
        },
    }),
}));

interface InfoItemProps {
    icon: React.ReactNode;
    title?: string;
    caption?: React.ReactNode;
    trailingButton?: React.ReactNode;
}

const InfoItem: React.FC<React.PropsWithChildren<InfoItemProps>> = ({
    icon,
    title,
    caption,
    trailingButton,
    children,
}) => (
    <Stack
        direction="row"
        sx={{ alignItems: "flex-start", flex: 1, gap: "12px" }}
    >
        <InfoItemIconContainer>{icon}</InfoItemIconContainer>
        {children ? (
            <Box sx={{ flex: 1, mt: "4px" }}>{children}</Box>
        ) : (
            <Stack sx={{ flex: 1, mt: "4px", gap: "4px" }}>
                <Typography sx={{ wordBreak: "break-all" }}>{title}</Typography>
                <Typography
                    variant="small"
                    {...(typeof caption != "string" && { component: "div" })}
                    sx={{ color: "text.muted" }}
                >
                    {caption}
                </Typography>
            </Stack>
        )}
        {trailingButton}
    </Stack>
);

const InfoItemIconContainer = styled("div")(
    ({ theme }) => `
    width: 48px;
    aspect-ratio: 1;
    display: flex;
    justify-content: center;
    align-items: center;
    color: ${theme.vars.palette.stroke.muted}
`,
);

const CreationTime: React.FC<{ file: EnteFile }> = ({ file }) => {
    const date = fileCreationPhotoDate(file);
    return (
        <InfoItem
            icon={<CalendarTodayIcon />}
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
            <VideocamOutlinedIcon />
        ) : (
            <PhotoOutlinedIcon />
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

interface RawExifProps {
    open: boolean;
    onClose: () => void;
    onInfoClose: () => void;
    tags: RawExifTags | undefined;
    fileName: string;
}

const RawExif: React.FC<RawExifProps> = ({
    open,
    onClose,
    onInfoClose,
    tags,
    fileName,
}) => {
    if (!tags) return <></>;

    const handleRootClose = () => {
        onClose();
        onInfoClose();
    };

    const items: (readonly [string, string, string, string])[] = Object.entries(
        tags,
    )
        .map(([namespace, namespaceTags]) =>
            Object.entries(namespaceTags).map(([tagName, tag]) => {
                const key = `${namespace}:${tagName}`;
                let description = "<...>";
                if (typeof tag == "string") {
                    description = tag;
                } else if (typeof tag == "number") {
                    description = `${tag}`;
                } else if (tag && typeof tag == "object") {
                    const descriptionField = (tag as Record<string, unknown>)
                        .description;
                    if (typeof descriptionField == "string") {
                        description = descriptionField;
                    }
                }

                return [key, namespace, tagName, description] as const;
            }),
        )
        .flat()
        .filter(([, , , description]) => description);

    return (
        <FileInfoSidebar open={open} onClose={onClose}>
            <SidebarDrawerTitlebar
                onClose={onClose}
                onRootClose={handleRootClose}
                title={t("exif")}
                caption={fileName}
                showRootCloseButton={false}
                actionButton={
                    <CopyButton size="small" text={JSON.stringify(tags)} />
                }
            />
            <Stack sx={{ gap: 2, py: 3, px: 1 }}>
                {items.map(([key, namespace, tagName, description]) => (
                    <ExifItem key={key}>
                        <Stack direction="row" sx={{ gap: 1 }}>
                            <Typography
                                variant="small"
                                sx={{ color: "text.muted" }}
                            >
                                {tagName}
                            </Typography>
                            <Typography
                                variant="tiny"
                                sx={{ color: "text.faint" }}
                            >
                                {namespace}
                            </Typography>
                        </Stack>
                        <EllipsizedTypography sx={{ width: "100%" }}>
                            {description}
                        </EllipsizedTypography>
                    </ExifItem>
                ))}
            </Stack>
        </FileInfoSidebar>
    );
};

const ExifItem = styled("div")`
    padding-left: 8px;
    padding-right: 8px;
    display: flex;
    flex-direction: column;
    gap: 4px;
`;
