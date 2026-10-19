import { PickCoverPhotoDialog } from "@/components/Collections/PickCoverPhotoDialog";
import { usePublicLinkURL } from "@/components/utils/use-public-link-url";
import { Copy01Icon, Edit03Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import DoneIcon from "@mui/icons-material/Done";
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
import { useClipboardCopy } from "ente-base/components/utils/hooks";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import type { Collection } from "ente-media/collection";
import type { EnteFile } from "ente-media/file";
import { FileType } from "ente-media/file-type";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { useSettingsSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { updateCollectionDetails } from "ente-new/photos/services/collection";
import { openURL } from "ente-new/photos/utils/web";
import { t } from "i18next";
import type { RemotePullOpts } from ".";

interface PublicLinkDetailsProps {
    collection: Collection;
    coverFile?: EnteFile;
    files: EnteFile[];
    user: LocalUser;
    onRemotePull: (opts?: RemotePullOpts) => Promise<void>;
}

export const PublicLinkDetails = ({
    collection,
    coverFile,
    files,
    user,
    onRemotePull,
}: PublicLinkDetailsProps) => {
    const { onGenericError } = useBaseContext();
    const { show: showPickCoverPhoto, props: pickCoverPhotoVisibilityProps } =
        useModalVisibility();
    const { customDomain } = useSettingsSnapshot();
    const { resolvedURL, isLoading, error } = usePublicLinkURL(
        collection,
        collection.publicURLs[0],
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

    return (
        <Box
            sx={{
                flex: 1,
                minHeight: 0,
                overflow: "auto",
                p: { xs: "24px", md: "36px" },
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
                                    "&:hover": { bgcolor: "background.paper" },
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
                <Stack
                    direction="row"
                    sx={(theme) => ({
                        alignItems: "center",
                        gap: "8px",
                        height: 52,
                        px: "16px",
                        borderRadius: "16px",
                        bgcolor: "fill.faint",
                        ...theme.applyStyles("light", { bgcolor: "#F4F4F4" }),
                    })}
                >
                    <Typography
                        component="span"
                        title={resolvedURL}
                        aria-live="polite"
                        sx={{
                            flex: 1,
                            minWidth: 0,
                            fontSize: 14,
                            fontWeight: 500,
                            lineHeight: "20px",
                            letterSpacing: 0,
                            overflow: "hidden",
                            textOverflow: "ellipsis",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {resolvedURL?.replace(/^https?:\/\//, "") ??
                            (error
                                ? t("generic_error")
                                : isLoading
                                  ? t("loading")
                                  : null)}
                    </Typography>
                    <CopyLinkButton
                        key={resolvedURL ?? "pending"}
                        url={resolvedURL}
                    />
                </Stack>
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
            </Stack>
            {canChangeCover && pickCoverPhotoVisibilityProps.open && (
                <PickCoverPhotoDialog
                    {...pickCoverPhotoVisibilityProps}
                    collection={collection}
                    files={files}
                    user={user}
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

const CopyLinkButton = ({ url }: { url: string | undefined }) => {
    const [copied, copy] = useClipboardCopy(url ?? "");
    const label = t(copied ? "copied" : "copy_link");
    return (
        <Tooltip title={label}>
            <span>
                <IconButton
                    aria-label={label}
                    disabled={!url}
                    onClick={copy}
                    sx={{
                        width: 36,
                        height: 36,
                        p: 0,
                        mr: "-6px",
                        borderRadius: "8px",
                    }}
                >
                    {copied ? (
                        <DoneIcon sx={{ fontSize: 24, color: "accent.main" }} />
                    ) : (
                        <HugeiconsIcon
                            icon={Copy01Icon}
                            size={24}
                            strokeWidth={1.5}
                        />
                    )}
                </IconButton>
            </span>
        </Tooltip>
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
