import "@fontsource-variable/inter";
import "@fontsource/itim";
import { CssBaseline, GlobalStyles } from "@mui/material";
import { ThemeProvider } from "@mui/material/styles";
import { CustomHead } from "ente-base/components/Head";
import { useSetupLogs } from "ente-base/components/utils/hooks-app";
import { shareTheme } from "ente-base/components/utils/theme";
import type { AppProps } from "next/app";
import Head from "next/head";
import React from "react";

const memoriesAppStyle = { "--font-itim": "'Itim'" } as React.CSSProperties;
const memoriesAppTitle = "Memories, shared with you";
const memoriesAppDescription = "Tap to relive with Ente";

function MemoriesAppHead() {
    const previewImage = "https://memories.ente.com/images/memories-meta.png";

    return (
        <>
            <CustomHead
                title={memoriesAppTitle}
                description={memoriesAppDescription}
            />
            <Head>
                <meta property="og:image" content={previewImage} />
                <meta property="og:image:secure_url" content={previewImage} />
                <meta property="og:image:type" content="image/png" />
                <meta property="og:image:width" content="720" />
                <meta property="og:image:height" content="405" />
                <meta name="twitter:image" content={previewImage} />
            </Head>
        </>
    );
}

const App: React.FC<AppProps> = ({ Component, pageProps }) => {
    useSetupLogs({ disableDiskLogs: true });

    return (
        <div style={memoriesAppStyle}>
            <ThemeProvider
                theme={shareTheme}
                defaultMode="system"
                // Avoid persisting a manual override; always follow the system theme.
                storageManager={null}
            >
                <MemoriesAppHead />
                <CssBaseline enableColorScheme />
                <GlobalStyles
                    styles={{
                        html: { height: "100%" },
                        body: {
                            height: "100%",
                            overflow: "hidden",
                            overscrollBehavior: "none",
                        },
                        "#__next": { height: "100%", overflow: "hidden" },
                    }}
                />
                <Component {...pageProps} />
            </ThemeProvider>
        </div>
    );
};

export default App;
