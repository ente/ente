import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import { useState } from "react";
import PhotoChoiceDialog from "./PhotoChoiceDialog";

export default function OriginalDownloadErrorDialog() {
    const { photos, waitForEnteOriginals } = useBook(
        "photos",
        "waitForEnteOriginals",
    );
    const { importActive } = usePhotoImport();
    const [dismissed, setDismissed] = useState<Set<string>>(() => new Set());
    const failed = photos.filter(
        (photo) =>
            photo.originalStatus === "failed" && !dismissed.has(photo.id),
    );
    const ids = failed.map((photo) => photo.id);
    const close = () =>
        setDismissed((previous) => new Set([...previous, ...ids]));
    const retry = async () => {
        close();
        if (!(await waitForEnteOriginals(ids))) {
            setDismissed(
                (previous) =>
                    new Set([...previous].filter((id) => !ids.includes(id))),
            );
        }
    };
    return (
        <PhotoChoiceDialog
            open={!importActive && failed.length > 0}
            icon="warning"
            title="Some photos couldn't download"
            description="We couldn't download some full-resolution photos from this album. You can keep editing, but these photos are needed to download or print your book."
            primary={{
                label: "Try again",
                onClick: () => {
                    void retry();
                },
            }}
            secondary={{ label: "Keep editing", onClick: close }}
            onClose={close}
        />
    );
}
