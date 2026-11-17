import { usePhotoImport } from "@/hooks/usePhotoImport";
import PhotoChoiceDialog from "./PhotoChoiceDialog";

export default function PhotoImportControls() {
    const {
        fileInputRef,
        handleFiles,
        oversizedImport,
        resolvePhotoLimit,
        setEnteUrl,
        maxPhotos,
    } = usePhotoImport();
    return (
        <>
            <input
                ref={fileInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif"
                multiple
                hidden
                onChange={(event) => {
                    if (event.currentTarget.files)
                        void handleFiles(event.currentTarget.files);
                    event.currentTarget.value = "";
                }}
            />
            {oversizedImport && (
                <PhotoChoiceDialog
                    open
                    title="Too many photos"
                    description={
                        oversizedImport === "album"
                            ? `This album has more photos than will fit in one book. You can use the first ${maxPhotos} or choose another album.`
                            : `These photos won’t all fit in one book. You can use the first ${maxPhotos} or pick your favorites.`
                    }
                    primary={{
                        label: `Use the first ${maxPhotos} photos`,
                        onClick: () => resolvePhotoLimit(true),
                    }}
                    secondary={{
                        label:
                            oversizedImport === "album"
                                ? "Choose another album"
                                : "Pick photos",
                        onClick: () => {
                            resolvePhotoLimit(false);
                            if (oversizedImport === "files")
                                fileInputRef.current?.click();
                            else setEnteUrl("");
                        },
                    }}
                    onClose={() => resolvePhotoLimit(false)}
                />
            )}
        </>
    );
}
