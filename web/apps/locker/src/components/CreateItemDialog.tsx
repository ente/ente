import {
    addCollectionName,
    toggleCollectionName,
    uploadQueueItemKey,
} from "@/components/createItemDialog/fileUploadHelpers";
import { FileUploadSection } from "@/components/createItemDialog/FileUploadSection";
import {
    CollectionSelector,
    ItemFormFields,
} from "@/components/createItemDialog/ItemFormFields";
import { typeDisplayName } from "@/components/createItemDialog/itemFormFieldsUtils";
import { lockerDialogPaperSx } from "@/components/lockerDialogStyles";
import {
    createDocumentIcon,
    createDocumentIconConfig,
    lockerItemIcon,
    lockerItemIconConfig,
} from "@/components/lockerItemIcons";
import type { LockerUploadLimitState } from "@/services/locker-limits";
import type { LockerUploadProgress } from "@/services/remote";
import type {
    LockerCollection,
    LockerItemType,
    LockerUploadCandidate,
} from "@/types";
import ChevronRightRoundedIcon from "@mui/icons-material/ChevronRightRounded";
import {
    Box,
    ButtonBase,
    Dialog,
    DialogContent,
    DialogTitle,
    Link,
    Stack,
    Typography,
} from "@mui/material";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import { t } from "i18next";
import React, { useRef } from "react";
import { Trans } from "react-i18next";
import {
    type CreateItemDialogEditItem,
    type CreateOption,
    useCreateItemDialogState,
} from "./createItemDialog/useCreateItemDialogState";

const CREATABLE_TYPES: {
    type: CreateOption;
    labelKey: string;
    descriptionKey: string;
    icon: React.ReactNode;
    bgColor: string;
}[] = [
    {
        type: "file",
        labelKey: "saveDocumentTitle",
        descriptionKey: "saveDocumentDescription",
        icon: createDocumentIcon(28, 1.9),
        bgColor: createDocumentIconConfig.backgroundColor,
    },
    {
        type: "note",
        labelKey: "personalNote",
        descriptionKey: "personalNoteDescription",
        icon: lockerItemIcon("note", { size: 28, strokeWidth: 1.9 }),
        bgColor: lockerItemIconConfig("note").backgroundColor,
    },
    {
        type: "physicalRecord",
        labelKey: "thing",
        descriptionKey: "physicalRecordsDescription",
        icon: lockerItemIcon("physicalRecord", { size: 28, strokeWidth: 1.9 }),
        bgColor: lockerItemIconConfig("physicalRecord").backgroundColor,
    },
    {
        type: "accountCredential",
        labelKey: "secret",
        descriptionKey: "accountCredentialsDescription",
        icon: lockerItemIcon("accountCredential", {
            size: 28,
            strokeWidth: 1.9,
        }),
        bgColor: lockerItemIconConfig("accountCredential").backgroundColor,
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
            slotProps={{
                paper: {
                    sx: {
                        ...lockerDialogPaperSx,
                        display: "flex",
                        flexDirection: "column",
                        maxHeight: "min(720px, 90vh)",
                        width: "min(100%, 520px)",
                    },
                },
            }}
        >
            <DialogTitle
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: 2,
                    fontWeight: "bold",
                    px: { xs: 4, sm: 5 },
                    pt: { xs: 4, sm: 4.5 },
                    pb: { xs: 2, sm: 2.5 },
                }}
            >
                <Box sx={{ minWidth: 0 }}>
                    {isEditMode
                        ? t("editItem")
                        : isFileMode
                          ? selectedUploadItems.length > 1
                              ? t("saveDocumentsTitle")
                              : t("saveDocumentTitle")
                          : selectedType
                            ? typeDisplayName(selectedType)
                            : t("saveToLocker")}
                </Box>
                {showUploadCounter && (
                    <Typography
                        variant="small"
                        sx={{
                            flexShrink: 0,
                            color: "text.muted",
                            opacity: 0.8,
                            fontWeight: 500,
                            alignSelf: "center",
                        }}
                    >
                        {savedUploadCount} / {totalUploadCount} {t("saved")}
                    </Typography>
                )}
            </DialogTitle>

            <DialogContent
                sx={{
                    px: { xs: 4, sm: 5 },
                    py: { xs: 2.5, sm: 3 },
                    ...(isFileMode
                        ? {
                              display: "flex",
                              flexDirection: "column",
                              flex: 1,
                              minHeight: 0,
                              overflow: "hidden",
                          }
                        : {}),
                }}
            >
                {shouldShowDialogErrorCard && (
                    <Box
                        sx={(theme) => ({
                            mb: 2.5,
                            px: 2,
                            py: 1.5,
                            borderRadius: "16px",
                            border: `1px solid ${theme.vars.palette.critical.main}22`,
                            backgroundColor: `${theme.vars.palette.critical.main}12`,
                        })}
                    >
                        <Typography
                            variant="small"
                            sx={{ color: "critical.main", fontWeight: 600 }}
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
                                                    color: "critical.main",
                                                    fontWeight: 700,
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
                    <Stack sx={{ gap: 2, pt: 0.5 }}>
                        <Typography variant="body" sx={{ color: "text.muted" }}>
                            {t("informationDescription")}
                        </Typography>
                        <Stack sx={{ gap: 1 }}>
                            {CREATABLE_TYPES.map((option) => (
                                <TypeCard
                                    key={option.type}
                                    label={t(option.labelKey)}
                                    description={t(option.descriptionKey)}
                                    icon={option.icon}
                                    bgColor={option.bgColor}
                                    onClick={() =>
                                        handleSelectOption(option.type)
                                    }
                                />
                            ))}
                        </Stack>
                    </Stack>
                )}

                {isFileMode && !isEditMode && (
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
                            setSelectedCollectionNamesByFileKey((current) => ({
                                ...current,
                                [fileKey]: toggleCollectionName(
                                    current[fileKey] ?? [],
                                    name,
                                ),
                            }))
                        }
                        onAddCollectionName={(fileKey, name) => {
                            setCustomCollectionNames((current) =>
                                addCollectionName(current, name),
                            );
                            setSelectedCollectionNamesByFileKey((current) => ({
                                ...current,
                                [fileKey]: addCollectionName(
                                    current[fileKey] ?? [],
                                    name,
                                ),
                            }));
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
                                        uploadQueueItemKey(item) !== fileKey,
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
                        onClose={handleClose}
                        onUpload={handleUpload}
                    />
                )}

                {formType && (!isFileMode || isEditMode) && (
                    <Stack sx={{ gap: 2.5, pt: 0.5 }}>
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

                        <Stack direction="row" sx={{ gap: 1, pt: 1 }}>
                            <FocusVisibleButton
                                fullWidth
                                color="secondary"
                                onClick={handleClose}
                                disabled={saving}
                            >
                                {t("cancel")}
                            </FocusVisibleButton>
                            <LoadingButton
                                fullWidth
                                color="accent"
                                loading={saving}
                                disabled={!canSave}
                                onClick={() => void handleSave()}
                            >
                                {t("saveRecord")}
                            </LoadingButton>
                        </Stack>
                    </Stack>
                )}
            </DialogContent>
        </Dialog>
    );
};

const TypeCard: React.FC<{
    label: string;
    description: string;
    icon: React.ReactNode;
    bgColor: string;
    onClick: () => void;
}> = ({ label, description, icon, bgColor, onClick }) => (
    <ButtonBase
        onClick={onClick}
        sx={(theme) => ({
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            width: "100%",
            gap: 2,
            px: 1,
            py: 1.25,
            borderRadius: "12px",
            transition: "background-color 0.15s",
            textAlign: "left",
            "&:hover": { backgroundColor: theme.vars.palette.fill.faintHover },
        })}
    >
        <Box
            sx={{
                display: "flex",
                alignItems: "center",
                gap: 2,
                minWidth: 0,
                flex: 1,
            }}
        >
            <Box
                sx={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    width: 48,
                    height: 48,
                    borderRadius: "50%",
                    backgroundColor: bgColor,
                    flexShrink: 0,
                }}
            >
                {icon}
            </Box>
            <Box sx={{ minWidth: 0, flex: 1 }}>
                <Typography variant="body" sx={{ fontWeight: "medium" }}>
                    {label}
                </Typography>
                <Typography
                    variant="small"
                    sx={{ color: "text.muted", textWrap: "balance" }}
                >
                    {description}
                </Typography>
            </Box>
        </Box>
        <ChevronRightRoundedIcon sx={{ color: "text.faint", flexShrink: 0 }} />
    </ButtonBase>
);
