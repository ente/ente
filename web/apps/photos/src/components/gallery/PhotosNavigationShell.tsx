import { CreateAlbumDialog } from "@/components/collections/CreateAlbumDialog";
import { SearchBar, type SearchBarProps } from "@/components/SearchBar";
import { useIsOffline } from "@/components/utils/use-is-offline";
import { uploadManager } from "@/services/upload-manager";
import {
    DashboardSquare01Icon,
    Home01Icon,
    Link04Icon,
    Location01Icon,
    Settings01Icon,
    Upload01Icon,
    User02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CloudOffIcon from "@mui/icons-material/CloudOff";
import {
    Box,
    CircularProgress,
    Stack,
    SvgIcon,
    Tooltip,
    Typography,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { EnteLogo, EnteLogoBox } from "ente-base/components/EnteLogo";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { NavbarBase } from "ente-base/components/Navbar";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { ut } from "ente-base/i18n";
import { thumbnailGridPadding } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { isMLSupported } from "ente-new/photos/services/ml";
import { t } from "i18next";
import { useCallback, useEffect, useState, type ReactNode } from "react";

import type { RemotePullOpts } from ".";
import {
    GalleryBarImpl,
    type GalleryBarImplProps,
    type GalleryBarPresentationProps,
} from "./BarImpl";
import { NavigationSlide } from "./NavigationSlide";
import type { GalleryBarMode } from "./reducer";
import { useNavigationContentMotion } from "./use-navigation-content-motion";

type GalleryNavigation = Omit<
    GalleryBarImplProps,
    | keyof GalleryBarPresentationProps
    | "mode"
    | "onCreateAlbum"
    | "onSelectPerson"
> & { onRemotePull: (opts?: RemotePullOpts) => Promise<void> };

type PhotosNavigationShellProps = SearchBarProps & {
    onSidebar: () => void;
    onUpload: () => void;
    onHome: () => void;
    onShowMap: () => void;
    isMapView: boolean;
    isMapSelected: boolean;
    mode: GalleryBarMode;
    onChangeMode: (mode: GalleryBarMode) => boolean;
};

export const PhotosNavigationShell: React.FC<
    React.PropsWithChildren<
        PhotosNavigationShellProps & {
            isFirstLoad: boolean;
            alternateHeader: ReactNode;
            galleryNavigation: GalleryNavigation | undefined;
        }
    >
> = ({
    isFirstLoad,
    alternateHeader,
    galleryNavigation,
    children,
    ...props
}) => {
    const isOffline = useIsOffline();
    const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const [railOpen, setRailOpen] = useState(true);
    const [navigationCollapsed, setNavigationCollapsed] = useState(false);
    const toggleRail = () => setRailOpen((open) => !open);
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const panelOpen =
        railOpen &&
        !!galleryNavigation &&
        !props.isInSearchMode &&
        !navigationCollapsed;
    const contentRef = useNavigationContentMotion(
        `${mobile}-${panelOpen}-${railOpen}`,
        reduceMotion,
    );
    const { show: showMobileNavigation, props: mobileDrawerProps } =
        useModalVisibility();
    const { onClose: closeMobileNavigation } = mobileDrawerProps;
    const { onSelectCollectionID } = galleryNavigation ?? {};
    const { onSelectPerson } = props;
    const selectCollection = useCallback(
        (id: number) => {
            onSelectCollectionID?.(id);
            closeMobileNavigation();
        },
        [onSelectCollectionID, closeMobileNavigation],
    );
    const selectPerson = useCallback(
        (id: string) => {
            onSelectPerson(id);
            closeMobileNavigation();
        },
        [onSelectPerson, closeMobileNavigation],
    );
    const { show: showAlbumNameInput, props: albumNameInputVisibilityProps } =
        useModalVisibility();
    const [createInHiddenSection, setCreateInHiddenSection] = useState(false);
    const openAlbumCreation = () => {
        setCreateInHiddenSection(props.mode == "hidden-albums");
        showAlbumNameInput();
    };
    useEffect(() => {
        setNavigationCollapsed(false);
    }, [props.mode, props.isInSearchMode]);
    useEffect(() => {
        if (!mobile) closeMobileNavigation();
    }, [mobile, closeMobileNavigation]);
    const handleChangeMode = (mode: GalleryBarMode) => {
        if (mode == "people" && !mobile) {
            closeMobileNavigation();
            props.onChangeMode(mode);
            return;
        }
        const reopeningSection =
            mobile &&
            mode == "albums" &&
            galleryNavigation &&
            !props.isInSearchMode &&
            (props.mode == "hidden-albums" || props.mode == "archive-albums");
        if (
            galleryNavigation &&
            !props.isInSearchMode &&
            ((props.mode == mode &&
                galleryNavigation.activeCollectionID !=
                    PseudoCollectionID.all) ||
                reopeningSection)
        ) {
            if (mobile) {
                if (mobileDrawerProps.open) closeMobileNavigation();
                else showMobileNavigation();
            } else {
                setNavigationCollapsed((collapsed) => !collapsed);
            }
            return;
        }
        if (!props.onChangeMode(mode)) return;
        setNavigationCollapsed(false);
        if (mobile) showMobileNavigation();
    };
    const galleryBar = galleryNavigation && (
        <GalleryBarImpl
            {...galleryNavigation}
            mode={props.mode}
            collapsed={!panelOpen}
            mobileDrawerProps={mobileDrawerProps}
            onCreateAlbum={openAlbumCreation}
            onSelectCollectionID={selectCollection}
            onSelectPerson={selectPerson}
        />
    );
    return (
        <Stack
            sx={(theme) => ({
                flex: 1,
                minWidth: 0,
                minHeight: 0,
                bgcolor: "#F4F4F4",
                ...theme.applyStyles("light", {
                    "& > :first-child .MuiButton-colorSecondary": {
                        "--mui-palette-secondary-main": "#FFFFFF",
                    },
                }),
                ...theme.applyStyles("dark", { bgcolor: "#161616" }),
            })}
        >
            <NavbarBase
                sx={{
                    pl: { xs: "9px", sm: "16px" },
                    pr: { xs: "12px", sm: "16px" },
                    flexBasis: { xs: "60px", sm: "76px" },
                    borderBottom: "none",
                }}
            >
                {alternateHeader ?? (
                    <NormalHeaderContents
                        onUpload={props.onUpload}
                        {...{ railOpen, toggleRail }}
                    />
                )}
            </NavbarBase>
            <Stack
                direction="row"
                sx={{
                    flex: 1,
                    minWidth: 0,
                    minHeight: 0,
                    overflow: "clip",
                    p: {
                        xs: railOpen ? "0 8px 8px 0" : "0 8px 8px",
                        sm: railOpen ? "0 11px 11px 0" : "0 11px 11px",
                    },
                }}
            >
                <NavigationSlide
                    open={railOpen}
                    width={{ xs: 56, sm: 72 }}
                    reduceMotion={reduceMotion}
                    rail
                >
                    <Box
                        component="nav"
                        sx={(theme) => ({
                            display: "flex",
                            height: "100%",
                            flexDirection: "column",
                            alignItems: "center",
                            flexShrink: 0,
                            width: "100%",
                            px: { xs: "9px", sm: "14px" },
                            gap: "12px",
                            ...theme.applyStyles("light", {
                                "& .MuiButton-colorSecondary": {
                                    "--mui-palette-secondary-main": "#FFFFFF",
                                },
                            }),
                        })}
                    >
                        {alternateHeader == null && (
                            <NormalNavigationRail
                                {...props}
                                isHome={
                                    !props.isMapSelected &&
                                    props.mode == "albums" &&
                                    !props.isInSearchMode &&
                                    galleryNavigation?.activeCollectionID ==
                                        PseudoCollectionID.all
                                }
                                onChangeMode={handleChangeMode}
                                opensDialog={mobile}
                                navigationOpen={
                                    !props.isMapSelected &&
                                    !!galleryNavigation &&
                                    (mobile
                                        ? mobileDrawerProps.open
                                        : !navigationCollapsed)
                                }
                            />
                        )}
                    </Box>
                </NavigationSlide>
                <Stack
                    sx={{
                        flex: 1,
                        minWidth: 0,
                        minHeight: 0,
                        flexDirection: { xs: "column", md: "row" },
                    }}
                >
                    {galleryNavigation && !props.isInSearchMode && (
                        <>
                            <NavigationSlide
                                open={panelOpen}
                                width={328}
                                reduceMotion={reduceMotion}
                                disabled={mobile}
                            >
                                {galleryBar}
                            </NavigationSlide>
                            <CreateAlbumDialog
                                {...albumNameInputVisibilityProps}
                                isHidden={createInHiddenSection}
                                onRemotePull={galleryNavigation.onRemotePull}
                                onSelectCollectionID={selectCollection}
                            />
                        </>
                    )}
                    <Stack
                        ref={contentRef}
                        sx={{ flex: 1, minWidth: 0, minHeight: 0, gap: "8px" }}
                    >
                        <Stack
                            sx={(theme) => ({
                                flex: 1,
                                minWidth: 0,
                                minHeight: 0,
                                pt: props.isMapView
                                    ? 0
                                    : {
                                          xs: `${thumbnailGridPadding}px`,
                                          md: "36px",
                                      },
                                px: props.isMapView ? 0 : { xs: 0, md: "12px" },
                                "--mui-palette-background-default": "#FFFFFF",
                                bgcolor: "background.default",
                                borderRadius: "20px",
                                overflow: "hidden",
                                ...theme.applyStyles("dark", {
                                    "--mui-palette-background-default":
                                        "#212121",
                                }),
                            })}
                        >
                            {children}
                        </Stack>
                        {isFirstLoad && <FirstLoadMessage />}
                        {isOffline && <OfflineMessage />}
                    </Stack>
                </Stack>
            </Stack>
        </Stack>
    );
};

const NormalHeaderContents: React.FC<
    Pick<PhotosNavigationShellProps, "onUpload"> & {
        railOpen: boolean;
        toggleRail: () => void;
    }
> = ({ onUpload, railOpen, toggleRail }) => {
    return (
        <Box
            sx={{
                position: "relative",
                display: "flex",
                alignItems: "center",
                flex: 1,
            }}
        >
            <Tooltip title={railOpen ? ut("Hide sidebar") : ut("Show sidebar")}>
                <FocusVisibleButton
                    color="secondary"
                    aria-label={
                        railOpen ? ut("Hide sidebar") : ut("Show sidebar")
                    }
                    aria-expanded={railOpen}
                    onClick={toggleRail}
                    sx={{
                        minWidth: 0,
                        width: 38,
                        height: 38,
                        p: 0,
                        borderRadius: "12px",
                    }}
                >
                    <SvgIcon
                        sx={{ fontSize: 20, fill: "none" }}
                        stroke="currentColor"
                        strokeWidth="1.8"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                    >
                        <rect x="3" y="4" width="18" height="16" rx="3" />
                        <path
                            d={
                                railOpen
                                    ? "M9 4v16M15 10l-2 2 2 2"
                                    : "M9 4v16M13 10l2 2-2 2"
                            }
                        />
                    </SvgIcon>
                </FocusVisibleButton>
            </Tooltip>
            <EnteLogoBox
                sx={{
                    position: "absolute",
                    left: "50%",
                    transform: "translateX(-50%)",
                    pointerEvents: "none",
                    "& svg": { height: { xs: "18px", sm: "20px" } },
                }}
            >
                <EnteLogo height={15} />
            </EnteLogoBox>
            <Box sx={{ flex: 1 }} />
            <UploadButton onClick={onUpload} />
        </Box>
    );
};

const NormalNavigationRail: React.FC<
    Omit<
        PhotosNavigationShellProps,
        "onUpload" | "onChangeMode" | "isMapView"
    > & {
        onChangeMode: (mode: GalleryBarMode) => void;
        isHome: boolean;
        opensDialog: boolean;
        navigationOpen: boolean;
    }
> = ({
    onSidebar,
    onHome,
    onShowMap,
    isMapSelected,
    mode,
    onChangeMode,
    isHome,
    opensDialog,
    navigationOpen,
    ...props
}) => (
    <>
        <HomeButton onClick={onHome} selected={isHome} />
        <SearchBar {...props} />
        <Box
            aria-hidden
            sx={(theme) => ({
                width: 38,
                height: "2px",
                flexShrink: 0,
                opacity: 0.5,
                bgcolor: "#E0E0E0",
                ...theme.applyStyles("dark", { bgcolor: "#3E3E3E" }),
            })}
        />
        {(["albums", "people", "links"] as const).map((item) =>
            item == "people" && !isMLSupported ? null : (
                <Tooltip key={item} title={t(item)}>
                    <FocusVisibleButton
                        color="secondary"
                        aria-label={t(item)}
                        aria-pressed={
                            navigationOpen &&
                            !isHome &&
                            !props.isInSearchMode &&
                            (mode == item ||
                                (item == "albums" &&
                                    (mode == "hidden-albums" ||
                                        mode == "archive-albums")))
                        }
                        aria-haspopup={opensDialog ? "dialog" : undefined}
                        onClick={() => onChangeMode(item)}
                        sx={{
                            minWidth: 0,
                            width: 38,
                            height: 38,
                            flexShrink: 0,
                            p: 0,
                            borderRadius: "12px",
                            color: "text.base",
                            '&[aria-pressed="true"]': {
                                color: "#FFFFFF",
                                bgcolor: "accent.main",
                                "&:hover": { bgcolor: "accent.main" },
                            },
                        }}
                    >
                        <HugeiconsIcon
                            icon={
                                item == "albums"
                                    ? DashboardSquare01Icon
                                    : item == "links"
                                      ? Link04Icon
                                      : User02Icon
                            }
                            size={20}
                            strokeWidth={1.8}
                        />
                    </FocusVisibleButton>
                </Tooltip>
            ),
        )}
        <Tooltip title={t("map")}>
            <FocusVisibleButton
                color="secondary"
                aria-label={t("map")}
                aria-pressed={isMapSelected}
                onClick={onShowMap}
                sx={{
                    minWidth: 0,
                    width: 38,
                    height: 38,
                    flexShrink: 0,
                    p: 0,
                    borderRadius: "12px",
                    color: "text.base",
                    '&[aria-pressed="true"]': {
                        color: "#FFFFFF",
                        bgcolor: "accent.main",
                        "&:hover": { bgcolor: "accent.main" },
                    },
                }}
            >
                <HugeiconsIcon
                    icon={Location01Icon}
                    size={20}
                    strokeWidth={1.8}
                />
            </FocusVisibleButton>
        </Tooltip>
        <Box sx={{ flex: 1 }} />
        <Tooltip title={t("settings")}>
            <FocusVisibleButton
                color="secondary"
                aria-label={t("settings")}
                aria-haspopup="dialog"
                onClick={onSidebar}
                sx={{
                    minWidth: 0,
                    width: 38,
                    height: 38,
                    flexShrink: 0,
                    mb: "13px",
                    p: 0,
                    borderRadius: "12px",
                }}
            >
                <HugeiconsIcon
                    icon={Settings01Icon}
                    size={20}
                    strokeWidth={1.8}
                />
            </FocusVisibleButton>
        </Tooltip>
    </>
);

const HomeButton: React.FC<ButtonishProps & { selected: boolean }> = ({
    onClick,
    selected,
}) => (
    <Tooltip title={ut("Home")}>
        <FocusVisibleButton
            color="secondary"
            aria-label={ut("Home")}
            aria-pressed={selected}
            onClick={onClick}
            sx={{
                minWidth: 0,
                width: 38,
                height: 38,
                p: 0,
                borderRadius: "12px",
                color: "text.base",
                '&[aria-pressed="true"]': {
                    color: "#FFFFFF",
                    bgcolor: "accent.main",
                    "&:hover": { bgcolor: "accent.main" },
                },
            }}
        >
            <HugeiconsIcon icon={Home01Icon} size={20} strokeWidth={1.8} />
        </FocusVisibleButton>
    </Tooltip>
);

const UploadButton: React.FC<ButtonishProps> = ({ onClick }) => {
    const disabled = uploadManager.isUploadInProgress();
    const isSmallWidth = useIsSmallWidth();

    const icon = (
        <HugeiconsIcon icon={Upload01Icon} size={20} strokeWidth={1.8} />
    );

    return (
        <>
            {isSmallWidth ? (
                <FocusVisibleButton
                    color="secondary"
                    aria-label={t("upload")}
                    sx={{
                        minWidth: 0,
                        width: 38,
                        height: 38,
                        p: 0,
                        borderRadius: "12px",
                    }}
                    {...{ onClick, disabled }}
                >
                    {icon}
                </FocusVisibleButton>
            ) : (
                <FocusVisibleButton
                    color="secondary"
                    startIcon={icon}
                    sx={{
                        minWidth: "140px",
                        flexShrink: 0,
                        whiteSpace: "nowrap",
                        height: "52px",
                        p: "18px 24px",
                        borderRadius: "20px",
                        border: 0,
                        fontSize: "14px",
                        fontWeight: 600,
                        lineHeight: "20px",
                        gap: "8px",
                        "& .MuiButton-startIcon": { m: 0 },
                    }}
                    {...{ onClick, disabled }}
                >
                    {t("upload")}
                </FocusVisibleButton>
            )}
        </>
    );
};

const GalleryStatusMessage: React.FC<
    React.PropsWithChildren<{ icon: ReactNode }>
> = ({ icon, children }) => (
    <Stack
        direction="row"
        role="status"
        sx={{
            flexShrink: 0,
            alignItems: "center",
            justifyContent: "center",
            gap: 1.25,
            px: 1,
            py: 1.25,
            color: "text.muted",
            opacity: 0.65,
        }}
    >
        {icon}
        <Typography variant="small" sx={{ textAlign: "center" }}>
            {children}
        </Typography>
    </Stack>
);

const FirstLoadMessage: React.FC = () => (
    <GalleryStatusMessage
        icon={
            <CircularProgress
                size={12}
                thickness={5}
                color="inherit"
                aria-hidden
            />
        }
    >
        {t("initial_load_delay_warning")}
    </GalleryStatusMessage>
);

const OfflineMessage: React.FC = () => (
    <GalleryStatusMessage
        icon={<CloudOffIcon sx={{ fontSize: 16 }} aria-hidden />}
    >
        {t("offline_message")}
    </GalleryStatusMessage>
);
