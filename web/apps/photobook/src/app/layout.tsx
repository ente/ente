import { BookProvider } from "@/context/BookContext";
import { PhotoImportProvider } from "@/hooks/usePhotoImport";
import theme from "@/theme/theme";
import "@fontsource-variable/inter";
import "@fontsource-variable/outfit";
import "@fontsource/gochi-hand";
import { AppRouterCacheProvider } from "@mui/material-nextjs/v16-appRouter";
import CssBaseline from "@mui/material/CssBaseline";
import { ThemeProvider } from "@mui/material/styles";
import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
    title: "Ente Photobook",
    description: "Create beautiful photobooks privately in your browser",
    icons: { icon: "/favicon-32x32.png", apple: "/icon-192x192.png" },
};

export default function RootLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    return (
        <html lang="en">
            <body>
                <AppRouterCacheProvider>
                    <ThemeProvider theme={theme}>
                        <CssBaseline />
                        <BookProvider>
                            <PhotoImportProvider>
                                {children}
                            </PhotoImportProvider>
                        </BookProvider>
                    </ThemeProvider>
                </AppRouterCacheProvider>
            </body>
        </html>
    );
}
