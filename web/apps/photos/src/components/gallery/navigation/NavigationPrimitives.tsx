import { Link05Icon, PinIcon, StarIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArchiveIcon from "@mui/icons-material/Archive";
import CloseIcon from "@mui/icons-material/Close";
import PeopleIcon from "@mui/icons-material/People";
import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    ButtonBase,
    Drawer,
    IconButton,
    InputBase,
    Stack,
    Typography,
    styled,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { ItemCard } from "ente-new/photos/components/Tiles";
import type {
    CollectionSummary,
    CollectionSummaryAttribute,
} from "ente-new/photos/services/collection-summary";
import { t } from "i18next";
import React, { useId, useRef, type ReactNode } from "react";

export interface GalleryBarPresentationProps {
    collapsed: boolean;
    mobileDrawerProps: ModalVisibilityProps;
}

interface NavigationFrameProps {
    title: ReactNode;
    actions: ReactNode;
    searchPlaceholder: string;
    searchQuery: string;
    setSearchQuery: (query: string) => void;
    mobileDrawerProps: ModalVisibilityProps;
    children: ReactNode;
}

export const NavigationFrame = ({
    title,
    actions,
    searchPlaceholder,
    searchQuery,
    setSearchQuery,
    mobileDrawerProps,
    children,
}: NavigationFrameProps) => {
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const titleID = useId();
    const searchInputRef = useRef<HTMLInputElement>(null);
    const navigation = (
        <Stack
            component="nav"
            aria-labelledby={titleID}
            onKeyDown={(event) => {
                if (event.key == "Escape" && searchQuery) {
                    event.stopPropagation();
                    setSearchQuery("");
                }
            }}
            sx={(theme) => ({
                "--gallery-navigation-surface": "#FFFFFF",
                "--gallery-navigation-hover":
                    "color-mix(in srgb, var(--mui-palette-text-base) 8%, var(--gallery-navigation-surface))",
                flexShrink: 0,
                width: "100%",
                height: "100%",
                minHeight: 0,
                px: mobile ? "12px" : "16px",
                py: mobile ? "14px" : 0,
                borderLeft: mobile ? 0 : "2px solid",
                borderColor: "rgba(224, 224, 224, 0.5)",
                gap: "16px",
                letterSpacing: 0,
                ...theme.applyStyles("dark", {
                    "--gallery-navigation-surface": "#212121",
                    borderColor: "rgba(62, 62, 62, 0.5)",
                }),
            })}
        >
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    flexShrink: 0,
                    height: 38,
                    gap: 0.5,
                    "& .MuiIconButton-root": {
                        width: 38,
                        height: 38,
                        borderRadius: "12px",
                        bgcolor: "var(--gallery-navigation-surface)",
                        "&:hover": {
                            bgcolor: "var(--gallery-navigation-hover)",
                        },
                    },
                }}
            >
                <Typography
                    component="h2"
                    id={titleID}
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        fontFamily: '"Outfit Variable", Outfit, sans-serif',
                        fontSize: mobile ? 20 : 24,
                        fontWeight: 600,
                        lineHeight: mobile ? "26px" : "32px",
                    }}
                >
                    {title}
                </Typography>
                {actions}
                {mobile && (
                    <IconButton
                        aria-label={t("close")}
                        onClick={mobileDrawerProps.onClose}
                    >
                        <CloseIcon sx={{ fontSize: 20 }} />
                    </IconButton>
                )}
            </Stack>
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    flexShrink: 0,
                    display: "flex",
                    height: 52,
                    gap: "10px",
                    px: "16px",
                    borderRadius: "12px",
                    bgcolor: "var(--gallery-navigation-surface)",
                    border: "1px solid",
                    borderColor: "stroke.faint",
                    "&:focus-within": {
                        outline: "1px solid",
                        outlineColor: "stroke.muted",
                        outlineOffset: -1,
                    },
                }}
            >
                <SearchIcon sx={{ fontSize: 18, color: "text.muted" }} />
                <InputBase
                    inputRef={searchInputRef}
                    fullWidth
                    placeholder={searchPlaceholder}
                    inputProps={{ "aria-label": searchPlaceholder }}
                    value={searchQuery}
                    onChange={(event) => setSearchQuery(event.target.value)}
                    sx={{
                        fontSize: mobile ? 13 : 14,
                        fontWeight: 500,
                        color: "text.base",
                        "& input::placeholder": {
                            color: "text.muted",
                            opacity: 1,
                        },
                    }}
                />
                {searchQuery && (
                    <IconButton
                        aria-label={t("clear_search")}
                        onClick={() => {
                            setSearchQuery("");
                            searchInputRef.current?.focus();
                        }}
                        size="small"
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                )}
            </Stack>
            {children}
        </Stack>
    );

    return mobile ? (
        <Drawer
            {...mobileDrawerProps}
            anchor="left"
            slotProps={{
                transition: { appear: true },
                backdrop: { sx: { bgcolor: "rgba(0,0,0,0.4)" } },
                paper: {
                    role: "dialog",
                    "aria-modal": true,
                    "aria-labelledby": titleID,
                    inert: !mobileDrawerProps.open,
                    sx: (theme) => ({
                        width: "100%",
                        borderRadius: 0,
                        boxShadow: "none",
                        bgcolor: "#F4F4F4",
                        ...theme.applyStyles("dark", { bgcolor: "#161616" }),
                    }),
                },
            }}
        >
            {navigation}
        </Drawer>
    ) : (
        navigation
    );
};

export const NavigationEmptyState = () => (
    <Stack
        role="status"
        sx={{
            flex: 1,
            minHeight: 0,
            alignItems: "center",
            justifyContent: "safe center",
            gap: "12px",
            px: "16px",
            py: "24px",
            textAlign: "center",
            overflowY: "auto",
        }}
    >
        <Box
            component="img"
            src="/images/empty-state/no-matches.svg"
            alt=""
            draggable={false}
            sx={{ width: 112, height: "auto", flexShrink: 0 }}
        />
        <Typography
            sx={{
                color: "text.base",
                fontFamily: '"Outfit Variable", sans-serif',
                fontSize: 18,
                fontWeight: 600,
                lineHeight: "26px",
            }}
        >
            {t("no_results")}
        </Typography>
    </Stack>
);

interface CollectionBarCardProps {
    collectionSummary: CollectionSummary;
    indented: boolean;
    activeCollectionID: number | undefined;
    onSelectCollectionID: (collectionID: number) => void;
}

export const CollectionBarCard: React.FC<CollectionBarCardProps> = ({
    collectionSummary,
    indented,
    activeCollectionID,
    onSelectCollectionID,
}: CollectionBarCardProps) => (
    <BarCard
        aria-label={collectionSummary.name}
        aria-current={
            activeCollectionID === collectionSummary.id ? "true" : undefined
        }
        title={collectionSummary.name}
        onClick={() => onSelectCollectionID(collectionSummary.id)}
        sx={
            indented
                ? { marginInlineStart: "20px", width: "calc(100% - 20px)" }
                : undefined
        }
    >
        <Box aria-hidden sx={{ flexShrink: 0 }}>
            <ItemCard
                TileComponent={BarThumbnail}
                coverFile={collectionSummary.coverFile}
            />
        </Box>
        <CardText>{collectionSummary.name}</CardText>
        <CollectionBarCardIcon attributes={collectionSummary.attributes} />
    </BarCard>
);

export const CardText: React.FC<React.PropsWithChildren> = ({ children }) => (
    <Typography
        noWrap
        sx={(theme) => ({
            flex: 1,
            minWidth: 0,
            fontFamily: '"Inter Variable", Inter, sans-serif',
            fontSize: 14,
            fontWeight: 500,
            lineHeight: "20px",
            [theme.breakpoints.down("md")]: { fontSize: 13 },
        })}
    >
        {children}
    </Typography>
);

interface CollectionBarCardIconProps {
    attributes: Set<CollectionSummaryAttribute>;
}

const CollectionBarCardIcon: React.FC<CollectionBarCardIconProps> = ({
    attributes,
}) => (
    <CollectionBarCardIcon_ aria-hidden>
        {attributes.has("userFavorites") && (
            <HugeiconsIcon
                icon={StarIcon}
                size={16}
                fill="currentColor"
                aria-hidden
            />
        )}
        {(attributes.has("pinned") || attributes.has("shareePinned")) && (
            <HugeiconsIcon icon={PinIcon} size={14} />
        )}
        {attributes.has("shared") && !attributes.has("sharedOnlyViaLink") && (
            <PeopleIcon />
        )}
        {attributes.has("sharedViaLink") && (
            <HugeiconsIcon icon={Link05Icon} size={16} />
        )}
        {attributes.has("archived") && <ArchiveIcon sx={{ opacity: 0.48 }} />}
    </CollectionBarCardIcon_>
);

export const CollectionBarCardIcon_ = styled("span")`
    display: flex;
    flex-shrink: 0;
    margin-inline-start: auto;
    align-items: center;
    gap: 4px;
    color: #969696;
    & > .MuiSvgIcon-root {
        font-size: 16px;
    }
`;

export const BarCard = styled(ButtonBase)(({ theme }) => ({
    display: "flex",
    justifyContent: "flex-start",
    gap: "12px",
    width: "100%",
    height: 48,
    paddingInline: "16px 12px",
    borderRadius: "12px",
    color: theme.vars.palette.text.base,
    textAlign: "left",
    '&[aria-current="true"], &[aria-current="page"]': {
        backgroundColor: "var(--gallery-navigation-surface)",
    },
    "&:hover": { backgroundColor: "var(--gallery-navigation-hover)" },
    "&.Mui-focusVisible": {
        outline: "2px solid",
        outlineColor: theme.vars.palette.stroke.base,
        outlineOffset: -2,
    },
    [theme.breakpoints.down("md")]: { height: 44 },
}));

export const BarThumbnail = styled("div")({
    width: 24,
    height: 24,
    position: "relative",
    overflow: "hidden",
    borderRadius: "6px",
    "& > img": {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
    },
    "& .MuiSvgIcon-root": { fontSize: 18 },
});
