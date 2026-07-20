import { Box } from "@mui/material";
import {
    SpaceAvatarCropPage,
    spaceSetupAvatarCropFooterHeight,
    spaceSetupAvatarCropSize,
} from "components/SpaceAvatarCropPage";
import { SpaceAvatarImage } from "components/SpaceAvatarImage";
import { SpaceBackIcon } from "components/SpaceBackIcon";
import { SpaceButtonSpinner } from "components/SpaceButtonSpinner";
import React, { useEffect, useRef, useState } from "react";
import type { Area, Point } from "react-easy-crop";
import { setupProfileBackground } from "screens/SetupProfileScreen";
import { spaceTouchTargetSize } from "styles/touchTargets";
import {
    prepareSpaceAvatarImageFromCrop,
    spaceAvatarCropImageForFile,
    spaceAvatarImageErrorMessage,
    spaceAvatarImageInputAccept,
} from "utils/spacePostImage";

const green = "#08C225";
const textBase = "#000";
const textLight = "#969696";
const textMuted = "#666";
const warning = "#F63A3A";

interface AvatarCropImage {
    file: File;
    url: string;
}

interface SetupProfilePhotoScreenProps {
    errorMessage?: string;
    isSubmitting?: boolean;
    onBack: () => void;
    onContinue: (avatarFile: File | null) => Promise<void>;
}

const AvatarPlaceholder: React.FC = () => (
    <SpaceAvatarImage aria-hidden border="4px solid white" borderRadius="50%" />
);

export const SetupProfilePhotoScreen: React.FC<
    SetupProfilePhotoScreenProps
> = ({ errorMessage, isSubmitting = false, onBack, onContinue }) => {
    const [avatarCropImage, setAvatarCropImage] =
        useState<AvatarCropImage | null>(null);
    const [avatarCrop, setAvatarCrop] = useState<Point>({ x: 0, y: 0 });
    const [avatarCropPixels, setAvatarCropPixels] = useState<Area | null>(null);
    const [avatarError, setAvatarError] = useState<string>();
    const [avatarZoom, setAvatarZoom] = useState(1);
    const [isApplyingAvatarCrop, setIsApplyingAvatarCrop] = useState(false);
    const [isPreparingAvatar, setIsPreparingAvatar] = useState(false);
    const [isSkipping, setIsSkipping] = useState(false);
    const avatarCropUrlRef = useRef<string | null>(null);
    const avatarSelectionIDRef = useRef(0);
    const fileInputRef = useRef<HTMLInputElement | null>(null);
    const canAddPicture = !isSubmitting && !isPreparingAvatar;
    const canSkip = !isSubmitting && !isPreparingAvatar;

    useEffect(
        () => () => {
            if (avatarCropUrlRef.current) {
                URL.revokeObjectURL(avatarCropUrlRef.current);
            }
        },
        [],
    );

    const clearAvatarCropImage = () => {
        avatarSelectionIDRef.current += 1;
        if (avatarCropUrlRef.current) {
            URL.revokeObjectURL(avatarCropUrlRef.current);
            avatarCropUrlRef.current = null;
        }
        setAvatarCropImage(null);
        setAvatarCrop({ x: 0, y: 0 });
        setAvatarCropPixels(null);
        setAvatarZoom(1);
        setIsApplyingAvatarCrop(false);
        setIsPreparingAvatar(false);
    };

    const prepareSelectedAvatar = async (file: File, selectionID: number) => {
        setIsPreparingAvatar(true);
        if (avatarCropUrlRef.current) {
            URL.revokeObjectURL(avatarCropUrlRef.current);
            avatarCropUrlRef.current = null;
        }
        setAvatarCropImage(null);
        setAvatarCropPixels(null);
        try {
            const cropImage = await spaceAvatarCropImageForFile(file);
            if (avatarSelectionIDRef.current != selectionID) {
                URL.revokeObjectURL(cropImage.url);
                return;
            }

            avatarCropUrlRef.current = cropImage.url;
            setAvatarCrop({ x: 0, y: 0 });
            setAvatarCropImage({ file, url: cropImage.url });
            setAvatarCropPixels(null);
            setAvatarError(undefined);
            setAvatarZoom(1);
        } catch (error) {
            if (avatarSelectionIDRef.current != selectionID) return;
            console.error("Failed to prepare space avatar", error);
            setAvatarError(spaceAvatarImageErrorMessage(error));
        } finally {
            if (avatarSelectionIDRef.current == selectionID) {
                setIsPreparingAvatar(false);
            }
        }
    };

    const handleAvatarChange: React.ChangeEventHandler<HTMLInputElement> = (
        event,
    ) => {
        const file = event.target.files?.[0];
        event.target.value = "";
        if (!file) return;

        const selectionID = avatarSelectionIDRef.current + 1;
        avatarSelectionIDRef.current = selectionID;
        setAvatarError(undefined);
        void prepareSelectedAvatar(file, selectionID);
    };

    const applyAvatarCrop = async () => {
        if (!avatarCropImage || !avatarCropPixels) return;

        setIsApplyingAvatarCrop(true);
        try {
            const avatar = await prepareSpaceAvatarImageFromCrop(
                avatarCropImage.file,
                avatarCropImage.url,
                avatarCropPixels,
            );

            setAvatarError(undefined);
            await onContinue(avatar.file);
            setIsApplyingAvatarCrop(false);
        } catch (error) {
            console.error("Failed to crop space avatar", error);
            setAvatarError(spaceAvatarImageErrorMessage(error));
            setIsApplyingAvatarCrop(false);
        }
    };

    const skipProfilePicture = async () => {
        setIsSkipping(true);
        await onContinue(null);
        setIsSkipping(false);
    };

    const avatarFileInput = (
        <Box
            component="input"
            ref={fileInputRef}
            accept={spaceAvatarImageInputAccept}
            onChange={handleAvatarChange}
            type="file"
            sx={{ display: "none" }}
        />
    );

    if (avatarCropImage) {
        return (
            <>
                {avatarFileInput}
                <SpaceAvatarCropPage
                    background={setupProfileBackground}
                    crop={avatarCrop}
                    errorMessage={errorMessage ?? avatarError}
                    imageURL={avatarCropImage.url}
                    isDoneDisabled={!avatarCropPixels}
                    isSaving={isApplyingAvatarCrop || isSubmitting}
                    onBack={clearAvatarCropImage}
                    onChooseAnother={() => fileInputRef.current?.click()}
                    onCropChange={setAvatarCrop}
                    onCropComplete={(_croppedArea, croppedAreaPixels) =>
                        setAvatarCropPixels(croppedAreaPixels)
                    }
                    onDone={() => void applyAvatarCrop()}
                    onZoomChange={setAvatarZoom}
                    secondaryActionVariant="button"
                    title="Add a profile photo"
                    zoom={avatarZoom}
                />
            </>
        );
    }

    return (
        <Box
            component="main"
            sx={{
                bgcolor: setupProfileBackground,
                color: textBase,
                display: "grid",
                height: "100dvh",
                inset: 0,
                overflow: "hidden",
                placeItems: { xs: "stretch", sm: "start center" },
                position: "fixed",
                width: "100%",
            }}
        >
            <Box
                sx={{
                    bgcolor: setupProfileBackground,
                    boxSizing: "border-box",
                    display: "grid",
                    gridTemplateRows: `42px minmax(0, 1fr) auto ${spaceSetupAvatarCropFooterHeight}`,
                    height: "100%",
                    minHeight: 0,
                    mx: "auto",
                    overflow: "hidden",
                    pb: "calc(20px + env(safe-area-inset-bottom))",
                    pt: "32px",
                    px: 3,
                    width: "100%",
                    "@media (min-width: 600px)": { maxWidth: 390 },
                }}
            >
                <Box
                    component="header"
                    sx={{
                        display: "grid",
                        gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                        height: spaceTouchTargetSize,
                        width: "100%",
                    }}
                >
                    <Box
                        component="button"
                        type="button"
                        aria-label="Back"
                        disabled={isSubmitting}
                        onClick={onBack}
                        sx={{
                            alignItems: "center",
                            bgcolor: "transparent",
                            border: 0,
                            color: textBase,
                            cursor: isSubmitting ? "default" : "pointer",
                            display: "flex",
                            height: spaceTouchTargetSize,
                            justifyContent: "flex-start",
                            p: 0,
                            width: spaceTouchTargetSize,
                            "&:focus-visible": {
                                borderRadius: "50%",
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                        }}
                    >
                        <SpaceBackIcon />
                    </Box>
                    <Box
                        component="h1"
                        sx={{
                            alignSelf: "center",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 20,
                            fontWeight: 600,
                            justifySelf: "center",
                            lineHeight: "28px",
                            m: 0,
                            whiteSpace: "nowrap",
                        }}
                    >
                        Add a profile photo
                    </Box>
                    <Box />
                </Box>

                {avatarFileInput}
                <Box
                    component="button"
                    type="button"
                    aria-label="Add profile picture"
                    disabled={!canAddPicture}
                    onClick={() => fileInputRef.current?.click()}
                    sx={{
                        alignItems: "center",
                        alignSelf: "center",
                        aspectRatio: "1 / 1",
                        bgcolor: "transparent",
                        border: 0,
                        borderRadius: "50%",
                        color: textBase,
                        cursor: canAddPicture ? "pointer" : "default",
                        display: "flex",
                        gridRow: 2,
                        justifyContent: "center",
                        justifySelf: "center",
                        overflow: "hidden",
                        p: 0,
                        width: spaceSetupAvatarCropSize,
                        "&:focus-visible": {
                            outline: `2px solid ${green}`,
                            outlineOffset: 3,
                        },
                    }}
                >
                    {isPreparingAvatar ? (
                        <Box
                            component="span"
                            sx={{
                                color: textLight,
                                fontFamily:
                                    '"Inter Variable", Inter, sans-serif',
                                fontSize: 13,
                                fontWeight: 600,
                                lineHeight: "18px",
                            }}
                        >
                            Preparing...
                        </Box>
                    ) : (
                        <AvatarPlaceholder />
                    )}
                </Box>
                {(avatarError || errorMessage) && (
                    <Box
                        role="alert"
                        sx={{
                            color: warning,
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 13,
                            fontWeight: 500,
                            gridRow: 3,
                            lineHeight: "18px",
                            mt: 2,
                            textAlign: "center",
                        }}
                    >
                        {errorMessage ?? avatarError}
                    </Box>
                )}

                <Box
                    sx={{
                        bgcolor: setupProfileBackground,
                        bottom: 0,
                        boxSizing: "border-box",
                        display: "flex",
                        flexDirection: "column",
                        gap: "10px",
                        left: "50%",
                        maxWidth: 390,
                        p: "16px 24px calc(20px + env(safe-area-inset-bottom))",
                        position: "fixed",
                        transform: "translateX(-50%)",
                        width: "100%",
                    }}
                >
                    <Box
                        className="green-bg"
                        component="button"
                        type="button"
                        disabled={!canAddPicture}
                        aria-label={isPreparingAvatar ? "Preparing" : undefined}
                        aria-busy={isPreparingAvatar ? true : undefined}
                        onClick={() => fileInputRef.current?.click()}
                        sx={{
                            alignItems: "center",
                            bgcolor: green,
                            border: 0,
                            borderRadius: "20px",
                            color: "white",
                            cursor: canAddPicture ? "pointer" : "default",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 500,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            p: "14px 24px",
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 3,
                            },
                            "&:hover": canAddPicture
                                ? { bgcolor: "#07AE22" }
                                : undefined,
                        }}
                    >
                        {isPreparingAvatar ? (
                            <SpaceButtonSpinner />
                        ) : (
                            "Add picture"
                        )}
                    </Box>
                    <Box
                        component="button"
                        type="button"
                        disabled={!canSkip}
                        aria-label={isSkipping ? "Saving" : undefined}
                        aria-busy={isSkipping ? true : undefined}
                        onClick={() => void skipProfilePicture()}
                        sx={{
                            alignItems: "center",
                            bgcolor: "#F2F2F2",
                            border: 0,
                            borderRadius: "20px",
                            color: textMuted,
                            cursor: canSkip ? "pointer" : "default",
                            display: "flex",
                            fontFamily: '"Inter Variable", Inter, sans-serif',
                            fontSize: 14,
                            fontWeight: 600,
                            height: 48,
                            justifyContent: "center",
                            lineHeight: "20px",
                            opacity: canSkip || isSkipping ? 1 : 0.56,
                            p: "14px 24px",
                            width: "100%",
                            "&:focus-visible": {
                                outline: `2px solid ${green}`,
                                outlineOffset: 2,
                            },
                            "&:hover": canSkip
                                ? { bgcolor: "#ECECEC" }
                                : undefined,
                        }}
                    >
                        {isSkipping ? <SpaceButtonSpinner /> : "Skip for now"}
                    </Box>
                </Box>
            </Box>
        </Box>
    );
};
