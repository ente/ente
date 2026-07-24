import SearchIcon from "@mui/icons-material/Search";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    Divider,
    InputAdornment,
    Stack,
    styled,
    TextField,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { SpacedRow } from "ente-base/components/containers";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, { useState } from "react";
import { ItemCard, LargeTileButton, LargeTileTextOverlay } from "./Tiles";

export type AssignPersonDialogProps = ModalVisibilityProps & {
    /**
     * Existing named people that can be selected.
     */
    people: Person[];
    /**
     * Title to show on the dialog.
     */
    title: string;
    /**
     * Called when the user selects a person.
     */
    onSelectPerson: (personID: string) => void;
};

/**
 * A dialog that allows selecting an existing person (cgroup) to associate
 * something (e.g. file(s)) with.
 */
export const AssignPersonDialog: React.FC<AssignPersonDialogProps> = ({
    open,
    onClose,
    people,
    title,
    onSelectPerson,
}) => {
    const isFullScreen = useMediaQuery("(max-width: 490px)");
    const [searchTerm, setSearchTerm] = useState("");
    const query = searchTerm.trim().toLowerCase();
    const filteredPeople = query
        ? people.filter((person) => person.name?.toLowerCase().includes(query))
        : people;

    return (
        <StyledDialog
            {...{ open, onClose }}
            fullWidth
            fullScreen={isFullScreen}
            slotProps={{
                paper: { sx: { maxWidth: "505px", minHeight: "80svh" } },
                transition: { onExited: () => setSearchTerm("") },
            }}
        >
            <DialogTitle>
                <Stack sx={{ gap: 1.5 }}>
                    <SpacedRow>
                        <Typography variant="h3">{title}</Typography>
                        <DialogCloseIconButton {...{ onClose }} />
                    </SpacedRow>
                    <TextField
                        fullWidth
                        type="search"
                        size="small"
                        placeholder={t("search")}
                        value={searchTerm}
                        onChange={(event) => setSearchTerm(event.target.value)}
                        autoFocus
                        slotProps={{
                            htmlInput: {
                                "aria-label": `${t("search")} ${t("people")}`,
                            },
                            input: {
                                startAdornment: (
                                    <InputAdornment position="start">
                                        <SearchIcon />
                                    </InputAdornment>
                                ),
                            },
                        }}
                        sx={searchFieldSx}
                    />
                </Stack>
            </DialogTitle>
            <Divider />
            {filteredPeople.length ? (
                <DialogContent_>
                    {filteredPeople.map((person) => (
                        <ItemCard
                            key={person.id}
                            TileComponent={LargeTileButton}
                            coverFile={person.displayFaceFile}
                            coverFaceID={person.displayFaceID}
                            onClick={() => onSelectPerson(person.id)}
                        >
                            <LargeTileTextOverlay>
                                <Typography>{person.name ?? ""}</Typography>
                            </LargeTileTextOverlay>
                        </ItemCard>
                    ))}
                </DialogContent_>
            ) : (
                <NoResultsContent>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("no_results")}
                    </Typography>
                </NoResultsContent>
            )}
        </StyledDialog>
    );
};

const StyledDialog = styled(Dialog)(({ theme }) => ({
    "& .MuiDialogTitle-root": { padding: theme.spacing(2) },
    "& .MuiDialogContent-root": { padding: theme.spacing(2) },
}));

const DialogContent_ = styled(DialogContent)`
    display: grid;
    grid-template-columns: repeat(auto-fill, 150px);
    gap: 4px;
    align-content: start;

    @media (min-width: 491px) {
        justify-content: center;
    }
`;

const NoResultsContent = styled(DialogContent)`
    display: flex;
    justify-content: center;
    align-items: center;
`;

const searchFieldSx = {
    "& .MuiOutlinedInput-root": {
        backgroundColor: "background.searchInput",
        borderColor: "transparent",
        "&:hover": { borderColor: "accent.light" },
        "&.Mui-focused": { borderColor: "accent.main", boxShadow: "none" },
    },
    "& .MuiInputBase-input": {
        color: "text.base",
        paddingTop: "8.5px !important",
        paddingBottom: "8.5px !important",
    },
    "& .MuiInputAdornment-root": {
        color: "stroke.muted",
        marginTop: "0 !important",
        marginRight: "8px",
    },
    "& .MuiOutlinedInput-notchedOutline": { borderColor: "transparent" },
    "& .MuiInputBase-input::placeholder": { color: "text.muted", opacity: 1 },
};
