import "@fontsource/space-grotesk/400.css";
import "@fontsource/space-grotesk/500.css";
import "@fontsource/space-grotesk/600.css";
import "@fontsource/space-grotesk/700.css";
import { CssBaseline } from "@mui/material";
import { ThemeProvider, createTheme } from "@mui/material/styles";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import type { AppProps } from "next/app";

const twoOf3Theme = createTheme({
    cssVariables: { colorSchemeSelector: "class" },
    colorSchemes: {
        light: {
            palette: {
                primary: { main: "rgb(252, 239, 93)", contrastText: "#111111" },
                background: { default: "#ffffff", paper: "#ffffff" },
                text: { primary: "#111111", secondary: "rgba(17,17,17,0.68)" },
                divider: "rgba(17,17,17,0.18)",
            },
        },
        dark: {
            palette: {
                primary: { main: "rgb(252, 239, 93)", contrastText: "#111111" },
                background: { default: "#0b0b0b", paper: "#111111" },
                text: {
                    primary: "#fafafa",
                    secondary: "rgba(250,250,250,0.68)",
                },
                divider: "rgba(255,255,255,0.18)",
            },
        },
    },
    shape: { borderRadius: 20 },
    typography: {
        fontFamily:
            '"Space Grotesk", "Inter Variable", "Helvetica Neue", sans-serif',
        fontWeightRegular: 500,
        fontWeightMedium: 600,
        fontWeightBold: 700,
        h1: { fontWeight: 700, letterSpacing: "-0.05em" },
        h2: { fontWeight: 700, letterSpacing: "-0.04em" },
        h3: { fontWeight: 700, letterSpacing: "-0.04em" },
        body1: { fontWeight: 500, lineHeight: 1.55, letterSpacing: "-0.012em" },
        body2: { fontWeight: 500, lineHeight: 1.55, letterSpacing: "-0.012em" },
        subtitle1: { fontWeight: 500 },
        subtitle2: { fontWeight: 500 },
        button: {
            fontWeight: 700,
            letterSpacing: "-0.01em",
            textTransform: "none",
        },
    },
    components: {
        MuiButton: {
            styleOverrides: { root: { borderRadius: 18, boxShadow: "none" } },
        },
    },
});

const App = ({ Component, pageProps }: AppProps) => {
    useSetupLogs({ disableDiskLogs: true });

    return (
        <ThemeProvider
            theme={twoOf3Theme}
            defaultMode="system"
            storageManager={null}
        >
            <CustomHead title="2of3 by Ente" />
            <CssBaseline enableColorScheme />
            <Component {...pageProps} />
        </ThemeProvider>
    );
};

export default App;
