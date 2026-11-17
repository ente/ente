import { ArrowLeft01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import DoneIcon from "@mui/icons-material/Done";
import {
    Box,
    Divider,
    IconButton,
    Stack,
    styled,
    Tooltip,
    Typography,
    type DialogProps,
    type SvgIconProps,
} from "@mui/material";
import { SidebarDrawer } from "ente-base/components/mui/SidebarDrawer";
import { useClipboardCopy } from "ente-base/components/utils/hooks";
import type { RawExifTags } from "ente-gallery/services/exif";
import { t } from "i18next";

interface CopyButtonProps {
    text: string;
    size?: SvgIconProps["fontSize"];
}

export const CopyButton: React.FC<CopyButtonProps> = ({ text, size }) => {
    const [copied, handleClick] = useClipboardCopy(text);

    const Icon = copied ? DoneIcon : ContentCopyIcon;

    return (
        <Tooltip arrow open={copied} title={t("copied")}>
            <IconButton onClick={handleClick} color="secondary">
                <Icon fontSize={size} />
            </IconButton>
        </Tooltip>
    );
};

export const FileInfoSidebar = styled(
    (props: Pick<DialogProps, "open" | "onClose" | "children">) => (
        <SidebarDrawer
            {...props}
            maxWidth="425px"
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
        "--mui-palette-background-paper": "#FFFFFF",
        "--mui-palette-text-muted": "#666666",
        "--mui-palette-stroke-faint": "#EBEBEB",
        ...theme.applyStyles("dark", {
            "--mui-palette-background-paper": "#212121",
            "--mui-palette-text-muted": "#999999",
            "--mui-palette-stroke-faint": "#2A2A2A",
        }),
        backgroundColor: theme.vars.palette.background.paper,
        backgroundImage: "none",
        boxShadow: "none",
        border: 0,
        letterSpacing: 0,
        "& .MuiTypography-root, & .MuiButton-root, & .MuiInputBase-root": {
            letterSpacing: 0,
        },
        "& h2.MuiTypography-root": {
            fontFamily: '"Outfit Variable", Outfit, sans-serif',
        },
        "& .MuiIconButton-root": {
            width: 38,
            height: 38,
            padding: 9,
            flexShrink: 0,
            borderRadius: 12,
            "& > .MuiSvgIcon-root": { fontSize: 20 },
            "&:hover": {
                backgroundColor: `color-mix(in srgb, ${theme.vars.palette.text.base} 8%, ${theme.vars.palette.background.paper})`,
            },
        },
        "& .MuiIconButton-root.Mui-focusVisible": {
            outline: "1px solid #08C225",
            outlineOffset: 2,
        },
        display: "flex",
        flexDirection: "column",
        top: "calc(env(titlebar-area-height, 0px) + 11px)",
        right: "calc(env(safe-area-inset-right, 0px) + 11px)",
        bottom: "calc(env(safe-area-inset-bottom, 0px) + 11px)",
        width: "calc(100% - env(safe-area-inset-left, 0px) - env(safe-area-inset-right, 0px) - 22px)",
        height: "auto",
        borderRadius: 20,
        [theme.breakpoints.down("sm")]: {
            top: "calc(env(titlebar-area-height, 0px) + 8px)",
            right: "calc(env(safe-area-inset-right, 0px) + 8px)",
            bottom: "calc(env(safe-area-inset-bottom, 0px) + 8px)",
            width: "calc(100% - env(safe-area-inset-left, 0px) - env(safe-area-inset-right, 0px) - 16px)",
        },
    },
    ".MuiDrawer-paper > .MuiBox-root": {
        flex: 1,
        display: "flex",
        flexDirection: "column",
        padding: "0 20px",
        minWidth: 0,
        [theme.breakpoints.down("sm")]: {
            paddingInline: "16px",
            paddingBottom: "env(safe-area-inset-bottom, 0px)",
        },
    },
}));

interface InfoItemProps {
    icon: React.ReactNode;
    title?: string;
    caption?: React.ReactNode;
    captionVariant?: "mini" | "small";
    trailingButton?: React.ReactNode;
}

export const FileInfoHeader = styled(Stack)(({ theme }) => ({
    position: "sticky",
    top: 0,
    zIndex: 2,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    minHeight: 76,
    paddingBlock: 16,
    [theme.breakpoints.down("sm")]: { minHeight: 68, paddingBlock: 12 },
    flexShrink: 0,
    backgroundColor: theme.vars.palette.background.paper,
    "& .MuiIconButton-root": { color: theme.vars.palette.text.base },
}));
export const FileInfoSection: React.FC<
    React.PropsWithChildren<{ title: string }>
> = ({ title, children }) => (
    <Stack component="section" sx={{ gap: 2, minWidth: 0 }}>
        <Divider sx={{ borderColor: "stroke.faint" }} />
        <Typography
            component="h3"
            sx={{ fontSize: 18, lineHeight: "24px", fontWeight: 600 }}
        >
            {title}
        </Typography>
        {children}
    </Stack>
);
export const InfoItem: React.FC<React.PropsWithChildren<InfoItemProps>> = ({
    icon,
    title,
    caption,
    captionVariant = "mini",
    trailingButton,
    children,
}) => (
    <Stack
        direction="row"
        sx={{
            alignItems: "center",
            minHeight: 56,
            gap: "12px",
            p: "8px 0",
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
                    variant={captionVariant}
                    {...(typeof caption != "string" && { component: "div" })}
                    sx={{
                        color: "text.muted",
                        lineHeight:
                            captionVariant === "small" ? "20px" : "16px",
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
    width: 38,
    height: 38,
    flexShrink: 0,
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    color: theme.vars.palette.text.muted,
    "& > svg": { width: 20, height: 20, strokeWidth: 1.8 },
}));
interface RawExifProps {
    open: boolean;
    onClose: () => void;
    tags: RawExifTags | undefined;
    fileName?: string;
}

export const RawExif: React.FC<RawExifProps> = ({
    open,
    onClose,
    tags,
    fileName,
}) => {
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
                <IconButton aria-label={t("go_back")} onClick={onClose}>
                    <HugeiconsIcon icon={ArrowLeft01Icon} size={20} />
                </IconButton>
                <Typography
                    component="h2"
                    variant="h5"
                    sx={{ flex: 1, lineHeight: "28px" }}
                >
                    {t("exif")}
                </Typography>
                <CopyButton size="small" text={JSON.stringify(tags)} />
            </FileInfoHeader>
            <Stack sx={{ gap: 2.5, pb: 3 }}>
                {fileName && (
                    <Typography
                        variant="small"
                        sx={{ color: "text.muted", overflowWrap: "anywhere" }}
                    >
                        {fileName}
                    </Typography>
                )}
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
