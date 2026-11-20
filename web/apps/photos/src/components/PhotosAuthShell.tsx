import { AuthPageShell } from "ente-accounts/components/auth/AuthPageShell";
import type { AuthPresentationConfig } from "ente-accounts/components/auth/styles";
import { isDesktop } from "ente-base/app";
import { RiveIllustration } from "ente-base/components/RiveIllustration";
import { t } from "i18next";
import type React from "react";

interface PhotosAuthShellProps extends React.PropsWithChildren {
    contentWidth?: 400 | 420;
    isPlanSelection?: boolean;
}

const photosAuthTheme: AuthPresentationConfig = {
    primary: "#08c225",
    primaryHover: "#069d1e",
    primaryActive: "#057c18",
    focus: "#08c225",
    focusDark: "#08c225",
    link: "#08c225",
    linkDark: "#08c225",
    termsLink: "#08c225",
    termsLinkDark: "#08c225",
    passwordMessage: "#000",
    passwordMessageDark: "#fff",
    textDisabledDark: "#4d4d4d",
    wideGamutPrimary: "color(display-p3 0.03137 0.76078 0.1451)",
    brandBackdrop: "/images/auth-onboarding-doodle.svg",
    mobileBrandHeight: 196,
    illustrationHeights: { desktop: 219, tablet: 172, mobile: 127, wide: 249 },
};

const planSelectionTheme: AuthPresentationConfig = {
    ...photosAuthTheme,
    lightContentBackground: "#f4f4f4",
    darkContentBackground: "#171717",
};

export function PhotosAuthShell({
    children,
    contentWidth,
    isPlanSelection,
}: PhotosAuthShellProps): React.JSX.Element {
    return (
        <AuthPageShell
            brand={{
                headline: t("photos_auth_headline"),
                subtitle: t("photos_auth_subtitle"),
                bullets: [
                    t("photos_auth_free_storage"),
                    t("photos_auth_no_ads_no_spying"),
                    t("auth_independently_audited"),
                ],
            }}
            presentationConfig={
                isPlanSelection ? planSelectionTheme : photosAuthTheme
            }
            contentWidth={contentWidth}
            contentLayout={isPlanSelection ? "content-scroll" : undefined}
            illustration={
                <RiveIllustration
                    src={
                        new URL(
                            "../assets/ente-login-ducky.riv",
                            import.meta.url,
                        )
                    }
                    stateMachine="Ducky"
                    fallback={
                        <img
                            src="/images/auth-ducky.svg"
                            alt=""
                            style={{
                                display: "block",
                                width: "100%",
                                height: 370,
                            }}
                        />
                    }
                />
            }
            viewportHeight={
                isDesktop
                    ? "calc(100svh - env(titlebar-area-height, 30px))"
                    : undefined
            }
        >
            {children}
        </AuthPageShell>
    );
}
