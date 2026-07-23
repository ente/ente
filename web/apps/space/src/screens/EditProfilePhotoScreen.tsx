import { ArrowLeft02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box } from "@mui/material";
import { SpaceAvatarCropPage } from "components/SpaceAvatarCropPage";
import { SpaceLoadingSpinner } from "components/SpaceRouteFallback";
import React, { useEffect, useRef, useState } from "react";
import type { Area, Point } from "react-easy-crop";
import { profileBackground } from "screens/ProfileScreen";
import { spaceTouchTargetSize } from "styles/touchTargets";
import {
    prepareSpaceAvatarImageFromCrop,
    prepareSpaceCoverImageFromCrop,
    spaceAvatarCropImageForFile,
    spaceAvatarImageErrorMessage,
    spaceAvatarImageInputAccept,
    spaceCoverCropImageForFile,
    spaceCoverImageErrorMessage,
    spaceCoverImageInputAccept,
    spaceProfileCoverAspectRatio,
} from "utils/spacePostImage";

const green = "#08C225";
const textBase = "#000";
const warning = "#F63A3A";

interface AvatarCropImage {
    file: File;
    url: string;
}

interface EditProfilePhotoScreenProps {
    avatarFile: File;
    onBack: () => void;
    onSave: (avatarFile: File) => Promise<void>;
    variant?: "avatar" | "cover";
}

interface EditProfileCoverScreenProps {
    coverFile: File;
    onBack: () => void;
    onSave: (coverFile: File) => Promise<void>;
}

const EditProfilePhotoShell: React.FC<
    React.PropsWithChildren<{ onBack: () => void; title: string }>
> = ({ children, onBack, title }) => (
    <Box
        component="main"
        sx={{
            bgcolor: profileBackground,
            color: textBase,
            display: "grid",
            minHeight: "100svh",
            overflowX: "hidden",
            placeItems: { xs: "stretch", sm: "start center" },
        }}
    >
        <Box
            sx={{
                bgcolor: profileBackground,
                boxSizing: "border-box",
                display: "flex",
                flexDirection: "column",
                minHeight: "100svh",
                mx: "auto",
                width: "100%",
                "@media (min-width: 600px)": { maxWidth: 390 },
            }}
        >
            <Box
                component="header"
                sx={{
                    alignItems: "center",
                    display: "grid",
                    gridTemplateColumns: `${spaceTouchTargetSize}px 1fr ${spaceTouchTargetSize}px`,
                    height: 56,
                    px: 2,
                    width: "100%",
                }}
            >
                <Box
                    component="button"
                    type="button"
                    aria-label="Back to profile"
                    onClick={onBack}
                    sx={{
                        alignItems: "center",
                        bgcolor: "transparent",
                        border: 0,
                        color: textBase,
                        cursor: "pointer",
                        display: "flex",
                        height: spaceTouchTargetSize,
                        justifyContent: "flex-start",
                        ml: "-2px",
                        p: 0,
                        width: spaceTouchTargetSize,
                        "&:focus-visible": {
                            borderRadius: "50%",
                            outline: `2px solid ${green}`,
                            outlineOffset: 2,
                        },
                    }}
                >
                    <HugeiconsIcon
                        icon={ArrowLeft02Icon}
                        size={24}
                        strokeWidth={1.8}
                    />
                </Box>
                <Box
                    component="h1"
                    sx={{
                        color: textBase,
                        fontFamily: '"Inter Variable", Inter, sans-serif',
                        fontSize: 18,
                        fontWeight: 700,
                        justifySelf: "center",
                        lineHeight: "24px",
                        m: 0,
                    }}
                >
                    {title}
                </Box>
                <Box />
            </Box>
            {children}
        </Box>
    </Box>
);

export const EditProfilePhotoScreen: React.FC<EditProfilePhotoScreenProps> = ({
    avatarFile,
    onBack,
    onSave,
    variant = "avatar",
}) => {
    const isCover = variant == "cover";
    const title = isCover ? "Edit cover photo" : "Edit profile photo";
    const inputAccept = isCover
        ? spaceCoverImageInputAccept
        : spaceAvatarImageInputAccept;
    const imageErrorMessage = isCover
        ? spaceCoverImageErrorMessage
        : spaceAvatarImageErrorMessage;
    const [avatarCropImage, setAvatarCropImage] =
        useState<AvatarCropImage | null>(null);
    const [avatarCrop, setAvatarCrop] = useState<Point>({ x: 0, y: 0 });
    const [avatarCropPixels, setAvatarCropPixels] = useState<Area | null>(null);
    const [avatarError, setAvatarError] = useState<string>();
    const [avatarZoom, setAvatarZoom] = useState(1);
    const [isApplyingAvatarCrop, setIsApplyingAvatarCrop] = useState(false);
    const [isPreparingAvatar, setIsPreparingAvatar] = useState(true);
    const avatarCropUrlRef = useRef<string | null>(null);
    const avatarSelectionIDRef = useRef(0);
    const fileInputRef = useRef<HTMLInputElement | null>(null);

    useEffect(
        () => () => {
            if (avatarCropUrlRef.current) {
                URL.revokeObjectURL(avatarCropUrlRef.current);
            }
        },
        [],
    );

    const prepareSelectedAvatar = React.useCallback(
        async (file: File, selectionID: number) => {
            setIsPreparingAvatar(true);
            if (avatarCropUrlRef.current) {
                URL.revokeObjectURL(avatarCropUrlRef.current);
                avatarCropUrlRef.current = null;
            }
            setAvatarCropImage(null);
            setAvatarCropPixels(null);
            try {
                const cropImage = await (isCover
                    ? spaceCoverCropImageForFile(file)
                    : spaceAvatarCropImageForFile(file));
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
                console.error("Failed to prepare space profile image", error);
                setAvatarError(imageErrorMessage(error));
            } finally {
                if (avatarSelectionIDRef.current == selectionID) {
                    setIsPreparingAvatar(false);
                }
            }
        },
        [imageErrorMessage, isCover],
    );

    useEffect(() => {
        const selectionID = avatarSelectionIDRef.current + 1;
        avatarSelectionIDRef.current = selectionID;
        setAvatarError(undefined);
        void prepareSelectedAvatar(avatarFile, selectionID);
    }, [avatarFile, prepareSelectedAvatar]);

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
        let avatarFile: File;
        try {
            const avatar = await (isCover
                ? prepareSpaceCoverImageFromCrop(
                      avatarCropImage.file,
                      avatarCropImage.url,
                      avatarCropPixels,
                  )
                : prepareSpaceAvatarImageFromCrop(
                      avatarCropImage.file,
                      avatarCropImage.url,
                      avatarCropPixels,
                  ));
            avatarFile = avatar.file;
        } catch (error) {
            console.error("Failed to crop space profile image", error);
            setAvatarError(imageErrorMessage(error));
            setIsApplyingAvatarCrop(false);
            return;
        }

        try {
            await onSave(avatarFile);
        } catch (error) {
            console.error("Failed to save space profile image", error);
            setAvatarError(
                error instanceof Error
                    ? error.message
                    : "Couldn't save your profile. Please try again.",
            );
            setIsApplyingAvatarCrop(false);
        }
    };

    const avatarFileInput = (
        <Box
            component="input"
            ref={fileInputRef}
            accept={inputAccept}
            onChange={handleAvatarChange}
            type="file"
            sx={{ display: "none" }}
        />
    );

    if (!avatarCropImage) {
        return (
            <>
                {avatarFileInput}
                <EditProfilePhotoShell onBack={onBack} title={title}>
                    <Box
                        sx={{
                            alignItems: "center",
                            display: "flex",
                            flex: 1,
                            flexDirection: "column",
                            justifyContent: "center",
                            px: 3,
                            textAlign: "center",
                        }}
                    >
                        {isPreparingAvatar ? (
                            <SpaceLoadingSpinner
                                ariaLabel={
                                    isCover
                                        ? "Preparing cover photo"
                                        : "Preparing profile photo"
                                }
                            />
                        ) : (
                            <>
                                {avatarError && (
                                    <Box
                                        role="alert"
                                        sx={{
                                            color: warning,
                                            fontFamily:
                                                '"Inter Variable", Inter, sans-serif',
                                            fontSize: 13,
                                            fontWeight: 500,
                                            lineHeight: "18px",
                                            maxWidth: 300,
                                        }}
                                    >
                                        {avatarError}
                                    </Box>
                                )}
                                <Box
                                    className="green-bg"
                                    component="button"
                                    type="button"
                                    onClick={() =>
                                        fileInputRef.current?.click()
                                    }
                                    sx={{
                                        alignItems: "center",
                                        bgcolor: green,
                                        border: 0,
                                        borderRadius: "20px",
                                        color: "white",
                                        cursor: "pointer",
                                        display: "flex",
                                        fontFamily:
                                            '"Inter Variable", Inter, sans-serif',
                                        fontSize: 14,
                                        fontWeight: 500,
                                        height: 44,
                                        justifyContent: "center",
                                        lineHeight: "20px",
                                        mt: avatarError ? 3 : 0,
                                        px: 2,
                                        width: "100%",
                                        "&:focus-visible": {
                                            outline: `2px solid ${green}`,
                                            outlineOffset: 3,
                                        },
                                        "&:hover": { bgcolor: "#07AE22" },
                                    }}
                                >
                                    Change picture
                                </Box>
                            </>
                        )}
                    </Box>
                </EditProfilePhotoShell>
            </>
        );
    }

    return (
        <>
            {avatarFileInput}
            <SpaceAvatarCropPage
                background={profileBackground}
                crop={avatarCrop}
                errorMessage={avatarError}
                headerVariant="app"
                imageURL={avatarCropImage.url}
                isDoneDisabled={!avatarCropPixels}
                isSaving={isApplyingAvatarCrop}
                onBack={onBack}
                onChooseAnother={() => fileInputRef.current?.click()}
                onCropChange={setAvatarCrop}
                onCropComplete={(_croppedArea, croppedAreaPixels) =>
                    setAvatarCropPixels(croppedAreaPixels)
                }
                onDone={() => void applyAvatarCrop()}
                onZoomChange={setAvatarZoom}
                aspect={isCover ? spaceProfileCoverAspectRatio : 1}
                cropShape={isCover ? "rect" : "round"}
                title={title}
                zoom={avatarZoom}
            />
        </>
    );
};

export const EditProfileCoverScreen: React.FC<EditProfileCoverScreenProps> = ({
    coverFile,
    onBack,
    onSave,
}) => (
    <EditProfilePhotoScreen
        avatarFile={coverFile}
        onBack={onBack}
        onSave={onSave}
        variant="cover"
    />
);
