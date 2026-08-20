import { Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { GlobalStyles, styled } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { pt } from "ente-base/i18n";
import type React from "react";
import {
    authAboveMobileMediaQuery,
    authColorVariables,
    authDisplayFontFamily,
} from "./auth/styles";

interface PhotosAuthShellProps extends React.PropsWithChildren {
    contentWidth?: 400 | 420;
}

export const PhotosAuthShell: React.FC<PhotosAuthShellProps> = ({
    children,
    contentWidth = 400,
}) => (
    <PageRoot>
        <GlobalStyles styles={authColorVariables} />
        <FrameCurves />
        <PageCard>
            <DesktopBrandSlot>
                <BrandPanel headline={authHeadline} size="desktop" />
            </DesktopBrandSlot>
            <TabletBrandSlot>
                <BrandPanel headline={authHeadline} size="tablet" />
            </TabletBrandSlot>
            <MobileBrandSlot>
                <BrandPanel headline={authHeadline} size="mobile" />
            </MobileBrandSlot>
            <ContentSheet>
                <SheetHandle />
                <ContentColumn contentWidth={contentWidth}>
                    {children}
                </ContentColumn>
            </ContentSheet>
        </PageCard>
    </PageRoot>
);

const authHeadline = pt("Safe home for your photos");

interface BrandPanelProps {
    headline: string;
    size: "desktop" | "tablet" | "mobile";
}

const BrandPanel: React.FC<BrandPanelProps> = ({ headline, size }) => (
    <BrandPanelRoot size={size}>
        <Wordmark size={size}>
            <EnteLogo />
        </Wordmark>
        <PanelCopy size={size}>
            <PanelHeadline size={size}>{headline}</PanelHeadline>
            {size !== "mobile" && (
                <PanelSubtitle size={size}>
                    {pt("End-to-end encrypted. Cross-platform. Open-source.")}
                </PanelSubtitle>
            )}
            {size === "desktop" && (
                <BulletList>
                    {[
                        pt("10 GB free forever"),
                        pt("Stored in 3 locations"),
                        pt("Open source, independently audited"),
                    ].map((bullet) => (
                        <Bullet key={bullet}>
                            <CheckCircle aria-hidden="true">
                                <HugeiconsIcon
                                    icon={Tick02Icon}
                                    size={12}
                                    strokeWidth={3}
                                />
                            </CheckCircle>
                            <span>{bullet}</span>
                        </Bullet>
                    ))}
                </BulletList>
            )}
        </PanelCopy>
        <IllustrationClip size={size}>
            <img src="/images/auth-ducky.svg" alt="" />
        </IllustrationClip>
    </BrandPanelRoot>
);

const PageRoot = styled("main")(({ theme }) => ({
    width: "100%",
    height: "100svh",
    minHeight: "100svh",
    display: "flex",
    position: "relative",
    overflow: "hidden",
    boxSizing: "border-box",
    backgroundColor: "#f4f4f4",
    ...theme.applyStyles("dark", { backgroundColor: "#0a0a0a" }),
    [authAboveMobileMediaQuery]: { padding: "40px" },
    "@media (min-width: 1024px)": {
        padding: 0,
        alignItems: "center",
        justifyContent: "center",
    },
}));

const FrameCurves = styled("div")(({ theme }) => ({
    display: "none",
    opacity: 0.3,
    ...theme.applyStyles("dark", { opacity: 0.02 }),
    [authAboveMobileMediaQuery]: {
        display: "block",
        position: "absolute",
        inset: 0,
        backgroundImage: 'url("/images/auth-frame-curves.svg")',
        backgroundRepeat: "no-repeat",
        backgroundSize: "cover",
        backgroundPosition: "center",
        pointerEvents: "none",
    },
}));

const PageCard = styled("div")(({ theme }) => ({
    width: "100%",
    height: "100%",
    minHeight: 0,
    display: "flex",
    flexDirection: "column",
    position: "relative",
    overflow: "hidden",
    backgroundColor: "#fff",
    ...theme.applyStyles("dark", { backgroundColor: "#252525" }),
    [authAboveMobileMediaQuery]: { borderRadius: "24px" },
    "@media (min-width: 1024px)": {
        width: "1032px",
        height: "min(740px, 100%)",
        flexDirection: "row",
    },
    "@media (min-width: 1600px)": {
        width: "1240px",
        height: "min(900px, 100%)",
    },
}));

const DesktopBrandSlot = styled("div")({
    display: "none",
    "@media (min-width: 1024px)": {
        display: "block",
        flex: "0 0 440px",
        height: "100%",
    },
    "@media (min-width: 1600px)": { flexBasis: "496px" },
});

const TabletBrandSlot = styled("div")({
    display: "none",
    [`${authAboveMobileMediaQuery} and (max-width: 1023px)`]: {
        display: "block",
        // Grows with the copy when it wraps at narrow widths; the band's
        // 268px design height is enforced as a minimum by BrandPanelRoot.
        flex: "0 0 auto",
        position: "relative",
        overflow: "hidden",
    },
});

const MobileBrandSlot = styled("div")({
    display: "block",
    flex: "0 0 196px",
    minHeight: 0,
    position: "relative",
    overflow: "hidden",
    [authAboveMobileMediaQuery]: { display: "none" },
});

const ContentSheet = styled("section")(({ theme }) => ({
    flex: 1,
    minHeight: 0,
    marginTop: "-28px",
    padding: "12px 24px 24px",
    display: "flex",
    flexDirection: "column",
    gap: "24px",
    position: "relative",
    zIndex: 1,
    overflowY: "auto",
    boxSizing: "border-box",
    borderRadius: "24px 24px 0 0",
    backgroundColor: "#fff",
    ...theme.applyStyles("dark", { backgroundColor: "#252525" }),
    [authAboveMobileMediaQuery]: {
        marginTop: "-32px",
        padding: "16px 48px 48px",
    },
    "@media (min-width: 1024px)": {
        width: "592px",
        marginTop: 0,
        padding: "48px 96px",
        alignItems: "center",
        justifyContent: "center",
        borderRadius: 0,
    },
    "@media (min-width: 1600px)": { width: "744px", padding: "56px 172px" },
}));

const SheetHandle = styled("div")({
    width: "36px",
    height: "4px",
    flexShrink: 0,
    alignSelf: "center",
    borderRadius: "999px",
    backgroundColor: "var(--photos-auth-fill-active)",
    "@media (min-width: 1024px)": { display: "none" },
});

const ContentColumn = styled("div", {
    shouldForwardProp: (prop) => prop !== "contentWidth",
})<{ contentWidth: 400 | 420 }>(({ contentWidth }) => ({
    width: "100%",
    minHeight: "min-content",
    display: "flex",
    flexDirection: "column",
    gap: "24px",
    [authAboveMobileMediaQuery]: {
        width: "440px",
        maxWidth: "100%",
        marginBlock: "auto",
        alignSelf: "center",
    },
    "@media (min-width: 1024px)": { width: `${contentWidth}px` },
    "@media (min-width: 1600px)": { gap: "28px" },
}));

const BrandPanelRoot = styled("div", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    width: "100%",
    height: size === "tablet" ? "auto" : "100%",
    ...(size === "tablet" && { minHeight: "268px", rowGap: "24px" }),
    padding:
        size === "desktop"
            ? "44px"
            : size === "tablet"
              ? "40px 40px 60px"
              : "18px 16px 40px",
    display: "flex",
    flexDirection: "column",
    justifyContent: size === "desktop" ? "flex-start" : "space-between",
    position: "relative",
    overflow: "hidden",
    boxSizing: "border-box",
    color: "#fff",
    backgroundColor: "var(--photos-auth-primary)",
    backgroundImage: `url("/images/auth-surface-noise.svg"), url("/images/auth-frame-curves.svg"), url("${greenTileP3}")`,
    backgroundRepeat: "repeat, no-repeat, repeat",
    backgroundSize: "auto, cover, auto",
}));

/* 1x1 Display-P3 PNG tiled so the brand green renders in P3 on capable
   screens; the #08c225 background color is the sRGB fallback. */
const greenTileP3 =
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACXBIWXMAAAsTAAALEwEAmpwYAAABaWlDQ1BEaXNwbGF5IFAzAAB4nHWQvUvDUBTFT6tS0DqIDh0cMolD1NIKdnFoKxRFMFQFq1OafgltfCQpUnETVyn4H1jBWXCwiFRwcXAQRAcR3Zw6KbhoeN6XVNoi3sfl/Ticc7lcwBtQGSv2AijplpFMxKS11Lrke4OHnlOqZrKooiwK/v276/PR9d5PiFlNu3YQ2U9cl84ul3aeAlN//V3Vn8maGv3f1EGNGRbgkYmVbYsJ3iUeMWgp4qrgvMvHgtMunzuelWSc+JZY0gpqhrhJLKc79HwHl4plrbWD2N6f1VeXxRzqUcxhEyYYilBRgQQF4X/8044/ji1yV2BQLo8CLMpESRETssTz0KFhEjJxCEHqkLhz634PrfvJbW3vFZhtcM4v2tpCAzidoZPV29p4BBgaAG7qTDVUR+qh9uZywPsJMJgChu8os2HmwiF3e38M6Hvh/GMM8B0CdpXzryPO7RqFn4Er/QcXKWq8MSlPPgAAABBJREFUeAEBBQD6/wAIwiX/A7QB7/maltEAAAAASUVORK5CYII=";

const Wordmark = styled("div", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    width: size === "desktop" ? "83px" : size === "tablet" ? "77px" : "64px",
    height: size === "desktop" ? "26px" : size === "tablet" ? "24px" : "20px",
    flexShrink: 0,
    margin: size === "mobile" ? "8px 0 0 8px" : 0,
    lineHeight: 0,
    position: "relative",
    zIndex: 1,
    "& > svg": { width: "100%", height: "100%" },
}));

const PanelCopy = styled("div", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    marginTop: size === "desktop" ? "52px" : 0,
    marginLeft: size === "mobile" ? "8px" : 0,
    // On the tablet band the ducky is anchored to the right edge, so keep
    // the copy from running underneath it at narrow widths.
    ...(size === "tablet" && { maxWidth: "calc(100% - 245px)" }),
    position: "relative",
    zIndex: 1,
}));

const PanelHeadline = styled("h1", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    maxWidth:
        size === "desktop" ? "300px" : size === "tablet" ? "380px" : "188px",
    margin: 0,
    fontFamily: authDisplayFontFamily,
    fontSize: size === "desktop" ? "42px" : size === "tablet" ? "34px" : "26px",
    fontWeight: 600,
    lineHeight:
        size === "desktop" ? "50px" : size === "tablet" ? "42px" : "34px",
    letterSpacing: "-0.02em",
    textWrap: "pretty",
}));

const PanelSubtitle = styled("p", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    margin: 0,
    marginTop: size === "desktop" ? "14px" : "10px",
    fontSize: size === "desktop" ? "20px" : "17px",
    fontWeight: 400,
    lineHeight: size === "desktop" ? "28px" : "24px",
    color: "rgba(255, 255, 255, 0.88)",
}));

const BulletList = styled("ul")({
    margin: "34px 0 0",
    padding: 0,
    display: "flex",
    flexDirection: "column",
    gap: "14px",
    listStyle: "none",
});

const Bullet = styled("li")({
    display: "flex",
    alignItems: "center",
    gap: "12px",
    fontSize: "17px",
    fontWeight: 400,
    lineHeight: "24px",
});

const CheckCircle = styled("span")({
    width: "24px",
    height: "24px",
    flex: "0 0 24px",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: "50%",
    backgroundColor: "rgba(255, 255, 255, 0.14)",
});

const IllustrationClip = styled("div", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    width: size === "desktop" ? "313px" : size === "tablet" ? "237px" : "175px",
    height:
        size === "desktop" ? "219px" : size === "tablet" ? "172px" : "127px",
    flexShrink: 0,
    overflow: "hidden",
    zIndex: 0,
    ...(size === "desktop"
        ? {
              marginTop: "auto",
              alignSelf: "center",
              "@media (min-width: 1600px)": { width: "355px", height: "249px" },
          }
        : {
              position: "absolute",
              right: size === "tablet" ? "28px" : "-4px",
              // Sit clear of the content sheet, which overlaps the band's
              // bottom edge by 32px (tablet) / 28px (mobile).
              bottom: size === "tablet" ? "44px" : "38px",
          }),
    "& > img": {
        display: "block",
        width: "473.694px",
        height: "370px",
        transformOrigin: "top left",
        transform:
            size === "desktop"
                ? "scale(0.66)"
                : size === "tablet"
                  ? "scale(0.5)"
                  : "scale(0.37)",
        ...(size === "desktop" && {
            "@media (min-width: 1600px)": { transform: "scale(0.75)" },
        }),
    },
}));
