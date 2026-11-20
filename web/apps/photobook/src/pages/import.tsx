import PhotoChoiceDialog from "@/components/PhotoChoiceDialog";
import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import { parseAlbumHandoff } from "@/lib/ente/handoff";
import { useRouter } from "next/router";
import { useEffect, useRef, useState } from "react";

export default function ImportAlbum() {
    const router = useRouter();
    const { loading } = useBook("loading");
    const { importEnteAlbum, chooseAnotherAlbum, enteStage } = usePhotoImport();
    const started = useRef(false);
    const [error, setError] = useState<string>();

    useEffect(() => {
        if (loading || !router.isReady || started.current) return;
        started.current = true;
        const hash = window.location.hash;
        window.history.replaceState(
            window.history.state,
            "",
            window.location.pathname,
        );
        try {
            const { albumUrl, linkDeviceToken } = parseAlbumHandoff(hash);
            void importEnteAlbum(albumUrl, {
                linkDeviceToken,
                confirmReplacement: true,
            });
        } catch (error) {
            setError(
                error instanceof Error
                    ? error.message
                    : "Couldn't open this album link.",
            );
        }
    }, [loading, router.isReady, importEnteAlbum]);

    const close = () => {
        void router.replace("/");
    };
    return (
        <PhotoChoiceDialog
            open={!!error && enteStage !== "url"}
            icon="warning"
            title="Couldn't open this album"
            description={error ?? ""}
            primary={{
                label: "Try a different album",
                onClick: chooseAnotherAlbum,
            }}
            onClose={close}
        />
    );
}
