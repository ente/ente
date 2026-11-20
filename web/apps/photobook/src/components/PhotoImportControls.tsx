import { usePhotoImport } from "@/hooks/usePhotoImport";
import { TextField } from "@mui/material";
import EntePasswordDialog from "./EntePasswordDialog";
import OriginalDownloadErrorDialog from "./OriginalDownloadErrorDialog";
import PhotoChoiceDialog from "./PhotoChoiceDialog";

export default function PhotoImportControls() {
    const {
        fileInputRef,
        handleFiles,
        enteStage,
        enteUrl,
        setEnteUrl,
        handleImportEnte,
        closeEnteDialog,
        entePassword,
        entePasswordError,
        verifyingPassword,
        setEntePassword,
        handleSubmitPassword,
        handleCancelPassword,
        handleReplaceBook,
    } = usePhotoImport();
    return (
        <>
            <OriginalDownloadErrorDialog />
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
            <PhotoChoiceDialog
                open={enteStage === "url"}
                title="Import another album"
                description="Paste an Ente album link to import its photos."
                primary={{
                    label: "Import",
                    onClick: () => {
                        void handleImportEnte();
                    },
                    disabled: !enteUrl.trim(),
                }}
                onClose={closeEnteDialog}
            >
                <TextField
                    autoFocus
                    fullWidth
                    label="Ente album link"
                    value={enteUrl}
                    autoComplete="off"
                    slotProps={{
                        htmlInput: { inputMode: "url", spellCheck: false },
                    }}
                    onChange={(event) => setEnteUrl(event.target.value)}
                    onKeyDown={(event) => {
                        if (event.key === "Enter" && enteUrl.trim()) {
                            event.preventDefault();
                            void handleImportEnte();
                        }
                    }}
                />
            </PhotoChoiceDialog>
            <EntePasswordDialog
                open={enteStage === "password"}
                password={entePassword}
                error={entePasswordError}
                submitting={verifyingPassword}
                onPasswordChange={setEntePassword}
                onSubmit={handleSubmitPassword}
                onCancel={handleCancelPassword}
            />
            <PhotoChoiceDialog
                open={enteStage === "replace"}
                icon="book"
                title="Start a new book?"
                description="Importing this album will replace the photobook saved in this browser."
                primary={{
                    label: "Replace book",
                    onClick: () => handleReplaceBook(true),
                }}
                secondary={{
                    label: "Keep current book",
                    onClick: () => handleReplaceBook(false),
                }}
                onClose={() => handleReplaceBook(false)}
            />
        </>
    );
}
