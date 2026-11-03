import EditPage from "@/components/EditPage";
import ResultsPage from "@/components/ResultsPage";
import { useBook } from "@/context/book";
import { usePhotoImport } from "@/hooks/usePhotoImport";
import { popupShadow, uiColors } from "@/theme/colors";
import {
    Alert,
    Box,
    CircularProgress,
    Snackbar,
    useMediaQuery,
} from "@mui/material";
import { MOBILE_QUERY } from "./editorLayout";
import EntePasswordDialog from "./EntePasswordDialog";
import ImportProgress from "./ImportProgress";

export default function AppShell() {
    const mobile = useMediaQuery(MOBILE_QUERY, { noSsr: true });
    const { appView, loading, importNotice, clearImportNotice } = useBook();
    const showPreview = mobile || appView === "results";
    const {
        importActive,
        enteStage,
        entePassword,
        setEntePassword,
        handleSubmitPassword,
        handleCancelPassword,
    } = usePhotoImport();
    if (loading) {
        return (
            <Box
                sx={{
                    minHeight: "100vh",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                }}
            >
                <CircularProgress sx={{ color: "#08C225" }} />
            </Box>
        );
    }

    return (
        <>
            {importActive ? (
                <ImportProgress />
            ) : (
                <Box data-workspace-view={showPreview ? "results" : "edit"}>
                    {showPreview ? <ResultsPage /> : <EditPage />}
                </Box>
            )}
            <EntePasswordDialog
                open={enteStage === "password"}
                password={entePassword}
                onPasswordChange={setEntePassword}
                onSubmit={handleSubmitPassword}
                onCancel={handleCancelPassword}
            />

            <Snackbar
                open={Boolean(importNotice)}
                autoHideDuration={10000}
                onClose={clearImportNotice}
                anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
            >
                <Alert
                    severity="info"
                    onClose={clearImportNotice}
                    sx={{
                        bgcolor: uiColors.surface,
                        color: uiColors.text,
                        boxShadow: popupShadow,
                        "& .MuiAlert-icon": { color: "#08C225" },
                    }}
                >
                    {importNotice}
                </Alert>
            </Snackbar>
        </>
    );
}
