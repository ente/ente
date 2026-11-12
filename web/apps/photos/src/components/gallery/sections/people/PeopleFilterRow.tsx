import { Cancel01Icon, Menu08Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    ButtonBase,
    Dialog,
    Stack,
    Typography,
    styled,
} from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import {
    useEffect,
    useId,
    useRef,
    useState,
    type MouseEventHandler,
} from "react";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

export const PeopleFilterRow = ({
    people,
    selectedPersonIDs,
}: {
    people: Person[];
    selectedPersonIDs: string[];
}) => {
    const { togglePerson } = usePhotosNavigation();
    const [showFilters, setShowFilters] = useState(false);
    const titleID = useId();
    // Mobile shows applied filters first and up to 14 recommendations in the
    // app bar; the filter sheet contains the complete list.
    const rowPeople = [
        ...people.filter((person) => selectedPersonIDs.includes(person.id)),
        ...people
            .filter((person) => !selectedPersonIDs.includes(person.id))
            .slice(0, 14),
    ];
    const pendingChip = useRef<HTMLButtonElement | null>(null);
    useEffect(() => {
        pendingChip.current?.scrollIntoView({
            block: "nearest",
            inline: "nearest",
        });
        pendingChip.current = null;
    }, [selectedPersonIDs]);
    if (!people.length) return null;
    return (
        <>
            <Stack
                role="group"
                aria-label={t("people")}
                direction="row"
                sx={{
                    gap: 1,
                    overflowX: "auto",
                    alignItems: "center",
                    px: 1,
                    pb: 1,
                    scrollbarWidth: "none",
                    "&::-webkit-scrollbar": { display: "none" },
                }}
            >
                <FilterButton
                    aria-label={t("filters")}
                    aria-haspopup="dialog"
                    aria-expanded={showFilters}
                    onClick={() => setShowFilters(true)}
                >
                    <HugeiconsIcon icon={Menu08Icon} size={16} />
                </FilterButton>
                {rowPeople.map((person) => (
                    <FaceFilter
                        key={person.id}
                        person={person}
                        selected={selectedPersonIDs.includes(person.id)}
                        onClick={(event) => {
                            if (!selectedPersonIDs.includes(person.id))
                                pendingChip.current = event.currentTarget;
                            togglePerson(person.id);
                        }}
                    />
                ))}
            </Stack>
            <Dialog
                open={showFilters}
                onClose={() => setShowFilters(false)}
                aria-labelledby={titleID}
                maxWidth={false}
                sx={{
                    "& .MuiDialog-container": {
                        alignItems: { xs: "flex-end", md: "center" },
                    },
                    "& .MuiBackdrop-root": { bgcolor: "rgba(0, 0, 0, 0.55)" },
                }}
                slotProps={{
                    paper: {
                        sx: (theme) => ({
                            m: { xs: 0, md: 4 },
                            width: { xs: "100%", md: 440 },
                            maxWidth: "100%",
                            p: "20px",
                            pb: "max(20px, env(safe-area-inset-bottom))",
                            borderRadius: { xs: "20px 20px 0 0", md: "24px" },
                            bgcolor: "#f4f4f4",
                            backgroundImage: "none",
                            ...theme.applyStyles("dark", {
                                bgcolor: "#161616",
                            }),
                        }),
                    },
                }}
            >
                <Stack
                    direction="row"
                    sx={{ alignItems: "center", height: 38 }}
                >
                    <Typography
                        id={titleID}
                        component="h2"
                        sx={{
                            flex: 1,
                            fontSize: 18,
                            lineHeight: "24px",
                            fontWeight: 600,
                        }}
                    >
                        {t("filters")}
                    </Typography>
                    <FilterButton
                        aria-label={t("close")}
                        onClick={() => setShowFilters(false)}
                        sx={{ borderRadius: "50%" }}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={16} />
                    </FilterButton>
                </Stack>
                <Box sx={{ mt: 2, maxHeight: "68dvh", overflowY: "auto" }}>
                    <Typography sx={{ fontSize: 14, fontWeight: 600, mb: 1 }}>
                        {t("people")}
                    </Typography>
                    <Stack
                        direction="row"
                        sx={{ flexWrap: "wrap", gap: "12px 8px" }}
                    >
                        {people.map((person) => (
                            <FaceFilter
                                key={person.id}
                                person={person}
                                selected={selectedPersonIDs.includes(person.id)}
                                avatarSize={48}
                                onClick={() => {
                                    togglePerson(person.id);
                                    setShowFilters(false);
                                }}
                            />
                        ))}
                    </Stack>
                </Box>
            </Dialog>
        </>
    );
};

// Match mobile's FaceFilterChip and FilterChipComponent: face-only, with an
// inverse surface and a small dismiss icon for applied filters.
const FaceFilter = ({
    person,
    selected,
    avatarSize = 32,
    onClick,
}: {
    person: Person;
    selected: boolean;
    avatarSize?: number;
    onClick: MouseEventHandler<HTMLButtonElement>;
}) => (
    <ButtonBase
        aria-label={person.name || t("unnamed_person")}
        aria-pressed={selected}
        onClick={onClick}
        sx={(theme) => ({
            "--people-face-size": `${avatarSize}px`,
            flexShrink: 0,
            minWidth: avatarSize + 8,
            height: avatarSize + 8,
            gap: "4px",
            p: "4px",
            pr: selected ? "8px" : "4px",
            borderRadius: `${(avatarSize + 8) / 2}px`,
            bgcolor: selected ? "#161616" : "#fff",
            color: "#fff",
            transition: "background-color 120ms ease-in-out",
            "&.Mui-focusVisible": {
                outline: "2px solid",
                outlineColor: "accent.main",
                outlineOffset: -2,
            },
            "@media (prefers-reduced-motion: reduce)": { transition: "none" },
            ...theme.applyStyles("dark", {
                bgcolor: selected ? "#f4f4f4" : "#212121",
                color: "#000",
            }),
        })}
    >
        <Box aria-hidden>
            <ItemCard
                TileComponent={FaceThumbnail}
                coverFile={person.displayFaceFile}
                coverFaceID={person.displayFaceID}
            />
        </Box>
        {selected && (
            <HugeiconsIcon icon={Cancel01Icon} size={14} aria-hidden />
        )}
    </ButtonBase>
);

const FaceThumbnail = styled("div")({
    width: "var(--people-face-size)",
    height: "var(--people-face-size)",
    position: "relative",
    overflow: "hidden",
    borderRadius: "50%",
    "& > img": {
        width: "100%",
        height: "100%",
        objectFit: "cover",
        display: "block",
    },
});

const FilterButton = styled(ButtonBase)(({ theme }) => ({
    width: 36,
    height: 36,
    flexShrink: 0,
    borderRadius: 12,
    backgroundColor: "#fff",
    color: "#000",
    "&.Mui-focusVisible": {
        outline: `2px solid ${theme.vars.palette.accent.main}`,
        outlineOffset: -2,
    },
    ...theme.applyStyles("dark", { backgroundColor: "#212121", color: "#fff" }),
}));
