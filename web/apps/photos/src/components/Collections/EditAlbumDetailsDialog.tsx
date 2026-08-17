import CloseIcon from "@mui/icons-material/Close";
import {
    Box,
    Dialog,
    IconButton,
    InputBase,
    Stack,
    styled,
    SvgIcon,
    Typography,
    type SvgIconProps,
    type SxProps,
    type Theme,
} from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import {
    uploadSheetMediaQuery,
    uploadSheetPaperSx,
    useIsUploadSheet,
} from "ente-gallery/components/upload-progress/bottom-sheet";
import {
    maxAlbumDescriptionLength,
    type Collection,
} from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { FocusVisibleUnstyledButton } from "ente-new/photos/components/UnstyledButton";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import { albumDescriptionGraphemeCount } from "ente-new/photos/services/collection";
import { useFormik } from "formik";
import { t } from "i18next";
import React, { useId, useState } from "react";
import { PickCoverPhotoDialog } from "./PickCoverPhotoDialog";

export interface AlbumDetails {
    name: string;
    description: string;
    coverID?: number;
}

type EditAlbumDetailsDialogProps = ModalVisibilityProps & {
    collection: Collection;
    files: EnteFile[];
    initialCoverFile: EnteFile | undefined;
    user: LocalUser;
    onSubmit: (details: AlbumDetails) => Promise<void>;
};

export const EditAlbumDetailsDialog: React.FC<EditAlbumDetailsDialogProps> = ({
    open,
    onClose,
    collection,
    files,
    initialCoverFile,
    user,
    onSubmit,
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const isSheet = useIsUploadSheet();
    const titleID = useId();
    const nameID = useId();
    const nameHelperID = useId();
    const descriptionID = useId();
    const descriptionHelperID = useId();
    const { show: showPickCoverPhoto, props: pickCoverPhotoVisibilityProps } =
        useModalVisibility();
    const [pendingCoverID, setPendingCoverID] = useState<number>();
    const initialName = collection.name;
    const initialDescription = collection.pubMagicMetadata?.data.caption ?? "";
    const formik = useFormik<AlbumDetails>({
        initialValues: { name: initialName, description: initialDescription },
        onSubmit: async ({
            name: untrimmedName,
            description: untrimmedDescription,
        }) => {
            const name = untrimmedName.trim();
            const description = untrimmedDescription.trim();
            const descriptionLength =
                albumDescriptionGraphemeCount(description);
            if (!name || descriptionLength > maxAlbumDescriptionLength) return;
            try {
                await onSubmit({ name, description, coverID: pendingCoverID });
                onClose();
            } catch (e) {
                onGenericError(e);
            }
        },
    });

    const trimmedName = formik.values.name.trim();
    const trimmedDescription = formik.values.description.trim();
    const descriptionLength = albumDescriptionGraphemeCount(trimmedDescription);
    const isDescriptionTooLong = descriptionLength > maxAlbumDescriptionLength;
    const hasChanges =
        trimmedName != initialName.trim() ||
        trimmedDescription != initialDescription.trim() ||
        pendingCoverID !== undefined;
    const isSaveDisabled =
        !trimmedName ||
        isDescriptionTooLong ||
        !hasChanges ||
        formik.isSubmitting;

    const handleClose = () => {
        if (formik.isSubmitting || pickCoverPhotoVisibilityProps.open) return;
        if (hasChanges) {
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

    const handleUseSelectedPhoto = (file: EnteFile) => {
        setPendingCoverID(file.id);
        return Promise.resolve(true);
    };

    const handleResetToDefault = () => {
        setPendingCoverID(0);
        return Promise.resolve(true);
    };

    const canShowCoverEditor = files.some(
        (file) => file.metadata.fileType !== FileType.video,
    );
    const effectiveCoverID =
        pendingCoverID ?? collection.pubMagicMetadata?.data.coverID ?? 0;
    const effectiveCoverFile =
        pendingCoverID === undefined
            ? initialCoverFile
            : pendingCoverID > 0
              ? files.find(({ id }) => id === pendingCoverID)
              : collection.pubMagicMetadata?.data.asc
                ? files.at(-1)
                : files[0];

    return (
        <>
            <Dialog
                open={open}
                onClose={
                    pickCoverPhotoVisibilityProps.open ? undefined : handleClose
                }
                aria-labelledby={titleID}
                maxWidth={false}
                slots={isSheet ? { transition: SlideUpTransition } : undefined}
                slotProps={{ paper: { sx: [paperSx, uploadSheetPaperSx] } }}
            >
                <Stack
                    component="form"
                    onSubmit={formik.handleSubmit}
                    sx={contentSx}
                >
                    <Stack direction="row" sx={headerSx}>
                        <Typography id={titleID} sx={titleSx}>
                            {t("edit_details")}
                        </Typography>
                        <IconButton
                            aria-label={t("close")}
                            disabled={formik.isSubmitting}
                            onClick={handleClose}
                            sx={headerButtonSx}
                        >
                            <CloseIcon sx={{ fontSize: 18 }} />
                        </IconButton>
                    </Stack>
                    <Stack sx={{ gap: "16px" }}>
                        <Stack direction="row" sx={nameRowSx}>
                            {canShowCoverEditor && (
                                <FocusVisibleUnstyledButton
                                    type="button"
                                    aria-label={t("set_cover")}
                                    disabled={formik.isSubmitting}
                                    onClick={showPickCoverPhoto}
                                    sx={coverButtonSx}
                                >
                                    <ItemCard
                                        key={effectiveCoverFile?.id}
                                        TileComponent={CoverTile}
                                        coverFile={effectiveCoverFile}
                                    />
                                    <Box sx={coverBadgeSx}>
                                        <PencilEditIcon
                                            sx={{ fontSize: 12 }}
                                            aria-hidden
                                        />
                                    </Box>
                                </FocusVisibleUnstyledButton>
                            )}
                            <Stack sx={fieldSx}>
                                <Typography
                                    component="label"
                                    htmlFor={nameID}
                                    sx={labelSx}
                                >
                                    {t("album_name")}
                                </Typography>
                                <InputBase
                                    id={nameID}
                                    name="name"
                                    aria-describedby={nameHelperID}
                                    value={formik.values.name}
                                    onChange={formik.handleChange}
                                    autoFocus
                                    fullWidth
                                    disabled={formik.isSubmitting}
                                    error={!trimmedName}
                                    sx={inputSx}
                                />
                                <Typography
                                    id={nameHelperID}
                                    sx={helperSx(!trimmedName)}
                                >
                                    {trimmedName ? "" : t("required")}
                                </Typography>
                            </Stack>
                        </Stack>
                        <Stack sx={fieldSx}>
                            <Typography
                                component="label"
                                htmlFor={descriptionID}
                                sx={labelSx}
                            >
                                {t("description")}
                            </Typography>
                            <InputBase
                                id={descriptionID}
                                name="description"
                                aria-describedby={descriptionHelperID}
                                value={formik.values.description}
                                onChange={formik.handleChange}
                                placeholder={t("caption_placeholder")}
                                multiline
                                rows={5}
                                fullWidth
                                disabled={formik.isSubmitting}
                                error={isDescriptionTooLong}
                                sx={multilineInputSx}
                            />
                            <Typography
                                id={descriptionHelperID}
                                sx={[
                                    helperSx(isDescriptionTooLong),
                                    { textAlign: "right" },
                                ]}
                            >
                                {`${descriptionLength}/${maxAlbumDescriptionLength}`}
                            </Typography>
                        </Stack>
                    </Stack>
                    <LoadingButton
                        type="submit"
                        fullWidth
                        color="accent"
                        loading={formik.isSubmitting}
                        disabled={isSaveDisabled}
                        sx={[
                            saveButtonSx,
                            ...(formik.isSubmitting ? [saveButtonBusySx] : []),
                        ]}
                    >
                        {t("save_changes")}
                    </LoadingButton>
                </Stack>
            </Dialog>
            {canShowCoverEditor && (
                <PickCoverPhotoDialog
                    {...pickCoverPhotoVisibilityProps}
                    collection={collection}
                    files={files}
                    user={user}
                    canResetToDefault={effectiveCoverID > 0}
                    onUseSelectedPhoto={handleUseSelectedPhoto}
                    onResetToDefault={handleResetToDefault}
                />
            )}
        </>
    );
};

const PencilEditIcon: React.FC<SvgIconProps> = (props) => (
    <SvgIcon {...props} viewBox="0 0 12 12">
        <path
            d="M1.89091 8.1546L1.5 10.5L3.84543 10.1091C4.25272 10.0413 4.62863 9.8478 4.9206 9.5558L10.2099 4.26644C10.5967 3.87961 10.5967 3.25245 10.2099 2.86563L9.13435 1.79012C8.7475 1.40329 8.1203 1.4033 7.73345 1.79014L2.44421 7.0795C2.15224 7.37145 1.95879 7.74735 1.89091 8.1546Z"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <path
            d="M7 3L9 5"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </SvgIcon>
);

const CoverTile = styled("div")`
    display: flex;
    position: relative;
    width: 108px;
    height: 108px;
    border-radius: 20px;
    overflow: hidden;
    user-select: none;
    & > img {
        object-fit: cover;
        width: 100%;
        height: 100%;
        pointer-events: none;
    }
`;

const green = "#08c225";
const greenHover = "#07ad21";
const errorColor = "#fa1336";

const paperSx = (theme: Theme) => ({
    width: "min(520px, calc(100svw - 32px))",
    maxWidth: "520px",
    m: 2,
    borderRadius: "20px",
    border: "1px solid #e0e0e0",
    backgroundColor: "#f4f4f4",
    backgroundImage: "none",
    boxShadow: "none",
    color: "text.base",
    ...theme.applyStyles("dark", {
        borderColor: "rgba(255 255 255 / 0.12)",
        backgroundColor: "#1b1b1b",
    }),
});

const contentSx = {
    p: "20px",
    gap: "36px",
    [uploadSheetMediaQuery]: {
        p: "12px 16px",
        pb: "calc(20px + env(safe-area-inset-bottom, 0px))",
        overflowY: "auto",
    },
};

const headerSx = {
    alignItems: "center",
    justifyContent: "space-between",
    gap: "12px",
};

const titleSx = {
    minWidth: 0,
    fontFamily: "'Outfit Variable', sans-serif",
    fontSize: 24,
    lineHeight: "32px",
    fontWeight: 600,
    overflowWrap: "anywhere",
};

const headerButtonSx = (theme: Theme) => ({
    width: 38,
    height: 38,
    p: 0,
    flexShrink: 0,
    color: "text.base",
    backgroundColor: "background.paper",
    "&:hover": { backgroundColor: "fill.faintHover" },
    ...theme.applyStyles("dark", {
        backgroundColor: "rgba(255 255 255 / 0.12)",
    }),
});

const nameRowSx = { alignItems: "center", gap: "16px" };

const coverButtonSx: SxProps<Theme> = {
    position: "relative",
    flexShrink: 0,
    width: 108,
    height: 108,
    borderRadius: "20px",
    "&:focus-visible, &:active": { borderRadius: "20px" },
    "&:disabled": { cursor: "default" },
};

const coverBadgeSx: SxProps<Theme> = (theme) => ({
    position: "absolute",
    right: "-6px",
    bottom: "-4px",
    display: "flex",
    width: 22,
    height: 22,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: "50%",
    color: "#fff",
    backgroundColor: green,
    border: "1.5px solid #f4f4f4",
    ...theme.applyStyles("dark", { borderColor: "#1b1b1b" }),
});

const fieldSx = { flex: 1, minWidth: 0, gap: "8px" };

const labelSx = { fontSize: 14, lineHeight: "20px", fontWeight: 500 };

const inputSx: SxProps<Theme> = (theme) => ({
    minHeight: 52,
    display: "flex",
    alignItems: "center",
    borderRadius: "16px",
    border: "1px solid transparent",
    backgroundColor: "background.paper",
    px: "16px",
    fontSize: 14,
    fontWeight: 500,
    color: "text.base",
    "&.Mui-focused": { borderColor: "rgba(0 0 0 / 0.08)" },
    "&.Mui-error": { borderColor: errorColor },
    "& input, & textarea": { padding: 0 },
    "& input::placeholder, & textarea::placeholder": {
        color: "text.muted",
        opacity: 1,
    },
    ...theme.applyStyles("dark", {
        backgroundColor: "#282828",
        "&.Mui-focused": { borderColor: "rgba(255 255 255 / 0.18)" },
    }),
});

const multilineInputSx: SxProps<Theme> = [
    inputSx,
    { alignItems: "flex-start", py: "20px", lineHeight: "20px" },
];

const helperSx = (isError: boolean) => (theme: Theme) => ({
    fontSize: 12,
    lineHeight: "16px",
    fontWeight: 500,
    color: isError ? errorColor : "rgba(0 0 0 / 0.45)",
    ...(isError
        ? {}
        : theme.applyStyles("dark", { color: "rgba(255 255 255 / 0.45)" })),
});

const saveButtonSx = (theme: Theme) => ({
    minHeight: 52,
    px: 3,
    py: "14px",
    borderRadius: "20px",
    fontSize: 14,
    lineHeight: "20px",
    fontWeight: 500,
    textTransform: "none",
    color: "#fff",
    backgroundColor: green,
    boxShadow: "none",
    "&:hover": { backgroundColor: greenHover, boxShadow: "none" },
    "&.Mui-disabled": {
        color: "#d6d6d6",
        backgroundColor: "#eaeaea",
        ...theme.applyStyles("dark", {
            color: "rgba(255 255 255 / 0.3)",
            backgroundColor: "rgba(255 255 255 / 0.12)",
        }),
    },
});

const saveButtonBusySx = {
    "&.Mui-disabled": { color: "#fff", backgroundColor: green, opacity: 0.7 },
};
