import { AuthPageShell } from "ente-accounts/components/auth/AuthPageShell";
import type { AuthPresentationConfig } from "ente-accounts/components/auth/styles";
import { t } from "i18next";
import type React from "react";

interface LockerAuthShellProps extends React.PropsWithChildren {
    contentWidth?: 400 | 420;
}

const lockerAuthTheme: AuthPresentationConfig = {
    primary: "#1071ff",
    primaryHover: "#0056cc",
    primaryActive: "#004db8",
    focus: "#1071ff",
    focusDark: "#1071ff",
    link: "#1071ff",
    linkDark: "#1071ff",
    termsLink: "#1071ff",
    termsLinkDark: "#1071ff",
    passwordMessage: "#000",
    passwordMessageDark: "#fff",
    textDisabledDark: "#4d4d4d",
    wideGamutPrimary: "color(display-p3 0.0627 0.4431 1)",
    mobileBrandHeight: 232,
    illustrationHeights: { desktop: 219, tablet: 172, mobile: 127, wide: 249 },
};

export function LockerAuthShell({
    children,
    contentWidth,
}: LockerAuthShellProps): React.JSX.Element {
    return (
        <AuthPageShell
            brand={{
                headline: t("locker_auth_headline"),
                subtitle: t("photos_auth_subtitle"),
                bullets: [
                    t("locker_auth_free_files"),
                    t("photos_auth_no_ads_no_spying"),
                    t("auth_independently_audited"),
                ],
            }}
            presentationConfig={lockerAuthTheme}
            contentWidth={contentWidth}
        >
            {children}
        </AuthPageShell>
    );
}
