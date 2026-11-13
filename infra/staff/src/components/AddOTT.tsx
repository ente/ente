import {
    Alert,
    Box,
    Button,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    FormControl,
    InputLabel,
    MenuItem,
    Paper,
    Select,
    type SelectChangeEvent,
    Typography,
} from "@mui/material";
import React, { useState } from "react";
import { addOTT } from "../services/admin-user";
import { useStaffSession } from "../services/session";
import { dateFromMicroseconds, microsecondsFromNow } from "../utils";

const APP_OPTIONS = [
    { label: "Photos", value: "photos" },
    { label: "Locker", value: "locker" },
    { label: "Auth", value: "auth" },
] as const;

type AppOption = (typeof APP_OPTIONS)[number]["value"];

interface AddOTTProps {
    open: boolean;
    onClose: () => void;
    userEmail: string;
}

export const AddOTT: React.FC<AddOTTProps> = ({ open, onClose, userEmail }) => {
    const [selectedApp, setSelectedApp] = useState<AppOption>("photos");
    const [submitting, setSubmitting] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [createdOtp, setCreatedOtp] = useState<string | null>(null);
    const [expiryPreview, setExpiryPreview] = useState(() =>
        computeExpiryTimeMicros(),
    );
    const session = useStaffSession();

    const resetForm = () => {
        setSelectedApp("photos");
        setError(null);
        setCreatedOtp(null);
        setExpiryPreview(computeExpiryTimeMicros());
    };

    const handleClose = () => {
        if (submitting) {
            return;
        }
        onClose();
    };

    const handleSubmit = async () => {
        try {
            setSubmitting(true);
            setError(null);

            if (!userEmail || userEmail === "None") {
                throw new Error("User email is unavailable");
            }

            const otp = generateOTP();
            const expiryTime = computeExpiryTimeMicros();
            setExpiryPreview(expiryTime);

            await addOTT(session, {
                email: userEmail,
                code: otp,
                app: selectedApp,
                expiryTime,
            });

            setCreatedOtp(otp);
        } catch (err) {
            if (err instanceof Error) {
                setError(err.message);
            } else {
                setError("Failed to create OTT");
            }
        } finally {
            setSubmitting(false);
        }
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            PaperComponent={Paper}
            maxWidth="xs"
            fullWidth
            slotProps={{ transition: { onEnter: resetForm } }}
        >
            {createdOtp ? (
                <>
                    <DialogTitle>OTT created</DialogTitle>
                    <DialogContent>
                        <Typography gutterBottom>
                            Share this OTP with the user. It expires in 7 days.
                        </Typography>
                        <Box
                            sx={{
                                bgcolor: "#F5F5F5",
                                borderRadius: 1,
                                p: 2,
                                textAlign: "center",
                                fontSize: "1.5rem",
                                fontWeight: "bold",
                                letterSpacing: "0.2rem",
                            }}
                        >
                            {createdOtp}
                        </Box>
                    </DialogContent>
                    <DialogActions>
                        <Button onClick={handleClose} variant="contained">
                            Done
                        </Button>
                    </DialogActions>
                </>
            ) : (
                <>
                    <DialogTitle>Add OTT</DialogTitle>
                    <DialogContent>
                        <Typography variant="body2" gutterBottom>
                            Generate a one-time token for{" "}
                            <strong>{userEmail || "this user"}</strong>. The OTP
                            expires 7 days from now.
                        </Typography>
                        <FormControl fullWidth margin="normal">
                            <InputLabel id="app-type-label">
                                App type
                            </InputLabel>
                            <Select
                                labelId="app-type-label"
                                value={selectedApp}
                                label="App type"
                                onChange={(
                                    event: SelectChangeEvent<AppOption>,
                                ) => setSelectedApp(event.target.value)}
                            >
                                {APP_OPTIONS.map((option) => (
                                    <MenuItem
                                        key={option.value}
                                        value={option.value}
                                    >
                                        {option.label}
                                    </MenuItem>
                                ))}
                            </Select>
                        </FormControl>
                        <Typography variant="caption" color="text.secondary">
                            Expires: {formatExpiryTime(expiryPreview)}
                        </Typography>
                        {error && (
                            <Alert severity="error" sx={{ mt: 2 }}>
                                {error}
                            </Alert>
                        )}
                    </DialogContent>
                    <DialogActions>
                        <Button onClick={handleClose}>Cancel</Button>
                        <Button
                            variant="contained"
                            onClick={() => {
                                void handleSubmit();
                            }}
                            disabled={submitting}
                        >
                            {submitting ? "Creating..." : "Create"}
                        </Button>
                    </DialogActions>
                </>
            )}
        </Dialog>
    );
};

const computeExpiryTimeMicros = () => microsecondsFromNow(7);

const formatExpiryTime = (expiryTime: number) =>
    dateFromMicroseconds(expiryTime).toLocaleString();

const generateOTP = () => {
    const values = new Uint32Array(1);
    crypto.getRandomValues(values);
    return `${values[0]! % 1_000_000}`.padStart(6, "0");
};
