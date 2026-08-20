import { useColorScheme } from "@mui/material/styles";

export type PasteResolvedMode = "light" | "dark";

export interface PasteThemeTokens {
    accent: { main: string; hover: string; soft: string; contrastText: string };
    frame: {
        outerBg: string;
        innerBg: string;
        innerBorder: string;
        selectionBg: string;
        selectionText: string;
        headerIcon: string;
        headerIconHoverBg: string;
        modeIconBorder: string;
        modeIconBg: string;
        modeMenuBg: string;
        modeMenuBorder: string;
        logoTint: string;
    };
    text: {
        primary: string;
        secondary: string;
        muted: string;
        subtle: string;
        placeholder: string;
        counter: string;
        counterHighlight: string;
        footer: string;
        footerDot: string;
        copied: string;
        dialogBody: string;
    };
    surface: {
        inputBg: string;
        inputBorder: string;
        inputGradient: string;
        inputShadow: string;
        chipBg: string;
        chipBorder: string;
        chipText: string;
        chipInsetShadow: string;
        linkRowBg: string;
        linkRowBorder: string;
        linkRowInsetShadow: string;
        floatingCardBg: string;
        floatingCardBorder: string;
        floatingCardShadow: string;
        qrBackdropDesktop: string;
        qrBackdropMobile: string;
        dialogBackdrop: string;
        dialogBg: string;
        dialogBorder: string;
    };
    button: {
        primaryBg: string;
        primaryHoverBg: string;
        primaryText: string;
        primaryDisabledBg: string;
        primaryDisabledText: string;
        ghostBorder: string;
        ghostText: string;
        ghostHoverBorder: string;
        ghostHoverBg: string;
        qrToggleBorder: string;
        qrToggleBg: string;
        qrToggleActiveBg: string;
        qrToggleHoverBg: string;
        qrToggleActiveHoverBg: string;
        qrToggleText: string;
        scriptLink: string;
        scriptLinkHover: string;
    };
    status: {
        spinner: string;
        loadingTitle: string;
        loadingBody: string;
        errorIcon: string;
        errorBody: string;
        deletedNote: string;
    };
    qr: {
        paperBg: string;
        module: string;
        finder: string;
        mobilePaperBg: string;
    };
}

const darkTokens: PasteThemeTokens = {
    accent: {
        main: "#2f6df7",
        hover: "#4c86ff",
        soft: "rgba(47, 109, 247, 0.14)",
        contrastText: "#f4f7ff",
    },
    frame: {
        outerBg: "#2f6df7",
        innerBg: "#0d1016",
        innerBorder: "rgba(255, 255, 255, 0.04)",
        selectionBg: "#2f6df7",
        selectionText: "#ffffff",
        headerIcon: "#f4f7ff",
        headerIconHoverBg: "rgba(255, 255, 255, 0.12)",
        modeIconBorder: "rgba(227, 236, 255, 0.25)",
        modeIconBg: "rgba(255, 255, 255, 0.03)",
        modeMenuBg: "rgba(20, 26, 40, 0.98)",
        modeMenuBorder: "rgba(214, 226, 255, 0.16)",
        logoTint: "#ffffff",
    },
    text: {
        primary: "rgba(244, 247, 255, 0.95)",
        secondary: "rgba(220, 229, 255, 0.82)",
        muted: "rgba(186, 201, 232, 0.56)",
        subtle: "rgba(182, 197, 229, 0.44)",
        placeholder: "rgba(230, 236, 255, 0.42)",
        counter: "rgba(234, 238, 255, 0.6)",
        counterHighlight: "rgba(204, 224, 255, 0.96)",
        footer: "rgba(220, 229, 255, 0.84)",
        footerDot: "rgba(220, 229, 255, 0.58)",
        copied: "rgba(182, 190, 208, 0.9)",
        dialogBody: "rgba(220, 229, 255, 0.82)",
    },
    surface: {
        inputBg: "rgba(39, 42, 52, 0.76)",
        inputBorder: "rgba(213, 225, 255, 0.14)",
        inputGradient:
            "linear-gradient(160deg, rgba(255, 255, 255, 0.06) 0%, rgba(255, 255, 255, 0.02) 58%, rgba(255, 255, 255, 0.015) 100%)",
        inputShadow:
            "0 12px 28px rgba(0, 0, 0, 0.26), inset 0 1px 0 rgba(255, 255, 255, 0.1)",
        chipBg: "rgba(255, 255, 255, 0.045)",
        chipBorder: "rgba(147, 155, 177, 0.24)",
        chipText: "rgba(220, 229, 255, 0.55)",
        chipInsetShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.05)",
        linkRowBg: "rgba(255, 255, 255, 0.05)",
        linkRowBorder: "rgba(214, 226, 255, 0.16)",
        linkRowInsetShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.08)",
        floatingCardBg: "rgba(9, 18, 48, 0.9)",
        floatingCardBorder: "rgba(47, 109, 247, 0.44)",
        floatingCardShadow: "0 16px 40px rgba(0, 0, 0, 0.42)",
        qrBackdropDesktop: "rgba(5, 10, 24, 0.72)",
        qrBackdropMobile: "rgba(5, 10, 24, 0.72)",
        dialogBackdrop: "rgba(5, 10, 24, 0.74)",
        dialogBg: "rgba(39, 42, 52, 0.76)",
        dialogBorder: "rgba(213, 225, 255, 0.14)",
    },
    button: {
        primaryBg: "#2f6df7",
        primaryHoverBg: "#2f6df7",
        primaryText: "rgba(231, 238, 252, 0.9)",
        primaryDisabledBg: "rgba(255, 255, 255, 0.18)",
        primaryDisabledText: "rgba(230, 236, 255, 0.44)",
        ghostBorder: "rgba(214, 226, 255, 0.28)",
        ghostText: "rgba(236, 242, 255, 0.95)",
        ghostHoverBorder: "rgba(214, 226, 255, 0.44)",
        ghostHoverBg: "rgba(255, 255, 255, 0.06)",
        qrToggleBorder: "rgba(244, 247, 255, 0.35)",
        qrToggleBg: "rgba(244, 247, 255, 0.12)",
        qrToggleActiveBg: "rgba(244, 247, 255, 0.22)",
        qrToggleHoverBg: "rgba(244, 247, 255, 0.18)",
        qrToggleActiveHoverBg: "rgba(244, 247, 255, 0.28)",
        qrToggleText: "#f4f7ff",
        scriptLink: "#2f6df7",
        scriptLinkHover: "#5d92ff",
    },
    status: {
        spinner: "rgba(176, 198, 234, 0.76)",
        loadingTitle: "rgba(201, 212, 236, 0.66)",
        loadingBody: "rgba(188, 201, 230, 0.44)",
        errorIcon: "rgba(180, 198, 232, 0.76)",
        errorBody: "rgba(186, 201, 232, 0.46)",
        deletedNote: "rgba(182, 197, 229, 0.44)",
    },
    qr: {
        paperBg: "#fff",
        module: "#2f6df7",
        finder: "#1d3d9f",
        mobilePaperBg: "#fff",
    },
};

const lightTokens: PasteThemeTokens = {
    accent: {
        main: "#2f6df7",
        hover: "#1f58e2",
        soft: "rgba(47, 109, 247, 0.12)",
        contrastText: "#f5f8ff",
    },
    frame: {
        outerBg: "#2f6df7",
        innerBg: "#f4f8ff",
        innerBorder: "rgba(12, 37, 94, 0.1)",
        selectionBg: "#2f6df7",
        selectionText: "#ffffff",
        headerIcon: "rgba(13, 35, 90, 0.86)",
        headerIconHoverBg: "rgba(47, 109, 247, 0.16)",
        modeIconBorder: "rgba(47, 109, 247, 0.22)",
        modeIconBg: "rgba(47, 109, 247, 0.06)",
        modeMenuBg: "rgba(255, 255, 255, 0.98)",
        modeMenuBorder: "rgba(47, 109, 247, 0.2)",
        logoTint: "#0d1016",
    },
    text: {
        primary: "rgba(12, 35, 89, 0.96)",
        secondary: "rgba(28, 57, 122, 0.82)",
        muted: "rgba(38, 66, 132, 0.66)",
        subtle: "rgba(52, 80, 148, 0.56)",
        placeholder: "rgba(47, 76, 140, 0.48)",
        counter: "rgba(35, 64, 129, 0.62)",
        counterHighlight: "rgba(32, 92, 224, 0.96)",
        footer: "#0d1016",
        footerDot: "#0d1016",
        copied: "rgba(37, 65, 126, 0.86)",
        dialogBody: "rgba(37, 65, 129, 0.82)",
    },
    surface: {
        inputBg: "rgba(255, 255, 255, 0.92)",
        inputBorder: "rgba(47, 109, 247, 0.24)",
        inputGradient:
            "linear-gradient(160deg, rgba(255, 255, 255, 0.98) 0%, rgba(242, 248, 255, 0.94) 58%, rgba(231, 241, 255, 0.9) 100%)",
        inputShadow:
            "0 10px 24px rgba(17, 51, 121, 0.14), inset 0 1px 0 rgba(255, 255, 255, 0.92)",
        chipBg: "rgba(47, 109, 247, 0.07)",
        chipBorder: "rgba(47, 109, 247, 0.24)",
        chipText: "rgba(34, 61, 122, 0.72)",
        chipInsetShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.8)",
        linkRowBg: "rgba(255, 255, 255, 0.86)",
        linkRowBorder: "rgba(47, 109, 247, 0.22)",
        linkRowInsetShadow: "inset 0 1px 0 rgba(255, 255, 255, 0.92)",
        floatingCardBg: "rgba(245, 249, 255, 0.96)",
        floatingCardBorder: "rgba(47, 109, 247, 0.3)",
        floatingCardShadow: "0 14px 34px rgba(17, 49, 114, 0.18)",
        qrBackdropDesktop: "rgba(18, 43, 94, 0.2)",
        qrBackdropMobile: "rgba(18, 43, 94, 0.2)",
        dialogBackdrop: "rgba(18, 43, 94, 0.2)",
        dialogBg: "rgba(255, 255, 255, 0.94)",
        dialogBorder: "rgba(47, 109, 247, 0.26)",
    },
    button: {
        primaryBg: "#2f6df7",
        primaryHoverBg: "#1f58e2",
        primaryText: "#f4f8ff",
        primaryDisabledBg: "rgba(47, 109, 247, 0.3)",
        primaryDisabledText: "rgba(16, 43, 102, 0.5)",
        ghostBorder: "rgba(47, 109, 247, 0.35)",
        ghostText: "rgba(19, 48, 108, 0.92)",
        ghostHoverBorder: "rgba(47, 109, 247, 0.5)",
        ghostHoverBg: "rgba(47, 109, 247, 0.1)",
        qrToggleBorder: "rgba(47, 109, 247, 0.3)",
        qrToggleBg: "rgba(47, 109, 247, 0.12)",
        qrToggleActiveBg: "rgba(47, 109, 247, 0.2)",
        qrToggleHoverBg: "rgba(47, 109, 247, 0.18)",
        qrToggleActiveHoverBg: "rgba(47, 109, 247, 0.28)",
        qrToggleText: "#1f53c8",
        scriptLink: "#1f58e2",
        scriptLinkHover: "#1849bc",
    },
    status: {
        spinner: "rgba(47, 109, 247, 0.74)",
        loadingTitle: "rgba(26, 55, 118, 0.78)",
        loadingBody: "rgba(52, 80, 142, 0.62)",
        errorIcon: "rgba(47, 109, 247, 0.68)",
        errorBody: "rgba(56, 84, 148, 0.72)",
        deletedNote: "rgba(48, 77, 143, 0.6)",
    },
    qr: {
        paperBg: "#fff",
        module: "#2f6df7",
        finder: "#1d3d9f",
        mobilePaperBg: "#fff",
    },
};

export const getPasteThemeTokens = (
    mode: PasteResolvedMode,
): PasteThemeTokens => (mode === "light" ? lightTokens : darkTokens);

export const usePasteColorMode = () => {
    const { systemMode } = useColorScheme();
    const resolvedMode: PasteResolvedMode = systemMode ?? "dark";
    return { resolvedMode };
};
