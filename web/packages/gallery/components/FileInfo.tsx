import {
    ArrowLeft01Icon,
    Calendar04Icon,
    Camera01Icon,
    CameraLensIcon,
    Cancel01Icon,
    Edit02Icon,
    Image01Icon,
    Location01Icon,
    UserAdd01Icon,
    Video02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
// TODO: Split this file to deal with the ente-new/photos imports.

import CloseIcon from "@mui/icons-material/Close";
import DoneIcon from "@mui/icons-material/Done";
import KeyboardArrowLeftIcon from "@mui/icons-material/KeyboardArrowLeft";
import KeyboardArrowRightIcon from "@mui/icons-material/KeyboardArrowRight";
import KeyboardOptionKeyIcon from "@mui/icons-material/KeyboardOptionKey";
import {
    Box,
    Button,
    CircularProgress,
    IconButton,
    Link,
    Stack,
    styled,
    TextField,
    Typography,
    type ButtonProps,
    type DialogProps,
} from "@mui/material";
import { LinkButtonUndecorated } from "ente-base/components/LinkButton";
import type { ButtonishProps } from "ente-base/components/mui";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { SidebarDrawer } from "ente-base/components/mui/SidebarDrawer";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { formattedDate, formattedTime } from "ente-base/i18n-date";
import log from "ente-base/log";
import type { Location } from "ente-base/types";
import { CopyButton } from "ente-gallery/components/FileInfoComponents";
import { RenameFileDialog } from "ente-gallery/components/RenameFileDialog";
import { tagNumericValue, type RawExifTags } from "ente-gallery/services/exif";
import { getLeafletWithDefaultIcons } from "ente-gallery/utils/leaflet";
import { formattedByteSize } from "ente-gallery/utils/units";
import type { EnteFile } from "ente-media/file";
import {
    fileCreationPhotoDate,
    fileFileName,
    fileLocation,
    type ParsedMetadata,
    type ParsedMetadataDate,
} from "ente-media/file-metadata";
import { FileType } from "ente-media/file-type";
import { AssignPersonDialog } from "ente-new/photos/components/AssignPersonDialog";
import { EditLocationDialog } from "ente-new/photos/components/EditLocationDialog";
import { FileDateTimePicker } from "ente-new/photos/components/FileDateTimePicker";
import { FilePeopleList } from "ente-new/photos/components/PeopleList";
import {
    usePeopleStateSnapshot,
    useSettingsSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import {
    updateFileCaption,
    updateFileFileName,
    updateFilePublicMagicMetadata,
    updateFilesLocation,
} from "ente-new/photos/services/file";
import {
    addManualFileAssignmentsToPerson,
    getAnnotatedFacesForFile,
    isMLEnabled,
    type AnnotatedFaceID,
} from "ente-new/photos/services/ml";
import { updateMapEnabled } from "ente-new/photos/services/settings";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useEffect, useMemo, useRef, useState } from "react";
import { Trans } from "react-i18next";

import "leaflet-defaulticon-compatibility/dist/leaflet-defaulticon-compatibility.webpack.css";
import "leaflet/dist/leaflet.css";
const leaflet = getLeafletWithDefaultIcons();

// TODO: Indicate missing exif (e.g. videos) better, both in the data type, and
// in the UI (e.g. by omitting the entire row).
export interface FileInfoExif {
    tags: RawExifTags | undefined;
    parsed: ParsedMetadata | undefined;
}

export type FileInfoProps = ModalVisibilityProps & {
    file: EnteFile;
    exif: FileInfoExif | undefined;
    allowEdits?: boolean;
    allowMap?: boolean;
    showCollections?: boolean;
    fileCollectionIDs?: Map<number, number[]>;
    collectionNameByID?: Map<number, string>;
    hiddenCollectionIDs?: Set<number>;
    onFileMetadataUpdate?: () => Promise<void>;
    // PhotoSwipe needs a separate refresh after caption metadata settles.
    onUpdateCaption: (fileID: number, newCaption: string) => void;
    onSelectCollection?: (collectionID: number) => void;
    onSelectPerson?: (personID: string) => void;
    onNavigationLockChange?: (locked: boolean) => void;
};

export const FileInfo: React.FC<FileInfoProps> = ({
    open,
    onClose,
    file,
    exif,
    allowEdits,
    allowMap,
    showCollections,
    fileCollectionIDs,
    collectionNameByID,
    hiddenCollectionIDs,
    onFileMetadataUpdate,
    onUpdateCaption,
    onSelectCollection,
    onSelectPerson,
    onNavigationLockChange,
}) => {
    const { mapEnabled } = useSettingsSnapshot();
    const peopleState = usePeopleStateSnapshot();
    const { showMiniDialog, onGenericError } = useBaseContext();

    const [annotatedFaces, setAnnotatedFaces] = useState<AnnotatedFaceID[]>([]);

    const { show: showRawExif, props: rawExifVisibilityProps } =
        useModalVisibility();
    const { show: showAssignPerson, props: assignPersonVisibilityProps } =
        useModalVisibility();
    const { show: showEditLocation, props: editLocationVisibilityProps } =
        useModalVisibility();

    const [captionEditState, setCaptionEditState] =
        useState<CaptionEditState>("saved");
    const [dateTimeNavigationLocked, setDateTimeNavigationLocked] =
        useState(false);
    const [renameNavigationLocked, setRenameNavigationLocked] = useState(false);

    const assignablePeople = useMemo(
        () =>
            (peopleState?.visiblePeople ?? []).filter(
                (p) => p.type == "cgroup" && !!p.name,
            ),
        [peopleState],
    );

    const manuallyAssignedPeople = useMemo(() => {
        if (!isMLEnabled()) return [];

        const detectedPersonIDs = new Set(
            annotatedFaces.map((f) => f.personID),
        );
        return (peopleState?.people ?? []).filter(
            (p) =>
                p.type == "cgroup" &&
                p.cgroup.data.manuallyAssigned.includes(file.id) &&
                !detectedPersonIDs.has(p.id),
        );
    }, [peopleState, file.id, annotatedFaces]);

    const canAddPerson = isMLEnabled() && assignablePeople.length > 0;

    const fileLocationValue = fileLocation(file) ?? exif?.parsed?.location;

    const location = fileLocationValue;

    const annotatedExif = useMemo(() => annotateExif(exif), [exif]);

    useEffect(() => {
        if (!isMLEnabled()) return undefined;

        // Naming a face does not change file identity; reopening must refetch it.
        if (!open) return undefined;

        setAnnotatedFaces([]);

        let didCancel = false;

        void getAnnotatedFacesForFile(file).then(
            (faces) => !didCancel && setAnnotatedFaces(faces),
        );

        return () => {
            didCancel = true;
        };
    }, [file, open, peopleState]);

    const handleClose = () => {
        if (captionEditState == "saving") return;
        if (captionEditState == "unsaved") {
            showMiniDialog({
                title: t("discard_changes"),
                message: t("discard_changes_confirm_message"),
                continue: {
                    text: t("discard"),
                    color: "critical",
                    action: onClose,
                },
            });
            return;
        }
        onClose();
    };

    const handleSelectFace = ({ personID, faceID }: AnnotatedFaceID) => {
        log.info(`Selected person ${personID} for faceID ${faceID}`);
        onSelectPerson?.(personID);
    };

    const handleAddPerson = async (personID: string) => {
        assignPersonVisibilityProps.onClose();
        try {
            await addManualFileAssignmentsToPerson(personID, [file.id]);
        } catch (e) {
            onGenericError(e);
        }
    };

    const handleEditLocationConfirm = async (newLocation: Location) => {
        try {
            await updateFilesLocation(
                [file],
                newLocation.latitude,
                newLocation.longitude,
            );
            await onFileMetadataUpdate?.();
        } catch (e) {
            onGenericError(e);
        }
    };

    const uploaderName = file.pubMagicMetadata?.data.uploaderName;

    const navigationLocked =
        open &&
        (rawExifVisibilityProps.open ||
            assignPersonVisibilityProps.open ||
            editLocationVisibilityProps.open ||
            captionEditState != "saved" ||
            dateTimeNavigationLocked ||
            renameNavigationLocked);

    useEffect(() => {
        onNavigationLockChange?.(navigationLocked);
    }, [onNavigationLockChange, navigationLocked]);

    return (
        <FileInfoSidebar open={open} onClose={handleClose}>
            <FileInfoHeader>
                <IconButton
                    aria-label={t("go_back")}
                    onClick={handleClose}
                    sx={{ width: 24, height: 40, flexShrink: 0, p: 0 }}
                >
                    <HugeiconsIcon icon={ArrowLeft01Icon} size={18} />
                </IconButton>
                <Typography
                    component="h2"
                    sx={{
                        flex: 1,
                        fontSize: 20,
                        lineHeight: "28px",
                        fontWeight: 600,
                    }}
                >
                    {t("details")}
                </Typography>
                <IconButton aria-label={t("close")} onClick={handleClose}>
                    <HugeiconsIcon icon={Cancel01Icon} size={18} />
                </IconButton>
            </FileInfoHeader>
            <Stack sx={{ pb: 2.5, gap: 2.5 }}>
                <Caption
                    {...{
                        file,
                        allowEdits,
                        onFileMetadataUpdate,
                        onUpdateCaption,
                        onEditStateChange: setCaptionEditState,
                    }}
                />
                <Stack sx={{ gap: "2px" }}>
                    <CreationTime
                        {...{
                            file,
                            allowEdits,
                            onFileMetadataUpdate,
                            onNavigationLockChange: setDateTimeNavigationLocked,
                        }}
                    />
                    <FileName
                        {...{
                            file,
                            annotatedExif,
                            allowEdits,
                            onFileMetadataUpdate,
                            onNavigationLockChange: setRenameNavigationLocked,
                        }}
                    />

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
                {(location || allowEdits) && (
                    <FileInfoSection title={t("location")}>
                        {location ? (
                            <>
                                <InfoItem
                                    icon={
                                        <HugeiconsIcon
                                            icon={Location01Icon}
                                            size={18}
                                        />
                                    }
                                    caption={
                                        !mapEnabled || !allowMap ? (
                                            <Link
                                                href={openStreetMapLink(
                                                    location,
                                                )}
                                                target="_blank"
                                                rel="noopener"
                                                sx={{ fontWeight: "medium" }}
                                            >
                                                {t("view_on_map")}
                                            </Link>
                                        ) : (
                                            <LinkButtonUndecorated
                                                onClick={() =>
                                                    updateMapEnabled(false)
                                                }
                                            >
                                                {t("disable_map")}
                                            </LinkButtonUndecorated>
                                        )
                                    }
                                    trailingButton={
                                        <Stack
                                            direction="row"
                                            sx={{
                                                gap: { xs: 0, sm: 1 },
                                                flexShrink: 0,
                                            }}
                                        >
                                            {allowEdits && (
                                                <EditButton
                                                    onClick={showEditLocation}
                                                />
                                            )}
                                            <CopyButton
                                                size="small"
                                                text={openStreetMapLink(
                                                    location,
                                                )}
                                            />
                                        </Stack>
                                    }
                                />
                                {allowMap && (
                                    <MapBox
                                        key={`${location.latitude}-${location.longitude}`}
                                        location={location}
                                        mapEnabled={mapEnabled}
                                    />
                                )}
                            </>
                        ) : (
                            allowEdits && (
                                <InfoItem
                                    icon={
                                        <HugeiconsIcon
                                            icon={Location01Icon}
                                            size={18}
                                        />
                                    }
                                    caption={
                                        <LinkButtonUndecorated
                                            onClick={showEditLocation}
                                        >
                                            {t("add_location_button")}
                                        </LinkButtonUndecorated>
                                    }
                                />
                            )
                        )}
                    </FileInfoSection>
                )}
                <FileInfoDivider />
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
                {isMLEnabled() &&
                    (annotatedFaces.length > 0 ||
                        manuallyAssignedPeople.length > 0 ||
                        canAddPerson) && (
                        <FileInfoSection title={t("people")}>
                            <FileInfoPeople>
                                <FilePeopleList
                                    file={file}
                                    annotatedFaceIDs={annotatedFaces}
                                    onSelectFace={handleSelectFace}
                                    manuallyAssignedPeople={
                                        manuallyAssignedPeople
                                    }
                                    onSelectPerson={onSelectPerson}
                                    onAddPerson={
                                        canAddPerson
                                            ? showAssignPerson
                                            : undefined
                                    }
                                    addPersonTitle={t("add_a_person")}
                                    addPersonLabel={t("add")}
                                    addPersonIcon={
                                        <HugeiconsIcon
                                            icon={UserAdd01Icon}
                                            size={24}
                                        />
                                    }
                                />
                            </FileInfoPeople>
                        </FileInfoSection>
                    )}
                {showCollections &&
                    fileCollectionIDs &&
                    collectionNameByID &&
                    onSelectCollection && (
                        <Albums
                            {...{
                                file,
                                fileCollectionIDs,
                                collectionNameByID,
                                hiddenCollectionIDs,
                                onSelectCollection,
                            }}
                        />
                    )}
                {uploaderName && (
                    <Typography
                        variant="small"
                        sx={{
                            fontSize: 12,
                            lineHeight: "16px",
                            textAlign: "right",
                            color: "text.muted",
                        }}
                    >
                        {t("added_by_name", { name: uploaderName })}
                    </Typography>
                )}
            </Stack>
            <FileInfoNavigationHint />
            <RawExif {...rawExifVisibilityProps} tags={exif?.tags} />

            {canAddPerson && (
                <AssignPersonDialog
                    {...assignPersonVisibilityProps}
                    people={assignablePeople}
                    title={t("add_a_person")}
                    onSelectPerson={handleAddPerson}
                />
            )}

            {allowEdits && (
                <EditLocationDialog
                    {...editLocationVisibilityProps}
                    files={[file]}
                    onConfirm={handleEditLocationConfirm}
                />
            )}
        </FileInfoSidebar>
    );
};

const navigationShortcut = "Alt / Option";

const FileInfoNavigationHint: React.FC = () => (
    <Typography
        component="div"
        variant="tiny"
        sx={{
            display: { xs: "none", sm: "block" },
            mt: "auto",
            pb: 3,
            px: 0,
            color: "text.muted",
            opacity: 0.24,
        }}
    >
        <Trans
            i18nKey="use_shortcut_to_navigate"
            components={{
                shortcut: <ShortcutHint shortcut={navigationShortcut} />,
            }}
        />
    </Typography>
);

interface ShortcutHintProps {
    shortcut: string;
}

function ShortcutHint({ shortcut }: ShortcutHintProps) {
    return (
        <InlineShortcut>
            <NavigationHintKey>
                <KeyboardOptionKeyIcon sx={{ fontSize: 12 }} />
                <Typography
                    component="span"
                    variant="tiny"
                    sx={{ fontWeight: "medium" }}
                >
                    {shortcut}
                </Typography>
            </NavigationHintKey>
            <NavigationHintSeparator>+</NavigationHintSeparator>
            <NavigationHintKey>
                <KeyboardArrowLeftIcon
                    titleAccess={t("previous")}
                    sx={{ fontSize: 14 }}
                />
            </NavigationHintKey>
            <NavigationHintSeparator>/</NavigationHintSeparator>
            <NavigationHintKey>
                <KeyboardArrowRightIcon
                    titleAccess={t("next")}
                    sx={{ fontSize: 14 }}
                />
            </NavigationHintKey>
        </InlineShortcut>
    );
}

const InlineShortcut = styled("span")({
    display: "inline-flex",
    alignItems: "center",
    gap: 4,
    verticalAlign: "middle",
});

const NavigationHintKey = styled("span")(
    ({ theme }) => `
    min-height: 20px;
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 2px 5px;
    border: 1px solid ${theme.vars.palette.stroke.faint};
    border-radius: 4px;
    color: ${theme.vars.palette.text.muted};
`,
);

const NavigationHintSeparator: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <Typography
        component="span"
        variant="tiny"
        sx={{ color: "text.faint", lineHeight: 1 }}
    >
        {children}
    </Typography>
);

type AnnotatedExif = Required<FileInfoExif> & {
    resolution?: string;
    megaPixels?: string;
    takenOnDevice?: string;
    fNumber?: string;
    exposureTime?: string;
    iso?: string;
};

const annotateExif = (
    fileInfoExif: FileInfoExif | undefined,
): AnnotatedExif | undefined => {
    if (!fileInfoExif?.tags || !fileInfoExif.parsed) return undefined;

    const info: AnnotatedExif = { ...fileInfoExif };

    const { width, height } = fileInfoExif.parsed;
    if (width && height) {
        info.resolution = `${width} x ${height}`;
        const mp = Math.round((width * height) / 1000000);
        if (mp) info.megaPixels = `${mp}MP`;
    }

    const { tags } = fileInfoExif;
    const { exif } = tags;

    if (exif) {
        if (exif.Make && exif.Model)
            info.takenOnDevice = `${exif.Make.description} ${exif.Model.description}`;

        const fNumber = exif.FNumber;
        if (fNumber && fNumber.value[1] != 0) {
            info.fNumber = fNumber.description;
        }

        if (exif.ExposureTime)
            info.exposureTime = exif.ExposureTime.description;

        if (exif.ISOSpeedRatings)
            info.iso = `ISO${tagNumericValue(exif.ISOSpeedRatings)}`;
    }

    return info;
};

const FileInfoSidebar = styled(
    (props: Pick<DialogProps, "open" | "onClose" | "children">) => (
        <SidebarDrawer
            {...props}
            maxWidth="425px"
            disableAppTitlebarBackdrop
            anchor="right"
            // Avoid MUI's aria-hidden focus warning when this closes.
            disableRestoreFocus={true}
            closeAfterTransition={true}
        />
    ),
)(({ theme }) => ({
    ...theme.applyStyles("light", {
        ".MuiBackdrop-root": {
            backgroundColor: theme.vars.palette.backdrop.faint,
        },
    }),
    ".MuiDrawer-paper": {
        display: "flex",
        flexDirection: "column",
        top: "calc(env(titlebar-area-height, 0px) + 12px)",
        bottom: "calc(env(safe-area-inset-bottom, 0px) + 12px)",
        height: "auto",
        borderRadius: 20,
        [theme.breakpoints.down("sm")]: {
            bottom: 0,
            borderRadius: "20px 20px 0 0",
        },
    },
    ".MuiDrawer-paper > .MuiBox-root": {
        flex: 1,
        display: "flex",
        flexDirection: "column",
        padding: "0 clamp(28px, 6vw, 30px)",
        minWidth: 0,
        [theme.breakpoints.down("sm")]: {
            paddingInline: "20px",
            paddingBottom: "env(safe-area-inset-bottom, 0px)",
        },
    },
    [theme.breakpoints.down("sm")]: {
        "& .MuiIconButton-root": {
            width: 44,
            height: 44,
            flexShrink: 0,
            padding: 12,
            "& > svg": { width: 20, height: 20 },
        },
    },
}));

interface InfoItemProps {
    icon: React.ReactNode;
    title?: string;
    caption?: React.ReactNode;
    trailingButton?: React.ReactNode;
}

const FileInfoHeader = styled(Stack)(({ theme }) => ({
    position: "sticky",
    top: 0,
    zIndex: 2,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    minHeight: 92,
    paddingTop: 18,
    [theme.breakpoints.down("sm")]: {
        minHeight: 64,
        paddingTop: 0,
        gap: 4,
        "& .MuiIconButton-root:first-of-type": { marginLeft: -12 },
        "& .MuiIconButton-root:last-of-type": { marginRight: -12 },
    },
    flexShrink: 0,
    backgroundColor: theme.vars.palette.background.paper,
    "& .MuiIconButton-root": { color: theme.vars.palette.text.base },
}));
const FileInfoDivider = styled("hr")(({ theme }) => ({
    width: "100%",
    margin: 0,
    border: 0,
    borderTop: `1px solid ${theme.vars.palette.stroke.faint}`,
    ...theme.applyStyles("dark", {
        borderColor: `color-mix(in srgb, ${theme.vars.palette.stroke.faint} 55%, transparent)`,
    }),
}));
const FileInfoSection: React.FC<React.PropsWithChildren<{ title: string }>> = ({
    title,
    children,
}) => (
    <Stack component="section" sx={{ gap: 1.75 }}>
        <FileInfoDivider sx={{ mb: 0.75 }} />
        <Typography
            component="h3"
            sx={{ fontSize: 18, lineHeight: "24px", fontWeight: 600 }}
        >
            {title}
        </Typography>
        {children}
    </Stack>
);
// Keep the shared people lists unchanged outside File Info.
const FileInfoPeople = styled(Box)(({ theme }) => ({
    "& > div": { gap: "14px 18px", marginBlockEnd: 0 },
    "& button": { width: 60, minWidth: 0, gap: 7 },
    "& button > img, & button > div, & button > .MuiSkeleton-root": {
        width: 60,
        height: 60,
        borderRadius: 20,
    },
    "& button > div": { border: 0 },
    "& .MuiTypography-root": {
        fontSize: 14,
        lineHeight: "20px",
        color: theme.vars.palette.text.base,
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap",
        width: "100%",
        textAlign: "center",
    },
}));
const InfoItem: React.FC<React.PropsWithChildren<InfoItemProps>> = ({
    icon,
    title,
    caption,
    trailingButton,
    children,
}) => (
    <Stack
        direction="row"
        sx={{
            alignItems: "center",
            minHeight: 56,
            gap: { xs: "8px", sm: "10px" },
            p: { xs: "8px 0", sm: "8px 10px" },
            minWidth: 0,
        }}
    >
        <InfoItemIconContainer>{icon}</InfoItemIconContainer>
        {children ? (
            <Box sx={{ flex: 1, minWidth: 0 }}>{children}</Box>
        ) : (
            <Stack sx={{ flex: 1, minWidth: 0, gap: "4px" }}>
                {title && (
                    <Typography
                        sx={{
                            overflowWrap: "anywhere",
                            fontSize: 14,
                            lineHeight: "20px",
                        }}
                    >
                        {title}
                    </Typography>
                )}
                <Typography
                    variant="mini"
                    {...(typeof caption != "string" && { component: "div" })}
                    sx={{
                        color: "text.muted",
                        fontSize: 12,
                        lineHeight: "16px",
                    }}
                >
                    {caption}
                </Typography>
            </Stack>
        )}
        {trailingButton}
    </Stack>
);
const InfoItemIconContainer = styled("div")(({ theme }) => ({
    width: 34,
    height: 34,
    flexShrink: 0,
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    color: theme.vars.palette.text.muted,
    "& > svg": { width: 18, height: 18 },
    [theme.breakpoints.down("sm")]: {
        width: 32,
        "& > svg": { width: 20, height: 20 },
    },
}));
type EditButtonProps = ButtonishProps & { loading?: boolean };
const EditButton: React.FC<EditButtonProps> = ({ onClick, loading }) => (
    <IconButton
        aria-label={t("edit_details")}
        onClick={onClick}
        disabled={!!loading}
        color="secondary"
        sx={{ width: 40, height: 40, flexShrink: 0, color: "text.muted" }}
    >
        {!loading ? (
            <HugeiconsIcon icon={Edit02Icon} size={18} />
        ) : (
            <CircularProgress size={18} color="inherit" />
        )}
    </IconButton>
);

type CaptionEditState = "saved" | "unsaved" | "saving";

type CaptionProps = Pick<
    FileInfoProps,
    "file" | "allowEdits" | "onFileMetadataUpdate" | "onUpdateCaption"
> & { onEditStateChange: (state: CaptionEditState) => void };

const Caption: React.FC<CaptionProps> = ({
    file,
    allowEdits,
    onFileMetadataUpdate,
    onUpdateCaption,
    onEditStateChange,
}) => {
    const [isSaving, setIsSaving] = useState(false);

    const caption = file.pubMagicMetadata?.data.caption ?? "";

    const formik = useFormik<{ caption: string }>({
        initialValues: { caption },
        enableReinitialize: true,
        validate: ({ caption }) =>
            caption.length > 5000
                ? { caption: t("caption_character_limit") }
                : {},
        onSubmit: async ({ caption: newCaption }, { setFieldError }) => {
            if (newCaption == caption) return;
            setIsSaving(true);
            try {
                await updateFileCaption(file, newCaption);
                await onFileMetadataUpdate?.();
                onUpdateCaption(file.id, newCaption);
                setIsSaving(false);
            } catch (e) {
                log.error("Failed to update caption", e);
                setIsSaving(false);
                setFieldError("caption", t("generic_error"));
            }
        },
    });

    const { values, errors, handleChange, handleSubmit, resetForm } = formik;

    const editState: CaptionEditState = isSaving
        ? "saving"
        : values.caption != caption
          ? "unsaved"
          : "saved";

    useEffect(() => {
        onEditStateChange(editState);
    }, [onEditStateChange, editState]);

    if (!caption.length && !allowEdits) {
        return <Box sx={{ minHeight: 2 }}></Box>;
    }

    return (
        <CaptionForm onSubmit={handleSubmit}>
            <TextField
                id="caption"
                sx={{ m: { sm: 0 } }}
                name="caption"
                type="text"
                multiline
                maxRows={7}
                aria-label={t("description")}
                hiddenLabel
                fullWidth
                placeholder={t("caption_placeholder")}
                value={values.caption}
                onChange={handleChange("caption")}
                error={!!errors.caption}
                helperText={errors.caption}
                disabled={!allowEdits || isSaving}
            />
            {values.caption != caption && (
                <Stack direction="row" sx={{ justifyContent: "flex-end" }}>
                    <IconButton
                        aria-label={t("save")}
                        type="submit"
                        disabled={isSaving}
                        sx={{ minWidth: "48px" }}
                    >
                        {isSaving ? (
                            <CircularProgress size="18px" color="inherit" />
                        ) : (
                            <DoneIcon />
                        )}
                    </IconButton>
                    <IconButton
                        aria-label={t("cancel")}
                        onClick={() => resetForm()}
                        disabled={isSaving}
                    >
                        <CloseIcon />
                    </IconButton>
                </Stack>
            )}
        </CaptionForm>
    );
};

const CaptionForm = styled("form")(({ theme }) => ({
    "& .MuiFilledInput-root": {
        backgroundColor: "transparent",
        borderRadius: 12,
        padding: "6px 0",
        fontSize: 14,
        lineHeight: "20px",
        color: theme.vars.palette.text.muted,
        "&:hover": { backgroundColor: theme.vars.palette.fill.fainter },
        "&.Mui-focused": { backgroundColor: theme.vars.palette.fill.fainter },
        "&::before": { borderBottom: 0 },
        "&:hover:not(.Mui-disabled, .Mui-error)::before": { borderBottom: 0 },
        "&.Mui-disabled": { backgroundColor: "transparent" },
    },
    "& textarea.Mui-disabled": {
        WebkitTextFillColor: theme.vars.palette.text.muted,
    },
}));

type CreationTimeProps = Pick<
    FileInfoProps,
    "allowEdits" | "onFileMetadataUpdate" | "onNavigationLockChange"
> & { file: EnteFile };

const CreationTime: React.FC<CreationTimeProps> = ({
    file,
    allowEdits,
    onFileMetadataUpdate,
    onNavigationLockChange,
}) => {
    const { onGenericError } = useBaseContext();

    const [isEditing, setIsEditing] = useState(false);
    const [isSaving, setIsSaving] = useState(false);

    const originalDate = fileCreationPhotoDate(file);

    useEffect(() => {
        onNavigationLockChange?.(isEditing || isSaving);
    }, [onNavigationLockChange, isEditing, isSaving]);

    const saveEdits = async (pickedTime: ParsedMetadataDate) => {
        setIsEditing(false);

        const { dateTime, timestamp: editedTime } = pickedTime;
        if (editedTime == originalDate.getTime()) {
            return;
        }

        setIsSaving(true);
        try {
            // The picker reports this computer's offset, not the photo's.
            await updateFilePublicMagicMetadata(file, { dateTime, editedTime });
            await onFileMetadataUpdate?.();
        } catch (e) {
            onGenericError(e);
        }
        setIsSaving(false);
    };

    return (
        <>
            <InfoItem
                icon={<HugeiconsIcon icon={Calendar04Icon} size={18} />}
                title={formattedDate(originalDate)}
                caption={formattedTime(originalDate)}
                trailingButton={
                    allowEdits && (
                        <EditButton
                            onClick={() => setIsEditing(true)}
                            loading={isSaving}
                        />
                    )
                }
            />
            {isEditing && (
                <FileDateTimePicker
                    initialValue={originalDate}
                    onAccept={saveEdits}
                    onDidClose={() => setIsEditing(false)}
                />
            )}
        </>
    );
};

type FileNameProps = Pick<
    FileInfoProps,
    "allowEdits" | "onFileMetadataUpdate" | "onNavigationLockChange"
> & { file: EnteFile; annotatedExif: AnnotatedExif | undefined };

const FileName: React.FC<FileNameProps> = ({
    file,
    annotatedExif,
    allowEdits,
    onFileMetadataUpdate,
    onNavigationLockChange,
}) => {
    const { show: showRename, props: renameVisibilityProps } =
        useModalVisibility();

    useEffect(() => {
        onNavigationLockChange?.(renameVisibilityProps.open);
    }, [onNavigationLockChange, renameVisibilityProps.open]);

    const fileName = fileFileName(file);

    const handleRename = async (newFileName: string) => {
        await updateFileFileName(file, newFileName);
        await onFileMetadataUpdate?.();
    };

    const icon =
        file.metadata.fileType == FileType.video ? (
            <HugeiconsIcon icon={Video02Icon} size={18} />
        ) : (
            <HugeiconsIcon icon={Image01Icon} size={18} />
        );

    const fileSize = file.info?.fileSize;
    const caption = createMultipartCaption(
        annotatedExif?.megaPixels,
        annotatedExif?.resolution,
        fileSize ? formattedByteSize(fileSize) : undefined,
    );

    return (
        <>
            <InfoItem
                icon={icon}
                title={fileName}
                caption={caption}
                trailingButton={
                    allowEdits && <EditButton onClick={showRename} />
                }
            />
            <RenameFileDialog
                {...renameVisibilityProps}
                fileName={fileName}
                onRename={handleRename}
            />
        </>
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

const leafletAttributionPrefix =
    '<a href="https://leafletjs.com" target="_blank" rel="noopener noreferrer">Leaflet</a>';

interface MapBoxProps {
    location: Location;
    mapEnabled: boolean;
}

const MapBox: React.FC<MapBoxProps> = ({ location, mapEnabled }) => {
    const urlTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    const attribution =
        '&copy; <a target="_blank" rel="noopener noreferrer" href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
    const zoom = 16;

    const mapBoxContainerRef = useRef<HTMLDivElement>(null);
    const mapRef = useRef<L.Map | null>(null);
    const markerRef = useRef<L.Marker | null>(null);

    useEffect(() => {
        if (!leaflet) return;
        if (!mapEnabled) {
            if (mapRef.current) {
                mapRef.current.remove();
                mapRef.current = null;
                markerRef.current = null;
            }
            return;
        }

        const mapContainer = mapBoxContainerRef.current;
        if (!mapContainer) return;

        const position: L.LatLngTuple = [location.latitude, location.longitude];
        if (!mapRef.current) {
            const map = leaflet.map(mapContainer).setView(position, zoom);
            map.attributionControl.setPrefix(leafletAttributionPrefix);
            leaflet
                .tileLayer(urlTemplate, {
                    attribution,
                    referrerPolicy: "strict-origin-when-cross-origin",
                })
                .addTo(map);
            markerRef.current = leaflet.marker(position).addTo(map);
            mapRef.current = map;
        } else {
            mapRef.current.setView(position, zoom);
            markerRef.current?.setLatLng(position);
        }
        return () => {
            if (mapRef.current) {
                mapRef.current.remove();
                mapRef.current = null;
                markerRef.current = null;
            }
        };
    }, [
        mapEnabled,
        location.latitude,
        location.longitude,
        zoom,
        attribution,
        urlTemplate,
    ]);

    return mapEnabled ? (
        <MapBoxContainer ref={mapBoxContainerRef} />
    ) : (
        <MapBoxEnableContainer>
            <ChipButton onClick={() => updateMapEnabled(true)}>
                {t("enable_map")}
            </ChipButton>
        </MapBoxEnableContainer>
    );
};

const MapBoxContainer = styled("div")`
    height: 156px;
    width: 100%;
    border-radius: 20px;
    overflow: hidden;
    flex-shrink: 0;
`;

const MapBoxEnableContainer = styled(MapBoxContainer)(
    ({ theme }) => `
    position: relative;
    display: flex;
    justify-content: center;
    align-items: center;
    background-color: ${theme.vars.palette.fill.fainter};
`,
);

interface RawExifProps {
    open: boolean;
    onClose: () => void;
    tags: RawExifTags | undefined;
}

const RawExif: React.FC<RawExifProps> = ({ open, onClose, tags }) => {
    if (!tags) {
        return <></>;
    }

    const items: (readonly [string, string, string, string])[] = Object.entries(
        tags,
    )
        .map(([namespace, namespaceTags]) => {
            return Object.entries(namespaceTags).map(
                ([tagName, tag]: [string, unknown]) => {
                    const key = `${namespace}:${tagName}`;
                    let description = "<...>";
                    if (typeof tag == "string") {
                        description = tag;
                    } else if (typeof tag == "number") {
                        description = `${tag}`;
                    } else if (
                        tag &&
                        typeof tag == "object" &&
                        "description" in tag &&
                        typeof tag.description == "string"
                    ) {
                        description = tag.description;
                    }
                    return [key, namespace, tagName, description] as const;
                },
            );
        })
        .flat()
        .filter(([, , , description]) => description);

    const namespaces = [...new Set(items.map(([, namespace]) => namespace))];

    return (
        <FileInfoSidebar open={open} onClose={onClose}>
            <FileInfoHeader>
                <IconButton
                    aria-label={t("go_back")}
                    onClick={onClose}
                    sx={{
                        width: 40,
                        height: 40,
                        flexShrink: 0,
                        p: 0,
                        ml: -1.25,
                        borderRadius: "50%",
                    }}
                >
                    <HugeiconsIcon icon={ArrowLeft01Icon} size={18} />
                </IconButton>
                <Typography
                    component="h2"
                    sx={{
                        flex: 1,
                        fontSize: 20,
                        lineHeight: "28px",
                        fontWeight: 600,
                    }}
                >
                    {t("exif")}
                </Typography>
                <CopyButton size="small" text={JSON.stringify(tags)} />
            </FileInfoHeader>
            <Stack sx={{ gap: 2.5, pb: 3 }}>
                {namespaces.map((namespace) => (
                    <FileInfoSection
                        key={namespace}
                        title={
                            namespace.charAt(0).toUpperCase() +
                            namespace.slice(1)
                        }
                    >
                        <Box component="dl" sx={{ m: 0, pl: 2 }}>
                            {items
                                .filter(
                                    ([, itemNamespace]) =>
                                        itemNamespace === namespace,
                                )
                                .map(([key, , tagName, description]) => (
                                    <Stack
                                        key={key}
                                        sx={{ py: 1.25, gap: 0.5 }}
                                    >
                                        <Typography
                                            component="dt"
                                            variant="small"
                                            sx={{
                                                color: "text.muted",
                                                overflowWrap: "anywhere",
                                            }}
                                        >
                                            {tagName}
                                        </Typography>
                                        <Typography
                                            component="dd"
                                            sx={{
                                                m: 0,
                                                fontSize: 14,
                                                lineHeight: "22px",
                                                overflowWrap: "anywhere",
                                                whiteSpace: "pre-wrap",
                                            }}
                                        >
                                            {description}
                                        </Typography>
                                    </Stack>
                                ))}
                        </Box>
                    </FileInfoSection>
                ))}
            </Stack>
        </FileInfoSidebar>
    );
};

type AlbumsProps = Required<
    Pick<
        FileInfoProps,
        "fileCollectionIDs" | "collectionNameByID" | "onSelectCollection"
    >
> & { file: EnteFile; hiddenCollectionIDs?: Set<number> };

const Albums: React.FC<AlbumsProps> = ({
    file,
    fileCollectionIDs,
    collectionNameByID,
    hiddenCollectionIDs,
    onSelectCollection,
}) => (
    <FileInfoSection title={t("albums")}>
        <Stack
            direction="row"
            sx={{
                gap: 1,
                flexWrap: "wrap",
                justifyContent: "flex-start",
                alignItems: "flex-start",
            }}
        >
            {fileCollectionIDs
                .get(file.id)
                ?.filter((collectionID) => collectionNameByID.has(collectionID))
                .map((collectionID) => {
                    const isHiddenCollection =
                        hiddenCollectionIDs?.has(collectionID);
                    return (
                        <ChipButton
                            key={collectionID}
                            onClick={() => {
                                if (!isHiddenCollection) {
                                    onSelectCollection(collectionID);
                                }
                            }}
                        >
                            {isHiddenCollection
                                ? t("section_hidden")
                                : collectionNameByID.get(collectionID)}
                        </ChipButton>
                    );
                })}
        </Stack>
    </FileInfoSection>
);

const ChipButton = styled((props: ButtonProps) => (
    <Button color="secondary" {...props} />
))(({ theme }) => ({
    ...theme.typography.mini,
    minHeight: 38,
    padding: "10px 16px",
    borderRadius: 24,
    color: theme.vars.palette.text.muted,
    backgroundColor: theme.vars.palette.fill.fainter,
    textTransform: "none",
    overflowWrap: "anywhere",
    maxWidth: "100%",
}));
