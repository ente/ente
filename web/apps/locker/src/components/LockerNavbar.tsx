import { Menu01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import SearchIcon from "@mui/icons-material/Search";
import {
    Box,
    IconButton,
    InputAdornment,
    Stack,
    TextField,
} from "@mui/material";
import { t } from "i18next";
import React, { useDeferredValue, useEffect, useState } from "react";

import { lockerContentMaxWidth } from "../styles/tokens";

interface LockerNavbarProps {
    onOpenSidebar: () => void;
    showMenuButton: boolean;
    stickyTop?: number;
    searchTerm: string;
    onSearchTermChange: (value: string) => void;
}

export const LockerNavbar: React.FC<LockerNavbarProps> = ({
    onOpenSidebar,
    showMenuButton,
    stickyTop = 0,
    searchTerm,
    onSearchTermChange,
}) => {
    const [localSearchTerm, setLocalSearchTerm] = useState(searchTerm);
    const deferredSearchTerm = useDeferredValue(localSearchTerm);

    useEffect(() => {
        onSearchTermChange(deferredSearchTerm);
    }, [deferredSearchTerm, onSearchTermChange]);

    useEffect(() => {
        setLocalSearchTerm(searchTerm);
    }, [searchTerm]);

    return (
        <Box
            sx={{
                position: "sticky",
                top: stickyTop,
                left: 0,
                zIndex: 1,
                background: "linear-gradient(135deg, #1071FF 0%, #0056CC 100%)",
                color: "#fff",
                px: 2,
                pt: 1,
                pb: 0.25,
            }}
        >
            <Stack
                direction="row"
                sx={{ alignItems: "center", justifyContent: "space-between" }}
            >
                {showMenuButton ? (
                    <IconButton onClick={onOpenSidebar} sx={{ color: "#fff" }}>
                        <HugeiconsIcon
                            icon={Menu01Icon}
                            size={24}
                            strokeWidth={2.25}
                        />
                    </IconButton>
                ) : (
                    <Box sx={{ width: 40 }} />
                )}

                <Box
                    component="img"
                    src="/images/app-logo.svg"
                    alt="Locker"
                    sx={{ height: 29, width: 73, objectFit: "contain" }}
                />

                <Box sx={{ width: 40 }} />
            </Stack>

            <Box
                sx={{
                    maxWidth: lockerContentMaxWidth,
                    mx: "auto",
                    mt: 0.5,
                    pb: 1.5,
                }}
            >
                <TextField
                    size="small"
                    placeholder={t("searchHint")}
                    value={localSearchTerm}
                    onChange={(event) => setLocalSearchTerm(event.target.value)}
                    variant="outlined"
                    fullWidth
                    slotProps={{
                        input: {
                            startAdornment: (
                                <InputAdornment position="start">
                                    <SearchIcon
                                        sx={{
                                            fontSize: 20,
                                            color: "text.faint",
                                        }}
                                    />
                                </InputAdornment>
                            ),
                        },
                    }}
                    sx={{
                        "& .MuiOutlinedInput-root": {
                            minHeight: 48,
                            borderRadius: "24px",
                            backgroundColor: "background.paper",
                            "& .MuiOutlinedInput-input": { py: 1.5 },
                            "& fieldset": { borderColor: "transparent" },
                            "&:hover fieldset": { borderColor: "transparent" },
                            "&.Mui-focused fieldset": {
                                borderColor: "rgba(255, 255, 255, 0.28)",
                                borderWidth: "1px",
                            },
                            "&.Mui-focused": {
                                boxShadow: "0 0 0 2px rgba(255, 255, 255, 0.1)",
                            },
                        },
                    }}
                />
            </Box>
        </Box>
    );
};
