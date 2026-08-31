import { Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { GlobalStyles, keyframes, styled } from "@mui/material";
import { EnteLogo } from "ente-base/components/EnteLogo";
import { t } from "i18next";
import type React from "react";
import {
    authAboveMobileMediaQuery,
    authColorVariables,
    authDisplayFontFamily,
    authMobileMediaQuery,
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
                <BrandPanel
                    headline={t("photos_auth_headline")}
                    size="desktop"
                />
            </DesktopBrandSlot>
            <TabletBrandSlot>
                <BrandPanel
                    headline={t("photos_auth_headline")}
                    size="tablet"
                />
            </TabletBrandSlot>
            <MobileBrandSlot>
                <BrandPanel
                    headline={t("photos_auth_headline")}
                    size="mobile"
                />
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

const shellReveal = keyframes({
    from: { opacity: 0, transform: "translateY(18px)" },
    to: { opacity: 1, transform: "translateY(0)" },
});

const brandCopyReveal = keyframes({
    from: { opacity: 0, transform: "translateY(12px)" },
    to: { opacity: 1, transform: "translateY(0)" },
});

const illustrationReveal = keyframes({
    from: { opacity: 0, transform: "translateY(18px) scale(0.98)" },
    to: { opacity: 1, transform: "translateY(0) scale(1)" },
});

const cameraSparkle = keyframes({
    from: {
        opacity: 0,
        transform: "translate(-50%, -50%) scale(0) rotate(-20deg)",
    },
    "35%": {
        opacity: 1,
        transform: "translate(-50%, -50%) scale(1) rotate(0)",
    },
    "70%": {
        opacity: 0.85,
        transform: "translate(-50%, -50%) scale(0.72) rotate(24deg)",
    },
    to: {
        opacity: 0,
        transform: "translate(-50%, -50%) scale(1.3) rotate(45deg)",
    },
});

const brandCurvesDrift = keyframes({
    "0%, 100%": {
        backgroundPosition: "0 0, calc(50% - 6px) calc(50% + 4px), 0 0",
    },
    "50%": { backgroundPosition: "0 0, calc(50% + 6px) calc(50% - 4px), 0 0" },
});

const brandCopyAnimation = {
    animation: `${brandCopyReveal} 520ms cubic-bezier(0.22, 1, 0.36, 1) both`,
    "@media (prefers-reduced-motion: reduce)": { animation: "none" },
};

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
                    {t("photos_auth_subtitle")}
                </PanelSubtitle>
            )}
            {size === "desktop" && (
                <BulletList>
                    {[
                        t("photos_auth_free_storage"),
                        t("photos_auth_no_ads_no_spying"),
                        t("auth_independently_audited"),
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
    animation: `${shellReveal} 620ms cubic-bezier(0.22, 1, 0.36, 1) both`,
    ...theme.applyStyles("dark", { backgroundColor: "#252525" }),
    "@media (prefers-reduced-motion: reduce)": { animation: "none" },
    [authAboveMobileMediaQuery]: { borderRadius: "24px" },
    "@media (min-width: 1024px)": {
        width: "1032px",
        height: "min(780px, 100%)",
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
    padding: "40px 24px 24px",
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
    [authMobileMediaQuery]: { display: "none" },
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
    [authMobileMediaQuery]: { flexGrow: 1 },
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
    backgroundPosition: "0 0, center, 0 0",
    backgroundSize: "auto, cover, auto",
    animation: `${brandCurvesDrift} 20s ease-in-out infinite`,
    "@media (prefers-reduced-motion: reduce)": { animation: "none" },
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
    ...brandCopyAnimation,
    animationDelay: "80ms",
}));

const PanelSubtitle = styled("p", {
    shouldForwardProp: (prop) => prop !== "size",
})<{ size: BrandPanelProps["size"] }>(({ size }) => ({
    margin: 0,
    marginTop: size === "desktop" ? "14px" : "10px",
    fontSize: size === "desktop" ? "20px" : "17px",
    fontWeight: 500,
    lineHeight: size === "desktop" ? "28px" : "24px",
    color: "rgba(255, 255, 255, 0.88)",
    ...brandCopyAnimation,
    animationDelay: "170ms",
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
    fontWeight: 500,
    lineHeight: "24px",
    ...brandCopyAnimation,
    "&:nth-of-type(1)": { animationDelay: "280ms" },
    "&:nth-of-type(2)": { animationDelay: "350ms" },
    "&:nth-of-type(3)": { animationDelay: "420ms" },
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
    position: "relative",
    overflow: "hidden",
    zIndex: 0,
    ...(size !== "tablet" && {
        animation: `${illustrationReveal} 500ms cubic-bezier(0.22, 1, 0.36, 1) ${size === "desktop" ? "840ms" : "130ms"} both`,
        "@media (prefers-reduced-motion: reduce)": { animation: "none" },
    }),
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
    "&::after": {
        content: '""',
        width:
            size === "desktop" ? "34px" : size === "tablet" ? "26px" : "20px",
        aspectRatio: "1",
        position: "absolute",
        left: "67%",
        top: size === "desktop" ? "59%" : "57%",
        zIndex: 1,
        pointerEvents: "none",
        backgroundColor: "#fff",
        clipPath:
            "polygon(50% 0%, 59% 39%, 100% 50%, 59% 61%, 50% 100%, 41% 61%, 0% 50%, 41% 39%)",
        filter: "drop-shadow(0 0 7px rgba(255, 245, 168, 0.95))",
        animation: `${cameraSparkle} 520ms ease-out ${size === "desktop" ? "1400ms" : size === "tablet" ? "740ms" : "690ms"} both`,
        "@media (prefers-reduced-motion: reduce)": { display: "none" },
    },
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
