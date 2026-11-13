import { Box, CircularProgress } from "@mui/material";
import { CustomHeadShare } from "ente-base/components/Head";
import Head from "next/head";
import React, { useEffect, useState } from "react";
import { CollectionShareView } from "../components/file-share/CollectionShareView";
import { FileShareView } from "../components/file-share/FileShareView";

const detectShareView = (pathname: string): "file" | "collection" | null => {
    if (/^\/c\/[^/]+\/?$/.test(pathname)) {
        return "collection";
    }

    if (pathname === "/" || pathname === "") {
        return null;
    }

    return "file";
};

// Every route is served by this page: the _redirects file (Cloudflare Pages),
// Next.js rewrites (dev), and nginx try_files (Docker) all rewrite to it, and
// it reads the share token from window.location instead of router params.
const Page: React.FC = () => {
    const [hideContent, setHideContent] = useState(false);
    const [shareView, setShareView] = useState<"file" | "collection" | null>(
        null,
    );

    useEffect(() => {
        const pathname = window.location.pathname;
        const nextShareView = detectShareView(pathname);
        setShareView(nextShareView);

        if (nextShareView === null) {
            setHideContent(true);
            window.location.href = "https://ente.com/locker";
        }
    }, []);

    return (
        <>
            <CustomHeadShare title="Ente Locker" />
            <Head>
                <meta name="robots" content="noindex, nofollow" />
            </Head>
            {!hideContent && shareView === null && (
                <Box
                    sx={{
                        minHeight: "100dvh",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        bgcolor: "#08090A",
                    }}
                >
                    <CircularProgress sx={{ color: "accent.main" }} size={32} />
                </Box>
            )}
            {!hideContent && shareView === "collection" ? (
                <CollectionShareView />
            ) : !hideContent && shareView === "file" ? (
                <FileShareView />
            ) : null}
        </>
    );
};

export default Page;
