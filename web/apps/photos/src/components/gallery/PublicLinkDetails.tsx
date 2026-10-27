import { ManagePublicShareOptions } from "@/components/collections/CollectionShare";
import { CoverPickerDialog } from "@/components/collections/CoverPickerDialog";
import { PublicLinkField } from "@/components/share/PublicLinkField";
import { usePublicLinkURL } from "@/components/utils/use-public-link-url";
import { Edit03Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    styled,
} from "@mui/material";
import type { LocalUser } from "ente-accounts/services/user";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import type { Collection, PublicURL } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import {
    removePublicLink,
    updateCollectionDetails,
} from "ente-new/photos/services/collection";
import { openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import { useState } from "react";
import type { RemotePullOpts } from ".";

interface PublicLinkDetailsProps {
    collection: Collection;
    fileCount: number;
    coverFile?: EnteFile;
    files: EnteFile[];
    user: LocalUser;
    setBlockingLoad: (value: boolean) => void;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

export const PublicLinkDetails = ({
    collection,
    fileCount,
    coverFile,
    files,
    user,
    setBlockingLoad,
    onRemotePull,
}: PublicLinkDetailsProps) => {
    const { onGenericError } = useBaseContext();
    const { show: showPickCoverPhoto, props: pickCoverPhotoVisibilityProps } =
        useModalVisibility();
    const { customDomain } = useSettingsSnapshot();
    const [removeLinkError, setRemoveLinkError] = useState("");
    const [shareState, setShareState] = useState({
        collection,
        publicURL: collection.publicURLs[0],
    });
    const publicURL =
        shareState.collection === collection
            ? shareState.publicURL
            : collection.publicURLs[0];
    const setPublicURL = (publicURL: PublicURL | undefined) =>
        setShareState({ collection, publicURL });
    const { resolvedURL, isLoading, error } = usePublicLinkURL(
        collection,
        publicURL,
        customDomain,
    );
    const canChangeCover =
        collection.owner.id === user.id &&
        files.length > 1 &&
        files.some((file) => file.metadata.fileType !== FileType.video);

    const updateCover = async (coverID: number) => {
        try {
            await updateCollectionDetails(collection, { coverID });
            await onRemotePull({
                silent: true,
                source: "update-link-cover",
                strict: true,
            });
            return true;
        } catch (e) {
            onGenericError(e);
            return false;
        }
    };

    const handleRemovePublicLink = async () => {
        setBlockingLoad(true);
        setRemoveLinkError("");
        try {
            await removePublicLink(collection);
            setPublicURL(undefined);
            void onRemotePull({ silent: true });
        } catch (e) {
            log.error("Failed to remove public link", e);
            setRemoveLinkError(t("generic_error"));
        } finally {
            setBlockingLoad(false);
        }
    };

    return (
        <Box
            sx={{
                display: "flex",
                flexDirection: "column",
                containerType: "inline-size",
                flex: 1,
                minHeight: 0,
                overflow: "auto",
                px: "24px",
                pt: { xs: "12px", md: 0 },
                pb: { xs: "24px", md: "36px" },
            }}
        >
            <Stack
                component="header"
                sx={{ minWidth: 0, minHeight: 54, gap: "2px", mb: "24px" }}
            >
                <Typography
                    component="h1"
                    noWrap
                    title={collection.name}
                    sx={{
                        fontFamily: '"Outfit Variable", Outfit, sans-serif',
                        fontSize: 24,
                        fontWeight: 600,
                        lineHeight: "32px",
                    }}
                >
                    {collection.name}
                </Typography>
                <Typography
                    sx={{
                        color: "text.muted",
                        fontSize: 14,
                        fontWeight: 500,
                        lineHeight: "20px",
                    }}
                >
                    {t("photos_count", { count: fileCount })}
                </Typography>
            </Stack>
            <Stack
                sx={{
                    display: "grid",
                    gridTemplateColumns: "minmax(0, 1fr)",
                    flex: 1,
                    gap: "28px",
                    alignContent: "start",
                    alignItems: "start",
                    "@container (min-width: 720px)": {
                        gridTemplateColumns: "minmax(0, 364px) minmax(0, 1fr)",
                        columnGap: "44px",
                    },
                }}
            >
                <Stack sx={{ width: "100%", maxWidth: 364, gap: "14px" }}>
                    <Box sx={{ position: "relative" }}>
                        <Box role="img" aria-label={collection.name}>
                            <ItemCard
                                key={`${collection.id}-${coverFile?.id ?? "empty"}`}
                                TileComponent={Cover}
                                coverFile={coverFile}
                            />
                        </Box>
                        {canChangeCover && (
                            <Tooltip title={t("set_cover")}>
                                <IconButton
                                    aria-label={t("set_cover")}
                                    onClick={showPickCoverPhoto}
                                    sx={{
                                        position: "absolute",
                                        top: 16,
                                        right: 16,
                                        width: 38,
                                        height: 38,
                                        p: "10px",
                                        borderRadius: "12px",
                                        bgcolor: "background.paper",
                                        color: "text.base",
                                        "&:hover": {
                                            bgcolor: "background.paper",
                                        },
                                    }}
                                >
                                    <HugeiconsIcon
                                        icon={Edit03Icon}
                                        size={18}
                                        strokeWidth={1.5}
                                    />
                                </IconButton>
                            </Tooltip>
                        )}
                    </Box>
                    <PublicLinkField
                        url={resolvedURL}
                        isLoading={isLoading}
                        error={!!error}
                    />
                    <Typography
                        sx={{
                            color: "text.muted",
                            fontSize: "11.5px",
                            fontWeight: 400,
                            lineHeight: 1.45,
                            letterSpacing: 0,
                        }}
                    >
                        {t("public_link_description")}
                    </Typography>
                    <FocusVisibleButton
                        color="secondary"
                        fullWidth
                        disabled={!resolvedURL}
                        onClick={() => {
                            if (resolvedURL) openURL(resolvedURL);
                        }}
                        sx={(theme) => ({
                            height: 52,
                            px: "24px",
                            py: "14px",
                            borderRadius: "20px",
                            fontSize: 14,
                            fontWeight: 500,
                            lineHeight: "20px",
                            letterSpacing: 0,
                            ...theme.applyStyles("light", {
                                bgcolor: "#EAEAEA",
                                "&:hover": { bgcolor: "secondary.hover" },
                            }),
                        })}
                    >
                        {t("open_album")}
                    </FocusVisibleButton>
                    {collection.owner.id === user.id && publicURL && (
                        <FocusVisibleButton
                            color="critical"
                            fullWidth
                            onClick={handleRemovePublicLink}
                            sx={{
                                height: 52,
                                bgcolor: "transparent",
                                color: "critical.main",
                                fontSize: 14,
                                fontWeight: 500,
                                textDecoration: "underline",
                                borderRadius: "20px",
                                "&:hover": { bgcolor: "fill.faintHover" },
                            }}
                        >
                            {t("remove_link")}
                        </FocusVisibleButton>
                    )}
                    {removeLinkError && (
                        <Typography
                            role="alert"
                            variant="small"
                            sx={{ color: "critical.main" }}
                        >
                            {removeLinkError}
                        </Typography>
                    )}
                </Stack>
                {collection.owner.id === user.id &&
                    publicURL &&
                    resolvedURL && (
                        <Box sx={{ minWidth: 0 }}>
                            <ManagePublicShareOptions
                                variant="inline"
                                {...{
                                    collection,
                                    publicURL,
                                    setPublicURL,
                                    resolvedURL,
                                    setBlockingLoad,
                                    onRemotePull,
                                }}
                            />
                        </Box>
                    )}
            </Stack>
            {canChangeCover && pickCoverPhotoVisibilityProps.open && (
                <CoverPickerDialog
                    {...pickCoverPhotoVisibilityProps}
                    collection={collection}
                    files={files}
                    currentCoverFile={coverFile}
                    canResetToDefault={
                        (collection.pubMagicMetadata?.data.coverID ?? 0) > 0
                    }
                    onUseSelectedPhoto={(file) => updateCover(file.id)}
                    onResetToDefault={() => updateCover(0)}
                />
            )}
        </Box>
    );
};

const Cover = styled("div")({
    position: "relative",
    width: "100%",
    aspectRatio: "1",
    borderRadius: 24,
    overflow: "hidden",
    "& > img": { width: "100%", height: "100%", objectFit: "cover" },
});
