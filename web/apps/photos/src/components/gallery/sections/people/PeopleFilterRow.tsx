import CloseIcon from "@mui/icons-material/Close";
import { Box, ButtonBase, Stack, Typography } from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import { BarThumbnail } from "../../navigation/NavigationPrimitives";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

export const PeopleFilterRow = ({
    people,
    selectedPersonIDs,
}: {
    people: Person[];
    selectedPersonIDs: string[];
}) => {
    const { togglePerson } = usePhotosNavigation();
    if (!people.length) return null;
    return (
        <Stack
            role="group"
            aria-label={t("people")}
            direction="row"
            sx={{
                gap: 1,
                overflowX: "auto",
                alignItems: "center",
                py: 1,
                minHeight: 56,
            }}
        >
            {people.map((person) => {
                const selected = selectedPersonIDs.includes(person.id);
                const name = person.name || t("unnamed_person");
                return (
                    <ButtonBase
                        key={person.id}
                        aria-label={name}
                        aria-pressed={selected}
                        onClick={() => togglePerson(person.id)}
                        sx={{
                            flexShrink: 0,
                            height: 40,
                            gap: 1,
                            pl: 0.75,
                            pr: 1.5,
                            borderRadius: "20px",
                            border: "1px solid",
                            borderColor: selected
                                ? "accent.main"
                                : "stroke.faint",
                            bgcolor: selected
                                ? "action.selected"
                                : "transparent",
                            "&:hover": { bgcolor: "action.hover" },
                            "&.Mui-focusVisible": {
                                outline: "2px solid",
                                outlineColor: "accent.main",
                                outlineOffset: -2,
                            },
                        }}
                    >
                        <Box
                            aria-hidden
                            sx={{
                                borderRadius: "50%",
                                overflow: "hidden",
                                flexShrink: 0,
                            }}
                        >
                            <ItemCard
                                TileComponent={BarThumbnail}
                                coverFile={person.displayFaceFile}
                                coverFaceID={person.displayFaceID}
                            />
                        </Box>
                        <Typography
                            component="span"
                            noWrap
                            sx={{ fontSize: 14, maxWidth: 140 }}
                        >
                            {name}
                        </Typography>
                        {selected && (
                            <CloseIcon aria-hidden sx={{ fontSize: 16 }} />
                        )}
                    </ButtonBase>
                );
            })}
        </Stack>
    );
};
