import CloudOffIcon from "@mui/icons-material/CloudOff";
import { CircularProgress, Stack, Typography } from "@mui/material";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { thumbnailGridPadding } from "ente-new/photos/components/utils/thumbnail-grid-layout";
import { t } from "i18next";
import type { ReactNode } from "react";
import { NavigationSlide } from "./NavigationSlide";
import { useNavigationContentMotion } from "./use-navigation-content-motion";

export interface GallerySectionPresentation {
    collapsed: boolean;
    mobile: boolean;
    mobileDrawerProps: ModalVisibilityProps;
    reduceMotion: boolean;
    isFirstLoad: boolean;
    isOffline: boolean;
}

export const GallerySectionLayout = ({
    presentation,
    navigation,
    fullBleed = false,
    children,
}: {
    presentation: GallerySectionPresentation;
    navigation?: ReactNode;
    fullBleed?: boolean;
    children: ReactNode;
}) => {
    const { collapsed, mobile, reduceMotion, isFirstLoad, isOffline } =
        presentation;
    const panelOpen = !!navigation && !collapsed;
    const contentRef = useNavigationContentMotion(
        `${mobile}-${panelOpen}`,
        reduceMotion,
    );

    return (
        <Stack
            sx={{
                flex: 1,
                minWidth: 0,
                minHeight: 0,
                flexDirection: { xs: "column", md: "row" },
            }}
        >
            {navigation && (
                <NavigationSlide
                    open={panelOpen}
                    width={328}
                    reduceMotion={reduceMotion}
                    disabled={mobile}
                >
                    {navigation}
                </NavigationSlide>
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
                        pt: fullBleed
                            ? 0
                            : { xs: `${thumbnailGridPadding}px`, md: "36px" },
                        px: fullBleed ? 0 : { xs: 0, md: "12px" },
                        "--mui-palette-background-default": "#FFFFFF",
                        bgcolor: "background.default",
                        borderRadius: "20px",
                        overflow: "hidden",
                        ...theme.applyStyles("dark", {
                            "--mui-palette-background-default": "#212121",
                        }),
                    })}
                >
                    {children}
                </Stack>
                {isFirstLoad && (
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
                )}
                {isOffline && (
                    <GalleryStatusMessage
                        icon={
                            <CloudOffIcon sx={{ fontSize: 16 }} aria-hidden />
                        }
                    >
                        {t("offline_message")}
                    </GalleryStatusMessage>
                )}
            </Stack>
        </Stack>
    );
};

const GalleryStatusMessage = ({
    icon,
    children,
}: {
    icon: ReactNode;
    children: ReactNode;
}) => (
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
