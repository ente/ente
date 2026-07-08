/* eslint-disable @typescript-eslint/ban-ts-comment */
/* TODO: Split this file to deal with the ente-new/photos imports.
1. Move common components into FileInfoComponents.tsx
2. Move the rest out to files in the apps themselves:
   - albums/SharedFileInfo
  -  photos/FileInfo
*/

import CalendarTodayIcon from "@mui/icons-material/CalendarToday";
import CameraOutlinedIcon from "@mui/icons-material/CameraOutlined";
import CloseIcon from "@mui/icons-material/Close";
import DoneIcon from "@mui/icons-material/Done";
import EditIcon from "@mui/icons-material/Edit";
import FaceRetouchingNaturalIcon from "@mui/icons-material/FaceRetouchingNatural";
import FolderOutlinedIcon from "@mui/icons-material/FolderOutlined";
import KeyboardArrowLeftIcon from "@mui/icons-material/KeyboardArrowLeft";
import KeyboardArrowRightIcon from "@mui/icons-material/KeyboardArrowRight";
import KeyboardOptionKeyIcon from "@mui/icons-material/KeyboardOptionKey";
import LocationOnOutlinedIcon from "@mui/icons-material/LocationOnOutlined";
import PhotoOutlinedIcon from "@mui/icons-material/PhotoOutlined";
import TextSnippetOutlinedIcon from "@mui/icons-material/TextSnippetOutlined";
import VideocamOutlinedIcon from "@mui/icons-material/VideocamOutlined";
import {
    Box,
    Button,
    CircularProgress,
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    InputAdornment,
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
import {
    SidebarDrawer,
    SidebarDrawerTitlebar,
} from "ente-base/components/mui/SidebarDrawer";
import { SingleInputForm } from "ente-base/components/SingleInputForm";
import { EllipsizedTypography } from "ente-base/components/Typography";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import { haveWindow } from "ente-base/env";
import { nameAndExtension } from "ente-base/file-name";
import { formattedDate, formattedTime } from "ente-base/i18n-date";
import log from "ente-base/log";
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

// Re-uses images from ~leaflet package.
import "leaflet-defaulticon-compatibility/dist/leaflet-defaulticon-compatibility.webpack.css";
import "leaflet/dist/leaflet.css";
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-unused-expressions
haveWindow() && require("leaflet-defaulticon-compatibility");
const leaflet = haveWindow()
    ? // eslint-disable-next-line @typescript-eslint/no-require-imports
      (require("leaflet") as typeof import("leaflet"))
    : null;

/**
 * Exif data for a file, in a form suitable for use by {@link FileInfo}.
 *
 * TODO: Indicate missing exif (e.g. videos) better, both in the data type, and
 * in the UI (e.g. by omitting the entire row).
 */
export interface FileInfoExif {
    tags: RawExifTags | undefined;
    parsed: ParsedMetadata | undefined;
}

export type FileInfoProps = ModalVisibilityProps & {
    /**
     * The file whose information we are showing.
     */
    file: EnteFile;
    /**
     * Exif information for {@link file}.
     */
    exif: FileInfoExif | undefined;
    /**
     * If set, then controls to edit the file's metadata (name, date, caption)
     * will be shown.
     */
    allowEdits?: boolean;
    /**
     * If set, then an inline map will be shown (if the user has enabled it)
     * using the file's location.
     */
    allowMap?: boolean;
    /**
     * If set, then a chip will be shown for each collection that this file is
     * a part of.
     *
     * Uses {@link fileCollectionIDs}, {@link collectionNameByID} and
     * {@link onSelectCollection}, so all of those props should also be set for
     * this to have an effect.
     */
    showCollections?: boolean;
    /**
     * A map from file IDs to the IDs of the collections that they're a part of.
     *
     * Used when {@link showCollections} is set.
     */
    fileCollectionIDs?: Map<number, number[]>;
    /**
     * A map from collection IDs to their name.
     *
     * Used when {@link showCollections} is set.
     */
    collectionNameByID?: Map<number, string>;
    /**
     * IDs of hidden collections.
     *
     * Used when {@link showCollections} is set.
     */
    hiddenCollectionIDs?: Set<number>;
    /**
     * Called when the action on the file info drawer has changed some metadata
     * for a file.
     *
     * It should return a promise that settles when the changes have been
     * reflected locally. Until the promise settles the UI element that
     * triggered the change will show an activity indicator to the user.
     */
    onFileMetadataUpdate?: () => Promise<void>;
    /**
     * Called when an action on the file info drawer change the caption of the
     * given {@link EnteFile}.
     *
     * This hook allows the file viewer to update the caption it is displaying
     * for the given file. It is called in addition to, and after the settlement
     * of, {@link onFileMetadataUpdate} since the caption update requires a
     * special case refresh of the PhotoSwipe dialog.
     *
     * @param fileID The ID of the file whose caption was updated.
     *
     * @param newCaption The updated value of the file's caption.
     */
    onUpdateCaption: (fileID: number, newCaption: string) => void;
    /**
     * Called when the user selects a collection from among the collections that
     * the file belongs to.
     */
    onSelectCollection?: (collectionID: number) => void;
    /**
     * Called when the user selects a person in the file info panel.
     */
    onSelectPerson?: (personID: string) => void;
    /**
     * Called when an edit surface owned by the file info panel is opened or
     * closed, so the viewer can avoid navigating to another file underneath it.
     */
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
    const { onGenericError } = useBaseContext();

    const [annotatedFaces, setAnnotatedFaces] = useState<AnnotatedFaceID[]>([]);

    const { show: showRawExif, props: rawExifVisibilityProps } =
        useModalVisibility();
    const { show: showAssignPerson, props: assignPersonVisibilityProps } =
        useModalVisibility();
    const { show: showEditLocation, props: editLocationVisibilityProps } =
        useModalVisibility();

    const [captionNavigationLocked, setCaptionNavigationLocked] =
        useState(false);
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
                !!p.name &&
                p.cgroup.data.manuallyAssigned.includes(file.id) &&
                !detectedPersonIDs.has(p.id),
        );
    }, [peopleState, file.id, annotatedFaces]);

    const canAddPerson = isMLEnabled() && assignablePeople.length > 0;

    // Prefer the location in the EnteFile, then fall back to Exif.
    const fileLocationValue = fileLocation(file) ?? exif?.parsed?.location;

    const location = fileLocationValue;

    const annotatedExif = useMemo(() => annotateExif(exif), [exif]);

    useEffect(() => {
        if (!isMLEnabled()) return undefined;

        // Take a dependency on open so that we refresh the list of people by
        // calling `getAnnotatedFacesForFile` again when the file info dialog is
        // closed and reopened.
        //
        // This covers a scenario like:
        // - User opens file info panel
        // - Selects one of the faces
        // - Gives it a name
        // - Then opens the same file again, and reopens the file info panel.
        //
        // Since the `file` hasn't changed, this hook wouldn't rerun. So we also
        // take a dependency on the open state of the dialog, causing us to
        // rerun whenever reopened (even if for the same file).
        if (!open) return undefined;

        setAnnotatedFaces([]);

        let didCancel = false;

        void getAnnotatedFacesForFile(file).then(
            (faces) => !didCancel && setAnnotatedFaces(faces),
        );

        return () => {
            didCancel = true;
        };
    }, [file, open]);

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
            captionNavigationLocked ||
            dateTimeNavigationLocked ||
            renameNavigationLocked);

    useEffect(() => {
        onNavigationLockChange?.(navigationLocked);
    }, [onNavigationLockChange, navigationLocked]);

    return (
        <BottomAlignedFileInfoSidebar {...{ open, onClose }}>
            <SidebarDrawerTitlebar
                onClose={onClose}
                onRootClose={onClose}
                title={t("info")}
            />
            <Stack sx={{ pt: 1, pb: 3, gap: "20px" }}>
                <Caption
                    {...{
                        file,
                        allowEdits,
                        onFileMetadataUpdate,
                        onUpdateCaption,
                        onNavigationLockChange: setCaptionNavigationLocked,
                    }}
                />
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
                        icon={<CameraOutlinedIcon />}
                        title={annotatedExif.takenOnDevice}
                        caption={createMultipartCaption(
                            annotatedExif.fNumber,
                            annotatedExif.exposureTime,
                            annotatedExif.iso,
                        )}
                    />
                )}

                {location ? (
                    <>
                        <InfoItem
                            icon={<LocationOnOutlinedIcon />}
                            title={t("location")}
                            caption={
                                !mapEnabled || !allowMap ? (
                                    <Link
                                        href={openStreetMapLink(location)}
                                        target="_blank"
                                        rel="noopener"
                                        sx={{ fontWeight: "medium" }}
                                    >
                                        {t("view_on_map")}
                                    </Link>
                                ) : (
                                    <LinkButtonUndecorated
                                        onClick={() => updateMapEnabled(false)}
                                    >
                                        {t("disable_map")}
                                    </LinkButtonUndecorated>
                                )
                            }
                            trailingButton={
                                <Stack direction="row" sx={{ gap: 1 }}>
                                    {allowEdits && (
                                        <EditButton
                                            onClick={showEditLocation}
                                        />
                                    )}
                                    <CopyButton
                                        size="medium"
                                        text={openStreetMapLink(location)}
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
                            icon={<LocationOnOutlinedIcon />}
                            title={t("location")}
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
                {isMLEnabled() &&
                    (annotatedFaces.length > 0 ||
                        manuallyAssignedPeople.length > 0 ||
                        canAddPerson) && (
                        <InfoItem icon={<FaceRetouchingNaturalIcon />}>
                            <FilePeopleList
                                file={file}
                                annotatedFaceIDs={annotatedFaces}
                                onSelectFace={handleSelectFace}
                                manuallyAssignedPeople={manuallyAssignedPeople}
                                onSelectPerson={onSelectPerson}
                                onAddPerson={
                                    canAddPerson ? showAssignPerson : undefined
                                }
                                addPersonTitle={t("add_a_person")}
                                addPersonLabel={t("add")}
                            />
                        </InfoItem>
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
                        sx={{ m: 2, textAlign: "right", color: "text.muted" }}
                    >
                        {t("added_by_name", { name: uploaderName })}
                    </Typography>
                )}
            </Stack>
            <FileInfoNavigationHint />
            <RawExif
                {...rawExifVisibilityProps}
                onInfoClose={onClose}
                tags={exif?.tags}
                fileName={fileFileName(file)}
            />

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
        </BottomAlignedFileInfoSidebar>
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
            px: 2,
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

/**
 * Some immediate fields of interest, in the form that we want to display on the
 * info panel for a file.
 */
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

        if (exif.FNumber)
            info.fNumber = exif.FNumber.description; /* e.g. "f/16" */

        if (exif.ExposureTime)
            info.exposureTime = exif.ExposureTime.description; /* "1/10" */

        if (exif.ISOSpeedRatings)
            info.iso = `ISO${tagNumericValue(exif.ISOSpeedRatings)}`;
    }

    return info;
};

const FileInfoSidebar = styled(
    (props: Pick<DialogProps, "open" | "onClose" | "children">) => (
        <SidebarDrawer
            {...props}
            anchor="right"
            // See: [Note: Workarounds for unactionable ARIA warnings], but this
            // time with a different workaround.
            //
            // https://github.com/mui/material-ui/issues/43106#issuecomment-2514637251
            disableRestoreFocus={true}
            closeAfterTransition={true}
        />
    ),
)(({ theme }) => ({
    // [Note: Lighter backdrop for overlays on photo viewer]
    //
    // The default backdrop color we use for the drawer in light mode is too
    // "white" when used in the image gallery because unlike the rest of the app
    // the gallery retains a black background irrespective of the mode. So use a
    // lighter scrim when overlaying content directly atop the image gallery.
    //
    // We don't need to add this special casing for nested overlays (e.g.
    // dialogs initiated from the file info drawer itself) since now there is
    // enough "white" on the screen to warrant the stronger (default) backdrop.
    ...theme.applyStyles("light", {
        ".MuiBackdrop-root": {
            backgroundColor: theme.vars.palette.backdrop.faint,
        },
    }),
}));

const BottomAlignedFileInfoSidebar = styled(FileInfoSidebar)({
    ".MuiDrawer-paper": { display: "flex", flexDirection: "column" },
    ".MuiDrawer-paper > .MuiBox-root": {
        flex: 1,
        display: "flex",
        flexDirection: "column",
    },
});

interface InfoItemProps {
    /**
     * The icon associated with the info entry.
     */
    icon: React.ReactNode;
    /**
     * The primary content / title of the info entry.
     *
     * Only used if {@link children} are not specified.
     */
    title?: string;
    /**
     * The secondary information / subtext associated with the info entry.
     *
     * Only used if {@link children} are not specified.
     */
    caption?: React.ReactNode;
    /**
     * A component, usually a button (e.g. an "edit button"), shown at the
     * trailing edge of the info entry.
     */
    trailingButton?: React.ReactNode;
}

/**
 * An entry in the file info panel listing.
 */
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

type EditButtonProps = ButtonishProps & {
    /**
     * If true, then an activity indicator is shown in place of the edit icon.
     */
    loading?: boolean;
};

const EditButton: React.FC<EditButtonProps> = ({ onClick, loading }) => (
    <IconButton onClick={onClick} disabled={!!loading} color="secondary">
        {!loading ? (
            <EditIcon />
        ) : (
            <CircularProgress size={"24px"} color="inherit" />
        )}
    </IconButton>
);

type CaptionProps = Pick<
    FileInfoProps,
    | "file"
    | "allowEdits"
    | "onFileMetadataUpdate"
    | "onUpdateCaption"
    | "onNavigationLockChange"
>;

const Caption: React.FC<CaptionProps> = ({
    file,
    allowEdits,
    onFileMetadataUpdate,
    onUpdateCaption,
    onNavigationLockChange,
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

    useEffect(() => {
        onNavigationLockChange?.(values.caption != caption || isSaving);
    }, [onNavigationLockChange, values.caption, caption, isSaving]);

    if (!caption.length && !allowEdits) {
        // Visually take up some space, otherwise the info panel for the shared
        // photos without a caption looks squished at the top.
        return <Box sx={{ minHeight: 2 }}></Box>;
    }

    return (
        <CaptionForm onSubmit={handleSubmit}>
            <TextField
                id="caption"
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
                        type="submit"
                        disabled={isSaving}
                        // Prevent layout shift when we're showing progress.
                        sx={{ minWidth: "48px" }}
                    >
                        {isSaving ? (
                            <CircularProgress size="18px" color="inherit" />
                        ) : (
                            <DoneIcon />
                        )}
                    </IconButton>
                    <IconButton onClick={() => resetForm()} disabled={isSaving}>
                        <CloseIcon />
                    </IconButton>
                </Stack>
            )}
        </CaptionForm>
    );
};

const CaptionForm = styled("form")(({ theme }) => ({
    padding: theme.spacing(1),
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
            // Same as before.
            return;
        }

        setIsSaving(true);
        try {
            // [Note: Don't modify offsetTime when editing date via picker]
            //
            // Use the updated date time (both in its canonical dateTime form,
            // and also as in the epoch timestamp), but don't use the offset.
            //
            // The offset here will be the offset of the computer where this
            // user is making this edit, not the offset of the place where the
            // photo was taken. In a future iteration of the date time editor,
            // we can provide functionality for the user to edit the associated
            // offset, but right now it is not even surfaced, so don't also
            // potentially overwrite it.
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
                icon={<CalendarTodayIcon />}
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
            <VideocamOutlinedIcon />
        ) : (
            <PhotoOutlinedIcon />
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
    <Stack direction="row" sx={{ gap: 1 }}>
        {p1 && <div>{p1}</div>}
        {p2 && <div>{p2}</div>}
        {p3 && <div>{p3}</div>}
    </Stack>
);

type RenameFileDialogProps = ModalVisibilityProps & {
    /**
     * The current name of the file.
     */
    fileName: string;
    /**
     * Called when the user makes a change to the existing name and activates the
     * rename button on the dialog.
     *
     * @param newFileName The changed name. The extension currently cannot be
     * modified, but it is guaranteed the name component of {@link newFileName}
     * will be different from that of the {@link fileName} prop of the dialog.
     *
     * Until the promise settles, the dialog will show an activity indicator. If
     * the promise rejects, it will also show an error. If the promise is
     * fulfilled, then the dialog will also be closed.
     *
     * The dialog will also be closed if the user activates the rename button
     * without changing the name.
     */
    onRename: (newFileName: string) => Promise<void>;
};

const RenameFileDialog: React.FC<RenameFileDialogProps> = ({
    open,
    onClose,
    fileName,
    onRename,
}) => {
    const [name, extension] = nameAndExtension(fileName);

    const handleSubmit = async (newName: string) => {
        const newFileName = [newName, extension].filter((x) => !!x).join(".");
        if (newFileName != fileName) {
            await onRename(newFileName);
        }
        onClose();
    };

    return (
        <Dialog {...{ open, onClose }} fullWidth maxWidth="xs">
            <DialogTitle sx={{ "&&&": { paddingBlock: "26px 0px" } }}>
                {t("rename_file")}
            </DialogTitle>
            <DialogContent>
                <SingleInputForm
                    label={t("file_name")}
                    placeholder={t("file_name")}
                    initialValue={name}
                    submitButtonColor="primary"
                    submitButtonTitle={t("rename")}
                    onSubmit={handleSubmit}
                    onCancel={onClose}
                    slotProps={{
                        input: {
                            // Align the adornment text to the input text.
                            sx: { alignItems: "baseline" },
                            endAdornment: extension && (
                                <InputAdornment position="end">
                                    {`.${extension}`}
                                </InputAdornment>
                            ),
                        },
                    }}
                />
            </DialogContent>
        </Dialog>
    );
};

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
            // @ts-ignore
            const map = leaflet.map(mapContainer).setView(position, zoom);
            map.attributionControl.setPrefix(leafletAttributionPrefix);
            // @ts-ignore
            leaflet.tileLayer(urlTemplate, { attribution }).addTo(map);
            // @ts-ignore
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
    height: 200px;
    width: 100%;
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
    if (!tags) {
        return <></>;
    }

    const handleRootClose = () => {
        onClose();
        onInfoClose();
    };

    const items: (readonly [string, string, string, string])[] = Object.entries(
        tags,
    )
        .map(([namespace, namespaceTags]) => {
            return Object.entries(namespaceTags).map(([tagName, tag]) => {
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
                    // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
                    typeof tag.description == "string"
                ) {
                    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-member-access
                    description = tag.description;
                }
                return [key, namespace, tagName, description] as const;
            });
        })
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
    <InfoItem icon={<FolderOutlinedIcon />}>
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
    </InfoItem>
);

const ChipButton = styled((props: ButtonProps) => (
    <Button color="secondary" {...props} />
))(({ theme }) => ({ ...theme.typography.small, padding: "8px" }));
