import { PasteCreatePanel } from "@/components/PasteCreatePanel";
import { PasteFrame } from "@/components/PasteFrame";
import { PasteViewPanel } from "@/components/PasteViewPanel";
import { usePasteRoute } from "@/use-paste";
import { Stack } from "@mui/material";
import Head from "next/head";

const Page = () => {
    const mode = usePasteRoute();

    return (
        <>
            <Head>
                <meta
                    name="description"
                    content="Share sensitive text with one-time, end-to-end encrypted links that auto-expire after 24 hours."
                />
                <meta
                    property="og:image"
                    content="https://paste.ente.com/images/metaimage.png"
                />
                <meta
                    name="twitter:image"
                    content="https://paste.ente.com/images/metaimage.png"
                />
            </Head>

            <PasteFrame>
                <Stack
                    spacing={2.5}
                    sx={{
                        width: "100%",
                        maxWidth: { xs: "100%", md: 620 },
                        minWidth: 0,
                        mx: "auto",
                    }}
                >
                    {mode === "create" && <PasteCreatePanel />}

                    {mode === "view" && <PasteViewPanel />}
                </Stack>
            </PasteFrame>
        </>
    );
};

export default Page;
