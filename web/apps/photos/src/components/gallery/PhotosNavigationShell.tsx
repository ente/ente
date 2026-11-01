import { SearchBar, type SearchBarProps } from "@/components/SearchBar";
import { Sidebar } from "@/components/sidebar/Sidebar";
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
import {
    Box,
    Stack,
    SvgIcon,
    Tooltip,
    useMediaQuery,
    useTheme,
} from "@mui/material";
import { EnteLogo, EnteLogoBox } from "ente-base/components/EnteLogo";
import { TranslucentLoadingOverlay } from "ente-base/components/loaders";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { NavbarBase } from "ente-base/components/Navbar";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import { useModalVisibility } from "ente-base/components/utils/modal";
import { ut } from "ente-base/i18n";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { isMLSupported } from "ente-new/photos/services/ml";
import type { SidebarActionID } from "ente-new/photos/services/search/types";
import { t } from "i18next";
import {
    useCallback,
    useEffect,
    useImperativeHandle,
    useState,
    type ReactNode,
} from "react";

import type { GallerySectionPresentation } from "./GallerySectionLayout";
import { NavigationSlide } from "./NavigationSlide";
import { usePhotosNavigation } from "./PhotosNavigationContext";
import type { GalleryBarMode } from "./reducer";

type PhotosNavigationShellProps = SearchBarProps & {
    onSidebar: () => void;
    onUpload: () => void;
    isMapView: boolean;
    isMapSelected: boolean;
    mode: GalleryBarMode;
};

export interface PhotosNavigationShellHandle {
    showSettings: (action?: SidebarActionID) => void;
}

export const PhotosNavigationShell: React.FC<
    Omit<PhotosNavigationShellProps, "isSettingsOpen" | "onSidebar"> & {
        ref?: React.Ref<PhotosNavigationShellHandle>;
        isFirstLoad: boolean;
        alternateHeader: ReactNode;
        navigationAvailable: boolean;
        activeCollectionID: number | undefined;
        children: (presentation: GallerySectionPresentation) => ReactNode;
        collectionNameByID: Map<number, string>;
        onAuthenticateUser: () => Promise<boolean>;
    }
> = ({
    ref,
    isFirstLoad,
    alternateHeader,
    navigationAvailable: hasNavigation,
    activeCollectionID,
    collectionNameByID,
    onAuthenticateUser,
    children,
    ...props
}) => {
    const { changeMode, showLibraryMap, showCleanupView } =
        usePhotosNavigation();
    const { show: showSidebar, props: sidebarVisibilityProps } =
        useModalVisibility();
    const [pendingSidebarAction, setPendingSidebarAction] =
        useState<SidebarActionID>();
    const [settingsLoading, setSettingsLoading] = useState(false);
    const showSettings = useCallback(
        (action?: SidebarActionID) => {
            setPendingSidebarAction(action);
            showSidebar();
        },
        [showSidebar],
    );
    const handleSidebarActionHandled = useCallback(
        () => setPendingSidebarAction(undefined),
        [],
    );
    useImperativeHandle(ref, () => ({ showSettings }), [showSettings]);
    const isOffline = useIsOffline();
    const reduceMotion = useMediaQuery("(prefers-reduced-motion: reduce)");
    const [navigationCollapsed, setNavigationCollapsed] = useState(false);
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const navigationAvailable = hasNavigation && !props.isInSearchMode;
    const panelOpen = navigationAvailable && !navigationCollapsed;
    const { show: showMobileNavigation, props: mobileDrawerProps } =
        useModalVisibility();
    const { onClose: closeMobileNavigation } = mobileDrawerProps;
    const navigationOpen =
        navigationAvailable && (mobile ? mobileDrawerProps.open : panelOpen);
    const toggleNavigation = () => {
        if (mobile) {
            if (mobileDrawerProps.open) closeMobileNavigation();
            else showMobileNavigation();
        } else {
            setNavigationCollapsed((collapsed) => !collapsed);
        }
    };
    useEffect(() => {
        setNavigationCollapsed(false);
    }, [props.mode, props.isInSearchMode, props.isMapSelected]);
    useEffect(() => {
        if (!mobile) closeMobileNavigation();
    }, [mobile, closeMobileNavigation]);
    const handleChangeMode = (mode: GalleryBarMode) => {
        if (mode == "people" && !mobile) {
            closeMobileNavigation();
            changeMode(mode);
            return;
        }
        const reopeningSection =
            mobile &&
            mode == "albums" &&
            hasNavigation &&
            !props.isInSearchMode &&
            (props.mode == "hidden-albums" || props.mode == "archive-albums");
        if (
            hasNavigation &&
            !props.isInSearchMode &&
            ((props.mode == mode &&
                activeCollectionID != PseudoCollectionID.all) ||
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
        if (!changeMode(mode)) return;
        setNavigationCollapsed(false);
        if (mobile) showMobileNavigation();
    };
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
                        {...{
                            navigationAvailable,
                            navigationOpen,
                            toggleNavigation,
                        }}
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
                    p: { xs: "0 8px 8px 0", sm: "0 11px 11px 0" },
                }}
            >
                <NavigationSlide
                    open
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
                                isSettingsOpen={sidebarVisibilityProps.open}
                                onSidebar={() => showSettings()}
                                onShowMap={() => {
                                    showLibraryMap();
                                    setNavigationCollapsed(false);
                                    if (mobile) showMobileNavigation();
                                }}
                                isHome={
                                    !props.isMapSelected &&
                                    props.mode == "albums" &&
                                    !props.isInSearchMode &&
                                    activeCollectionID == PseudoCollectionID.all
                                }
                                onChangeMode={handleChangeMode}
                                opensDialog={mobile}
                                navigationOpen={
                                    !props.isMapSelected &&
                                    hasNavigation &&
                                    (mobile
                                        ? mobileDrawerProps.open
                                        : !navigationCollapsed)
                                }
                            />
                        )}
                    </Box>
                </NavigationSlide>
                {children({
                    collapsed: !panelOpen,
                    mobile,
                    mobileDrawerProps,
                    reduceMotion,
                    isFirstLoad,
                    isOffline,
                })}
            </Stack>
            <Sidebar
                {...sidebarVisibilityProps}
                pendingAction={pendingSidebarAction}
                onActionHandled={handleSidebarActionHandled}
                onShowLargeFiles={() => showCleanupView("large-files")}
                onShowDuplicates={() => showCleanupView("duplicates")}
                collectionNameByID={collectionNameByID}
                onAuthenticateUser={onAuthenticateUser}
                setLoading={setSettingsLoading}
            />
            {settingsLoading && <TranslucentLoadingOverlay />}
        </Stack>
    );
};

const NormalHeaderContents: React.FC<
    Pick<PhotosNavigationShellProps, "onUpload"> & {
        navigationAvailable: boolean;
        navigationOpen: boolean;
        toggleNavigation: () => void;
    }
> = ({ onUpload, navigationAvailable, navigationOpen, toggleNavigation }) => {
    return (
        <Box
            sx={{
                position: "relative",
                display: "flex",
                alignItems: "center",
                flex: 1,
            }}
        >
            <Tooltip
                title={
                    !navigationAvailable
                        ? ""
                        : navigationOpen
                          ? ut("Hide navigation panel")
                          : ut("Show navigation panel")
                }
            >
                <FocusVisibleButton
                    color="secondary"
                    aria-label={
                        navigationOpen
                            ? ut("Hide navigation panel")
                            : ut("Show navigation panel")
                    }
                    aria-expanded={navigationOpen}
                    disabled={!navigationAvailable}
                    onClick={toggleNavigation}
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
                                navigationOpen
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
    Omit<PhotosNavigationShellProps, "onUpload" | "isMapView"> & {
        onChangeMode: (mode: GalleryBarMode) => void;
        onShowMap: () => void;
        isHome: boolean;
        opensDialog: boolean;
        navigationOpen: boolean;
    }
> = ({
    onSidebar,
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
        <HomeButton selected={isHome} />
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

const HomeButton: React.FC<{ selected: boolean }> = ({ selected }) => {
    const { goHome } = usePhotosNavigation();
    return (
        <Tooltip title={ut("Home")}>
            <FocusVisibleButton
                color="secondary"
                aria-label={ut("Home")}
                aria-pressed={selected}
                onClick={goHome}
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
};

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
