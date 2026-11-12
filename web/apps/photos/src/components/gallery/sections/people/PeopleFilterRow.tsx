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
    type ReactNode,
} from "react";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

export const PeopleFilterRow = ({
    people,
    activePeople,
    onlyThem,
}: {
    people: Person[];
    activePeople: Person[];
    onlyThem: boolean;
}) => {
    const { togglePerson, togglePeopleOnlyThem } = usePhotosNavigation();
    const selectedPersonIDs = activePeople.map((person) => person.id);
    const canShowOnlyThem = activePeople.length > 0 && activePeople.length <= 4;
    const [showFilters, setShowFilters] = useState(false);
    const titleID = useId();
    const pendingChip = useRef<HTMLButtonElement | null>(null);
    useEffect(() => {
        pendingChip.current?.scrollIntoView({
            block: "nearest",
            inline: "nearest",
        });
        pendingChip.current = null;
    }, [activePeople]);
    const renderFilters = (avatarSize: number, limit?: number) => {
        const selected = people.filter((person) =>
            selectedPersonIDs.includes(person.id),
        );
        const suggestions = people.filter(
            (person) => !selectedPersonIDs.includes(person.id),
        );
        // The badge replaces the applied face chips, as on mobile.
        const filters: (Person | "only-them")[] = onlyThem
            ? ["only-them"]
            : [
                  ...selected,
                  ...(canShowOnlyThem ? ["only-them" as const] : []),
                  ...suggestions.slice(0, limit),
              ];
        return filters.map((filter) =>
            filter === "only-them" ? (
                <PeopleFilterChip
                    key="only-them"
                    name={t("only_them")}
                    label={t("only_them")}
                    selected={onlyThem}
                    avatarSize={avatarSize}
                    onClick={() => {
                        togglePeopleOnlyThem();
                        setShowFilters(false);
                    }}
                >
                    <PeopleFaceCollage people={activePeople} />
                </PeopleFilterChip>
            ) : (
                <FaceFilter
                    key={`person:${filter.id}`}
                    person={filter}
                    selected={selectedPersonIDs.includes(filter.id)}
                    avatarSize={avatarSize}
                    onClick={(event) => {
                        if (
                            avatarSize === 32 &&
                            !selectedPersonIDs.includes(filter.id)
                        )
                            pendingChip.current = event.currentTarget;
                        togglePerson(filter.id);
                        setShowFilters(false);
                    }}
                />
            ),
        );
    };
    if (!people.length && !canShowOnlyThem) return null;
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
                    disableRipple
                    aria-label={t("filters")}
                    aria-haspopup="dialog"
                    aria-expanded={showFilters}
                    onClick={() => setShowFilters(true)}
                >
                    <HugeiconsIcon icon={Menu08Icon} size={16} />
                </FilterButton>
                {renderFilters(32, canShowOnlyThem ? 13 : 14)}
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
                        disableRipple
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
                        {renderFilters(48)}
                    </Stack>
                </Box>
            </Dialog>
        </>
    );
};

const FaceFilter = ({
    person,
    ...props
}: {
    person: Person;
    selected: boolean;
    avatarSize?: number;
    onClick: MouseEventHandler<HTMLButtonElement>;
}) => (
    <PeopleFilterChip name={person.name || t("unnamed_person")} {...props}>
        <ItemCard
            TileComponent={FaceThumbnail}
            coverFile={person.displayFaceFile}
            coverFaceID={person.displayFaceID}
        />
    </PeopleFilterChip>
);

// Match mobile's FilterChipComponent, including the labeled Only them badge.
const PeopleFilterChip = ({
    name,
    label,
    selected,
    avatarSize = 32,
    onClick,
    children,
}: {
    name: string;
    label?: string;
    selected: boolean;
    avatarSize?: number;
    onClick: MouseEventHandler<HTMLButtonElement>;
    children: ReactNode;
}) => (
    <ButtonBase
        disableRipple
        aria-label={name}
        aria-pressed={selected}
        onClick={onClick}
        sx={(theme) => ({
            "--people-face-size": `${avatarSize}px`,
            flexShrink: 0,
            minWidth: avatarSize + 8,
            height: avatarSize + 8,
            gap: "4px",
            p: "4px",
            pr: selected ? "8px" : label ? "18px" : "4px",
            borderRadius: `${(avatarSize + 8) / 2}px`,
            bgcolor: label
                ? selected
                    ? "#d6d6d6"
                    : "#e8e8e8"
                : selected
                  ? "#161616"
                  : "#fff",
            color: label ? "#161616" : selected ? "#fff" : "rgba(0, 0, 0, 0.7)",
            transition: "background-color 120ms ease-in-out",
            "&.Mui-focusVisible": {
                outline: "2px solid",
                outlineColor: "accent.main",
                outlineOffset: -2,
            },
            "@media (prefers-reduced-motion: reduce)": { transition: "none" },
            ...theme.applyStyles("dark", {
                bgcolor: label
                    ? selected
                        ? "#d6d6d6"
                        : "#e8e8e8"
                    : selected
                      ? "#f4f4f4"
                      : "#212121",
                color: label
                    ? "#161616"
                    : selected
                      ? "#000"
                      : "rgba(255, 255, 255, 0.7)",
            }),
        })}
    >
        <Box aria-hidden>{children}</Box>
        {label && (
            <Typography
                component="span"
                sx={{ fontSize: 12, lineHeight: "16px", whiteSpace: "nowrap" }}
            >
                {label}
            </Typography>
        )}
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

const PeopleFaceCollage = ({ people }: { people: Person[] }) => (
    <Box
        sx={{
            width: "var(--people-face-size)",
            height: "var(--people-face-size)",
            borderRadius: "50%",
            overflow: "hidden",
            display: "grid",
            gap: "1px",
            gridTemplateColumns: people.length > 1 ? "1fr 1fr" : "1fr",
            gridTemplateRows: people.length > 2 ? "1fr 1fr" : "1fr",
        }}
    >
        {people.map((person, index) => (
            <Box
                key={person.id}
                sx={{
                    minWidth: 0,
                    minHeight: 0,
                    overflow: "hidden",
                    gridRow:
                        people.length === 3 && index === 0
                            ? "span 2"
                            : undefined,
                    borderRadius:
                        people.length === 3
                            ? ["0", "0 0 0 3px", "3px 0 0 0"][index]
                            : people.length === 4
                              ? [
                                    "0 0 3px 0",
                                    "0 0 0 3px",
                                    "0 3px 0 0",
                                    "3px 0 0 0",
                                ][index]
                              : 0,
                    "& > div": {
                        width: "100%",
                        height: "100%",
                        borderRadius: 0,
                    },
                }}
            >
                <ItemCard
                    TileComponent={FaceThumbnail}
                    coverFile={person.displayFaceFile}
                    coverFaceID={person.displayFaceID}
                />
            </Box>
        ))}
    </Box>
);

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
