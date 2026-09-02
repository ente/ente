import { AuthPageShell } from "ente-accounts/components/auth/AuthPageShell";
import type { AuthPresentationConfig } from "ente-accounts/components/auth/styles";
import { t } from "i18next";
import type React from "react";

interface AuthShellProps extends React.PropsWithChildren {
    contentWidth?: 400 | 420;
}

const authenticatorAuthTheme: AuthPresentationConfig = {
    primary: "#9610d6",
    primaryHover: "#8e0fcb",
    primaryActive: "#750ca8",
    focus: "#9610d6",
    focusDark: "#c76cff",
    link: "#000",
    linkDark: "#fff",
    termsLink: "#000",
    termsLinkDark: "#fff",
    passwordMessage: "#666",
    passwordMessageDark: "#999",
    textDisabledDark: "#808080",
    mobileBrandHeight: 196,
    illustrationHeights: { desktop: 245, tablet: 185, mobile: 137, wide: 278 },
};

export function AuthShell({
    children,
    contentWidth,
}: AuthShellProps): React.JSX.Element {
    return (
        <AuthPageShell
            brand={{
                headline: t("authenticator_auth_headline"),
                subtitle: t("photos_auth_subtitle"),
                bullets: [
                    t("authenticator_auth_free"),
                    t("photos_auth_no_ads_no_spying"),
                    t("auth_independently_audited"),
                ],
            }}
            presentationConfig={authenticatorAuthTheme}
            contentWidth={contentWidth}
        >
            {children}
        </AuthPageShell>
    );
}
