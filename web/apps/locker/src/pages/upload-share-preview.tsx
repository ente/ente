import { CreateItemDialog } from "@/components/create-item/CreateItemDialog";
import { LockerFileLinkDialog } from "@/components/items/LockerFileLinkDialog";
import { LockerConfirmDialog } from "@/components/ui/LockerConfirmDialog";
import { useSetupLockerI18n } from "@/i18n/locker";
import { lockerPrimaryButtonSx } from "@/styles/fields";
import { lockerTextBodySx, lockerTextH2Sx } from "@/styles/tokens";
import type { LockerUploadCandidate } from "@/types";
import { Box, Button, Snackbar, Stack, Typography } from "@mui/material";
import { useRef, useState } from "react";

export default function UploadSharePreview() {
    const isI18nReady = useSetupLockerI18n();
    const [stage, setStage] = useState<
        "ready" | "upload" | "success" | "share"
    >("success");
    const [items, setItems] = useState<LockerUploadCandidate[]>([]);
    const [uploadedNames, setUploadedNames] = useState([
        "Travel insurance.pdf",
    ]);
    const [selectedName, setSelectedName] = useState("Travel insurance.pdf");
    const [toast, setToast] = useState<string>();
    const completedNames = useRef<string[]>([]);

    if (process.env.NODE_ENV !== "development" || !isI18nReady) return null;

    const startUpload = () => {
        completedNames.current = [];
        setItems([
            {
                file: new File(
                    ["Sample document for the Locker interaction preview."],
                    "Travel insurance.txt",
                    { type: "text/plain" },
                ),
                suggestedCollectionNames: [],
            },
        ]);
        setStage("upload");
    };

    return (
        <Box sx={{ minHeight: "100vh", bgcolor: "background.default" }}>
            <Stack
                component="header"
                direction="row"
                sx={{
                    p: 3,
                    gap: 2,
                    alignItems: "center",
                    borderBottom: "1px solid",
                    borderColor: "divider",
                }}
            >
                <Box
                    component="img"
                    src="/images/locker.svg"
                    alt="Ente Locker"
                    sx={{ width: 40, height: 40 }}
                />
                <Typography sx={lockerTextH2Sx}>Share after upload</Typography>
            </Stack>
            <Stack sx={{ maxWidth: 440, mx: "auto", p: 3, gap: 3 }}>
                <Typography sx={lockerTextBodySx} color="text.secondary">
                    Local preview using Locker’s existing dialogs. Uploads and
                    share links are simulated.
                </Typography>
                <Button
                    onClick={startUpload}
                    sx={(theme) =>
                        lockerPrimaryButtonSx(theme, { loading: false })
                    }
                >
                    Try the upload flow
                </Button>
                <Button onClick={() => setStage("success")}>
                    Show upload complete
                </Button>
                <Button href="/locker">Open Locker</Button>
            </Stack>
            <CreateItemDialog
                open={stage === "upload"}
                onClose={() =>
                    setStage((current) =>
                        current === "upload" ? "ready" : current,
                    )
                }
                collections={[]}
                initialItems={items}
                onSave={() => Promise.resolve()}
                userDetails={{
                    usage: 0,
                    storageLimit: 10 * 1024 ** 3,
                    fileCount: 0,
                    lockerFileLimit: 1000,
                    isPartOfFamily: false,
                }}
                onEnsureCollections={(names) =>
                    Promise.resolve(
                        new Map(names.map((name, index) => [name, index + 1])),
                    )
                }
                onUploadProgress={async (file, _collections, onProgress) => {
                    onProgress({ phase: "preparing" });
                    await new Promise((resolve) => setTimeout(resolve, 250));
                    onProgress({
                        phase: "uploading",
                        loaded: file.size / 2,
                        total: file.size,
                    });
                    await new Promise((resolve) => setTimeout(resolve, 450));
                    onProgress({ phase: "finalizing" });
                    await new Promise((resolve) => setTimeout(resolve, 250));
                    completedNames.current.push(file.name);
                }}
                onUploadsFinished={() => {
                    setUploadedNames([...completedNames.current]);
                    setSelectedName(completedNames.current[0] ?? "Document");
                    setStage("success");
                    return Promise.resolve();
                }}
            />
            <LockerConfirmDialog
                open={stage === "success"}
                illustration="/images/onboarding-share.png"
                illustrationSize={180}
                compactIllustration
                title={
                    uploadedNames.length === 1
                        ? "File uploaded"
                        : `${uploadedNames.length} files uploaded`
                }
                body={
                    uploadedNames.length === 1
                        ? `${selectedName} is safely stored in Locker. Share a link now?`
                        : "Your files are safely stored in Locker. Share a file now?"
                }
                confirmLabel="Share file"
                cancelLabel="Done"
                tone="primary"
                onClose={() => setStage("ready")}
                onConfirm={() => setStage("share")}
            />
            {uploadedNames.length > 1 && stage === "share" ? (
                <LockerConfirmDialog
                    open
                    illustration="/images/onboarding-share.png"
                    illustrationSize={180}
                    compactIllustration
                    title="Choose a file to share"
                    body={uploadedNames.map((name, index) => (
                        <Button
                            key={`${index}:${name}`}
                            fullWidth
                            onClick={() => {
                                setSelectedName(name);
                                setUploadedNames([name]);
                            }}
                        >
                            {name}
                        </Button>
                    ))}
                    confirmLabel="Done"
                    tone="primary"
                    onClose={() => setStage("ready")}
                    onConfirm={() => setStage("ready")}
                />
            ) : (
                <LockerFileLinkDialog
                    open={stage === "share"}
                    itemTitle={selectedName}
                    url="https://example.invalid/locker/demo-link"
                    loading={false}
                    deleting={false}
                    onClose={() => setStage("ready")}
                    onCopy={() => setToast("Preview: link copied (simulated)")}
                    onShare={() => setToast("Preview: sharing simulated")}
                    onDelete={() => {
                        setStage("ready");
                        setToast("Preview: link deleted (simulated)");
                    }}
                />
            )}
            <Snackbar
                open={!!toast}
                message={toast}
                autoHideDuration={3500}
                onClose={() => setToast(undefined)}
            />
        </Box>
    );
}
