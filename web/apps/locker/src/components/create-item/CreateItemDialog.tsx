import { lockerScrollAreaSx } from "@/components/create-item/create-item-dialog-styles";
import {
    addCollectionName,
    toggleCollectionName,
    uploadQueueItemKey,
} from "@/components/create-item/file-upload-helpers";
import { FileUploadSection } from "@/components/create-item/FileUploadSection";
import { typeDisplayName } from "@/components/create-item/item-form-fields-utils";
import {
    CollectionSelector,
    ItemFormFields,
} from "@/components/create-item/ItemFormFields";
import {
    createDocumentIconConfig,
    lockerItemIconConfig,
} from "@/components/items/locker-item-icons";
import type { LockerUploadLimitState } from "@/services/locker-limits";
import type { LockerUploadProgress } from "@/services/uploads";
import {
    lockerHeaderIconButtonSx,
    lockerPrimaryButtonSx,
} from "@/styles/fields";
import type {
    LockerCollection,
    LockerItemType,
    LockerUploadCandidate,
} from "@/types";
import {
    ArrowLeft01Icon,
    Cancel01Icon,
    CancelCircleIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ChevronRightRoundedIcon from "@mui/icons-material/ChevronRightRounded";
import {
    Box,
    ButtonBase,
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    Link,
    Stack,
    Typography,
} from "@mui/material";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { type ComponentProps, useRef } from "react";
import { Trans } from "react-i18next";
import {
    type CreateItemDialogEditItem,
    type CreateOption,
    useCreateItemDialogState,
} from "./use-create-item-dialog-state";

const CREATABLE_TYPES: {
    type: CreateOption;
    labelKey: string;
    descriptionKey: string;
    icon: ComponentProps<typeof HugeiconsIcon>["icon"];
}[] = [
    {
        type: "file",
        labelKey: "saveDocumentTitle",
        descriptionKey: "saveDocumentDescription",
        icon: createDocumentIconConfig.icon,
    },
    {
        type: "note",
        labelKey: "personalNote",
        descriptionKey: "personalNoteDescription",
        icon: lockerItemIconConfig("note").icon,
    },
    {
        type: "physicalRecord",
        labelKey: "thing",
        descriptionKey: "physicalRecordsDescription",
        icon: lockerItemIconConfig("physicalRecord").icon,
    },
    {
        type: "accountCredential",
        labelKey: "secret",
        descriptionKey: "accountCredentialsDescription",
        icon: lockerItemIconConfig("accountCredential").icon,
    },
];

interface CreateItemDialogProps {
    open: boolean;
    onClose: () => void;
    collections: LockerCollection[];
    onSave: (
        type: LockerItemType,
        data: Record<string, unknown>,
        collectionIDs: number[],
    ) => Promise<void>;
    onUploadProgress?: (
        file: File,
        collectionIDs: number[],
        onProgress: (progress: LockerUploadProgress) => void,
    ) => Promise<void>;
    onUploadItemComplete?: () => void;
    onUploadsFinished?: (uploadedCount: number) => Promise<void>;
    onCreateCollection?: (name: string) => Promise<number>;
    onEnsureCollections?: (
        names: string[],
    ) => Promise<Map<string, number> | Record<string, number>>;
    onEnsureUploadLimitState?: () => Promise<
        { userDetails: LockerUploadLimitState } | undefined
    >;
    defaultCollectionID?: number | null;
    initialItems?: LockerUploadCandidate[];
    editItem?: CreateItemDialogEditItem | null;
    userDetails?: LockerUploadLimitState;
}

export const CreateItemDialog: React.FC<CreateItemDialogProps> = ({
    open,
    onClose,
    collections,
    onSave,
    onUploadProgress,
    onUploadItemComplete,
    onUploadsFinished,
    onCreateCollection,
    onEnsureCollections,
    onEnsureUploadLimitState,
    defaultCollectionID,
    initialItems,
    editItem,
    userDetails,
}) => {
    const fileInputRef = useRef<HTMLInputElement>(null);
    const {
        canSave,
        canUpload,
        completedFileKeys,
        customCollectionNames,
        displayCollections,
        error,
        failedFileKeys,
        formData,
        formType,
        handleClose,
        handleDialogClose,
        handleFieldChange,
        handleFileSelect,
        handleSave,
        handleSelectOption,
        handleStepBackToOptions,
        handleUpload,
        isEditMode,
        isFileMode,
        saving,
        savedUploadCount,
        selectedCollectionIDs,
        selectedCollectionNamesByFileKey,
        selectedOption,
        selectedType,
        selectedUploadItems,
        setCustomCollectionNames,
        setSelectedCollectionIDs,
        setSelectedCollectionNamesByFileKey,
        setSelectedUploadItems,
        setShowPassword,
        shouldShowDialogErrorCard,
        showPassword,
        showUploadCounter,
        totalUploadCount,
        upgradeCTAType,
        uploading,
        uploadingFileKeys,
        uploadCapByFileKey,
        uploadProgressByFileKey,
    } = useCreateItemDialogState({
        open,
        collections,
        onClose,
        onSave,
        onUploadProgress,
        onUploadItemComplete,
        onUploadsFinished,
        onEnsureCollections,
        onEnsureUploadLimitState,
        defaultCollectionID,
        initialItems,
        editItem,
        userDetails,
    });

    return (
        <Dialog
            open={open}
            onClose={handleDialogClose}
            fullWidth
            maxWidth="sm"
            sx={(theme) => ({
                "& .MuiBackdrop-root": { backgroundColor: "rgba(0 0 0 / 0.6)" },
                "& .MuiDialogTitle-root": { padding: 0 },
                "& .MuiDialogContent-root": {
                    padding: 0,
                    paddingTop: "16px",
                    paddingRight: isFileMode ? 0 : "14px",
                    marginRight: isFileMode ? 0 : "-14px",
                },
                [theme.breakpoints.down("sm")]: {
                    "& .MuiDialog-container": { alignItems: "flex-end" },
                },
            })}
            slotProps={{
                paper: {
                    sx: (theme) => ({
                        display: "flex",
                        flexDirection: "column",
                        maxHeight: "min(720px, 90vh)",
                        width: "min(100%, 440px)",
                        borderRadius: "24px",
                        backgroundColor: theme.vars.palette.background.default,
                        padding: "20px",
                        margin: "16px",
                        [theme.breakpoints.down("sm")]: {
                            width: "100%",
                            maxWidth: "100%",
                            margin: 0,
                            borderRadius: "20px 20px 0 0",
                            paddingBottom:
                                "max(34px, env(safe-area-inset-bottom))",
                            maxHeight: "90vh",
                        },
                    }),
                },
            }}
        >
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    gap: "12px",
                    minHeight: 38,
                    flexShrink: 0,
                }}
            >
                {!isEditMode &&
                    selectedOption !== null &&
                    !(isFileMode && selectedUploadItems.length > 0) && (
                        <IconButton
                            onClick={handleStepBackToOptions}
                            disabled={saving || uploading}
                            aria-label={t("go_back")}
                            sx={lockerHeaderIconButtonSx}
                        >
                            <HugeiconsIcon
                                icon={ArrowLeft01Icon}
                                size={18}
                                strokeWidth={1.5}
                            />
                        </IconButton>
                    )}
                <DialogTitle
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        fontSize: 18,
                        lineHeight: "24px",
                        fontWeight: 600,
                        whiteSpace: "nowrap",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                    }}
                >
                    {isEditMode
                        ? t("editItem")
                        : isFileMode
                          ? selectedUploadItems.length > 1
                              ? t("saveDocumentsTitle")
                              : t("saveDocumentTitle")
                          : selectedType
                            ? typeDisplayName(selectedType)
                            : t("saveToLocker")}
                </DialogTitle>
                <IconButton
                    onClick={handleClose}
                    disabled={saving || uploading}
                    aria-label={t("close")}
                    sx={lockerHeaderIconButtonSx}
                >
                    <HugeiconsIcon
                        icon={Cancel01Icon}
                        size={18}
                        strokeWidth={1.5}
                    />
                </IconButton>
            </Box>

            <DialogContent
                sx={(theme) => ({
                    ...(isFileMode
                        ? {
                              display: "flex",
                              flexDirection: "column",
                              flex: 1,
                              minHeight: 0,
                              overflow: "hidden",
                          }
                        : lockerScrollAreaSx(theme)),
                })}
            >
                {shouldShowDialogErrorCard && (
                    <Box
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            gap: "16px",
                            minHeight: 66,
                            px: "16px",
                            py: "12px",
                            mb: "16px",
                            borderRadius: "20px",
                            backgroundColor: "background.paper",
                            flexShrink: 0,
                        }}
                    >
                        <Box
                            sx={{
                                color: "critical.main",
                                flexShrink: 0,
                                display: "flex",
                            }}
                        >
                            <HugeiconsIcon
                                icon={CancelCircleIcon}
                                size={24}
                                strokeWidth={1.5}
                            />
                        </Box>
                        <Typography
                            variant="mini"
                            sx={{ color: "text.muted", minWidth: 0 }}
                        >
                            {upgradeCTAType === "fileCountLimit" ? (
                                <Trans
                                    i18nKey="uploadFileCountLimitErrorBodyWithUpgrade"
                                    components={{
                                        cta: (
                                            <Link
                                                href="https://photos.ente.com"
                                                target="_blank"
                                                rel="noopener"
                                                underline="always"
                                                sx={{
                                                    color: "accent.main",
                                                    fontWeight: 600,
                                                }}
                                            />
                                        ),
                                    }}
                                />
                            ) : (
                                error
                            )}
                        </Typography>
                    </Box>
                )}

                {!isEditMode && !selectedOption && (
                    <Stack sx={{ gap: "24px" }}>
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            {t("informationDescription")}
                        </Typography>
                        <Stack sx={{ gap: "16px" }}>
                            {CREATABLE_TYPES.map((option) => (
                                <TypeCard
                                    key={option.type}
                                    label={t(option.labelKey)}
                                    description={t(option.descriptionKey)}
                                    icon={option.icon}
                                    onClick={() =>
                                        handleSelectOption(option.type)
                                    }
                                />
                            ))}
                        </Stack>
                    </Stack>
                )}

                {isFileMode && !isEditMode && (
                    <>
                        {showUploadCounter && (
                            <Typography
                                variant="small"
                                sx={{
                                    color: "text.muted",
                                    mb: "16px",
                                    flexShrink: 0,
                                }}
                            >
                                {savedUploadCount} / {totalUploadCount}{" "}
                                {t("saved")}
                            </Typography>
                        )}
                        <FileUploadSection
                            fileInputRef={fileInputRef}
                            selectedUploadItems={selectedUploadItems}
                            collections={displayCollections}
                            availableCollectionNames={customCollectionNames}
                            selectedCollectionNamesByFileKey={
                                selectedCollectionNamesByFileKey
                            }
                            completedFileKeys={completedFileKeys}
                            failedFileKeys={failedFileKeys}
                            uploadingFileKeys={uploadingFileKeys}
                            uploadProgressByFileKey={uploadProgressByFileKey}
                            uploadCapByFileKey={uploadCapByFileKey}
                            uploading={uploading}
                            canUpload={canUpload}
                            onFileSelect={handleFileSelect}
                            onToggleCollectionName={(fileKey, name) =>
                                setSelectedCollectionNamesByFileKey(
                                    (current) => ({
                                        ...current,
                                        [fileKey]: toggleCollectionName(
                                            current[fileKey] ?? [],
                                            name,
                                        ),
                                    }),
                                )
                            }
                            onAddCollectionName={(fileKey, name) => {
                                setCustomCollectionNames((current) =>
                                    addCollectionName(current, name),
                                );
                                setSelectedCollectionNamesByFileKey(
                                    (current) => ({
                                        ...current,
                                        [fileKey]: addCollectionName(
                                            current[fileKey] ?? [],
                                            name,
                                        ),
                                    }),
                                );
                            }}
                            onAddAvailableCollectionName={(name) =>
                                setCustomCollectionNames((current) =>
                                    addCollectionName(current, name),
                                )
                            }
                            onSetCollectionNamesForAllItems={(names) =>
                                setSelectedCollectionNamesByFileKey(
                                    Object.fromEntries(
                                        selectedUploadItems.map((item) => [
                                            uploadQueueItemKey(item),
                                            names,
                                        ]),
                                    ),
                                )
                            }
                            onRemoveItem={(fileKey) => {
                                setSelectedUploadItems((current) =>
                                    current.filter(
                                        (item) =>
                                            uploadQueueItemKey(item) !==
                                            fileKey,
                                    ),
                                );
                                setSelectedCollectionNamesByFileKey((current) =>
                                    Object.fromEntries(
                                        Object.entries(current).filter(
                                            ([key]) => key !== fileKey,
                                        ),
                                    ),
                                );
                            }}
                            onUpload={handleUpload}
                        />
                    </>
                )}

                {formType && (!isFileMode || isEditMode) && (
                    <Stack sx={{ gap: "24px" }}>
                        <ItemFormFields
                            type={formType}
                            data={formData}
                            onChange={handleFieldChange}
                            showPassword={showPassword}
                            onTogglePassword={() =>
                                setShowPassword((value) => !value)
                            }
                        />

                        <CollectionSelector
                            key={`${open ? "open" : "closed"}:${
                                editItem?.id ?? "create"
                            }:${formType}`}
                            collections={displayCollections}
                            selectedIDs={selectedCollectionIDs}
                            initialSelectedIDs={
                                isEditMode ? editItem?.collectionIDs : undefined
                            }
                            onToggle={(collectionID) =>
                                setSelectedCollectionIDs((current) =>
                                    current.includes(collectionID)
                                        ? current.filter(
                                              (id) => id !== collectionID,
                                          )
                                        : [...current, collectionID],
                                )
                            }
                            onCreateCollection={onCreateCollection}
                        />

                        {error && upgradeCTAType !== "fileCountLimit" && (
                            <Typography
                                variant="small"
                                sx={{ color: "critical.main" }}
                            >
                                {error}
                            </Typography>
                        )}

                        <LoadingButton
                            fullWidth
                            color="accent"
                            loading={saving}
                            disabled={!canSave}
                            onClick={() => void handleSave()}
                            sx={(theme) =>
                                lockerPrimaryButtonSx(theme, {
                                    loading: saving,
                                })
                            }
                        >
                            {t("saveRecord")}
                        </LoadingButton>
                    </Stack>
                )}
            </DialogContent>
        </Dialog>
    );
};

const TypeCard: React.FC<{
    label: string;
    description: string;
    icon: ComponentProps<typeof HugeiconsIcon>["icon"];
    onClick: () => void;
}> = ({ label, description, icon, onClick }) => (
    <ButtonBase
        onClick={onClick}
        sx={(theme) => ({
            display: "flex",
            alignItems: "center",
            width: "100%",
            gap: "12px",
            px: "12px",
            py: "9px",
            minHeight: 58,
            borderRadius: "20px",
            backgroundColor: theme.vars.palette.background.paper,
            transition: "background-color 0.15s",
            textAlign: "left",
            "&:hover": { backgroundColor: theme.vars.palette.fill.faintHover },
        })}
    >
        <Box
            sx={(theme) => ({
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                width: 36,
                height: 36,
                flexShrink: 0,
                color: theme.vars.palette.accent.main,
            })}
        >
            <HugeiconsIcon
                icon={icon}
                size={20}
                strokeWidth={1.5}
                color="currentColor"
            />
        </Box>
        <Box sx={{ flex: 1, minWidth: 0 }}>
            <Typography variant="small" sx={{ fontWeight: 500 }}>
                {label}
            </Typography>
            <Typography variant="mini" sx={{ color: "text.muted", mt: "4px" }}>
                {description}
            </Typography>
        </Box>
        <Box
            sx={{
                width: 36,
                height: 36,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
            }}
        >
            <ChevronRightRoundedIcon
                sx={{ fontSize: 24, color: "text.base" }}
            />
        </Box>
    </ButtonBase>
);
