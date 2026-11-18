import { usePhotoImport } from "@/hooks/usePhotoImport";

export default function PhotoImportControls() {
    const { fileInputRef, handleFiles } = usePhotoImport();
    return (
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
    );
}
