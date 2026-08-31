import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    InputAdornment,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import { ensureLocalUser } from "ente-accounts/services/user";
import { useBaseContext } from "ente-base/context";
import { isNamedError } from "ente-base/error";
import { publicKey, type Session } from "ente-legacy-wasm/authenticated";
import React, { useMemo, useState } from "react";
import {
    legacyAddContact,
    legacyVerificationID,
    type LegacySuggestedUser,
} from "..";
import { contactsDisplaySnapshot } from "../..";
import { resolveContactDisplayFromSnapshot } from "../../resolver";
import { ActionButton } from "./ActionButton";
import { LegacyIdentityRow } from "./LegacyIdentityRow";
import { LegacyRecoveryDayPicker } from "./LegacyRecoveryDayPicker";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface LegacyAddContactContentProps {
    getSession: () => Promise<Session>;
    existingEmails: string[];
    onAdded: () => Promise<void>;
    suggestedUsers: LegacySuggestedUser[];
    variant?: "page" | "sheet";
}

const nonEnteDialogAttributes = (email: string) => ({
    title: "Cannot add trusted contact",
    message: `${email} is not linked to an Ente account yet, so it cannot be used as a trusted contact.`,
});

export const LegacyAddContactContent: React.FC<
    LegacyAddContactContentProps
> = ({
    getSession,
    existingEmails,
    onAdded,
    suggestedUsers,
    variant = "page",
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();
    const currentUser = ensureLocalUser();
    const [email, setEmail] = useState("");
    const [selectedRecoveryDays, setSelectedRecoveryDays] = useState(14);
    const snapshot = contactsDisplaySnapshot();

    const normalizedExistingEmails = useMemo(
        () =>
            new Set(existingEmails.map((value) => value.trim().toLowerCase())),
        [existingEmails],
    );

    const filteredSuggestions = useMemo(() => {
        const normalizedQuery = email.trim().toLowerCase();
        const byEmail = new Map<string, LegacySuggestedUser>();
        for (const user of suggestedUsers) {
            const normalizedEmail = user.email.trim().toLowerCase();
            const resolvedDisplay = resolveContactDisplayFromSnapshot(
                snapshot,
                { email: user.email, userID: user.id },
            );
            const normalizedName = resolvedDisplay.primaryLabel
                .trim()
                .toLowerCase();
            if (
                !normalizedEmail ||
                normalizedEmail === currentUser.email.toLowerCase() ||
                normalizedExistingEmails.has(normalizedEmail)
            ) {
                continue;
            }
            if (
                normalizedQuery &&
                !normalizedEmail.includes(normalizedQuery) &&
                !normalizedName.includes(normalizedQuery)
            ) {
                continue;
            }
            byEmail.set(normalizedEmail, user);
        }
        return [...byEmail.values()].sort((a, b) =>
            a.email.localeCompare(b.email, undefined, { sensitivity: "base" }),
        );
    }, [
        currentUser.email,
        email,
        normalizedExistingEmails,
        snapshot,
        suggestedUsers,
    ]);

    const normalizedEmail = email.trim().toLowerCase();

    const handleVerify = async () => {
        if (!normalizedEmail || !EMAIL_PATTERN.test(normalizedEmail)) {
            showMiniDialog({
                title: "Invalid email",
                message: "Enter a valid email address before verifying its ID.",
            });
            return;
        }
        try {
            const verificationID = await legacyVerificationID(
                await getSession(),
                normalizedEmail,
            );
            if (!verificationID) {
                showMiniDialog({
                    title: "Verification ID unavailable",
                    message:
                        "That email is not linked to an Ente account yet, so there is no public key to verify.",
                });
                return;
            }
            showMiniDialog({
                title: "Verification ID",
                message: (
                    <Box
                        sx={{ whiteSpace: "pre-wrap", wordBreak: "break-word" }}
                    >
                        {verificationID}
                    </Box>
                ),
            });
        } catch (error) {
            onGenericError(error);
        }
    };

    const handleAdd = () => {
        if (!normalizedEmail) {
            return;
        }
        if (!EMAIL_PATTERN.test(normalizedEmail)) {
            showMiniDialog({
                title: "Invalid email",
                message:
                    "Enter a valid email address for your trusted contact.",
            });
            return;
        }
        if (normalizedEmail === currentUser.email.toLowerCase()) {
            showMiniDialog({
                title: "Invalid trusted contact",
                message:
                    "You cannot add your own account as a trusted contact.",
            });
            return;
        }
        if (normalizedExistingEmails.has(normalizedEmail)) {
            showMiniDialog({
                title: "Already added",
                message: "That email is already present in your Legacy setup.",
            });
            return;
        }

        void (async () => {
            try {
                const key = await publicKey(
                    await getSession(),
                    normalizedEmail,
                );
                if (!key) {
                    showMiniDialog(nonEnteDialogAttributes(normalizedEmail));
                    return;
                }

                showMiniDialog({
                    title: "Add trusted contact?",
                    message: `Ente will wait ${selectedRecoveryDays} days before ${normalizedEmail} can recover your account.`,
                    continue: {
                        text: "Add trusted contact",
                        color: "primary",
                        action: async () => {
                            try {
                                await legacyAddContact(
                                    await getSession(),
                                    normalizedEmail,
                                    selectedRecoveryDays,
                                );
                            } catch (error) {
                                if (
                                    isNamedError(error, "contact_not_on_ente")
                                ) {
                                    setTimeout(() => {
                                        showMiniDialog(
                                            nonEnteDialogAttributes(
                                                normalizedEmail,
                                            ),
                                        );
                                    }, 0);
                                    return;
                                }
                                throw error;
                            }
                            await onAdded();
                        },
                    },
                });
            } catch (error) {
                onGenericError(error);
            }
        })();
    };

    const isSheet = variant === "sheet";

    return (
        <Stack sx={{ gap: 2, ...(isSheet ? {} : { px: 2, pb: 2 }) }}>
            {!isSheet && (
                <Stack sx={{ gap: 1 }}>
                    <Typography variant="h4">Add trusted contact</Typography>
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        Search an email, verify the identity if needed, and
                        choose how long recovery should wait.
                    </Typography>
                </Stack>
            )}

            <Stack
                sx={{
                    gap: 2,
                    ...(isSheet
                        ? {}
                        : {
                              p: 2,
                              borderRadius: "20px",
                              backgroundColor: "backdrop.base",
                          }),
                }}
            >
                <TextField
                    autoFocus
                    size="small"
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="Enter email"
                    slotProps={{
                        input: {
                            startAdornment: (
                                <InputAdornment position="start">
                                    <SearchIcon fontSize="small" />
                                </InputAdornment>
                            ),
                        },
                    }}
                />

                {!!filteredSuggestions.length && (
                    <Stack sx={{ gap: 1 }}>
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            Choose from an existing contact
                        </Typography>
                        <Stack
                            sx={{
                                gap: 0.5,
                                p: 0.75,
                                borderRadius: "18px",
                                backgroundColor: "fill.faint",
                                maxHeight: 260,
                                overflowY: "auto",
                            }}
                        >
                            {filteredSuggestions.map((user) => (
                                <LegacyIdentityRow
                                    key={`${user.id ?? "email"}:${user.email}`}
                                    email={user.email}
                                    userID={user.id}
                                    selected={
                                        normalizedEmail ===
                                        user.email.trim().toLowerCase()
                                    }
                                    onClick={() => setEmail(user.email)}
                                />
                            ))}
                        </Stack>
                    </Stack>
                )}

                {!!email.trim() &&
                    !filteredSuggestions.length &&
                    EMAIL_PATTERN.test(normalizedEmail) && (
                        <Typography
                            variant="small"
                            sx={{ color: "text.muted" }}
                        >
                            No existing contact matched. You can still add this
                            email directly.
                        </Typography>
                    )}

                <Stack sx={{ gap: 1 }}>
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        Choose a recovery time
                    </Typography>
                    <LegacyRecoveryDayPicker
                        selectedDays={selectedRecoveryDays}
                        onChange={setSelectedRecoveryDays}
                    />
                </Stack>

                <ActionButton
                    fullWidth
                    buttonType="primary"
                    onClick={handleAdd}
                    disabled={!email.trim()}
                >
                    Add trusted contact
                </ActionButton>

                <ActionButton
                    buttonType="link"
                    onClick={() => void handleVerify()}
                    disabled={!email.trim()}
                    sx={{ alignSelf: "center" }}
                >
                    Verify
                </ActionButton>
            </Stack>
        </Stack>
    );
};
