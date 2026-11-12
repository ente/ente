import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import { Box, IconButton, Stack, Tooltip, Typography } from "@mui/material";
import { GalleryItemsHeaderAdapter } from "ente-new/photos/components/gallery/ListHeader";
import { ItemCard } from "ente-new/photos/components/Tiles";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import { useTranslation } from "react-i18next";
import { BarThumbnail } from "../../navigation/NavigationPrimitives";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

export const CombinedPeopleHeader = ({
    people,
    fileCount,
}: {
    people: Person[];
    fileCount: number;
}) => {
    const { backToPeople } = usePhotosNavigation();
    const { i18n } = useTranslation();
    const title = new Intl.ListFormat(i18n.resolvedLanguage, {
        type: "conjunction",
    }).format(people.map((person) => person.name || t("unnamed_person")));
    return (
        <GalleryItemsHeaderAdapter
            sx={{ display: "flex", alignItems: "center", gap: 2, minWidth: 0 }}
        >
            <Tooltip title={t("go_back")}>
                <IconButton
                    aria-label={t("go_back")}
                    onClick={backToPeople}
                    sx={{ width: 32, height: 32, flexShrink: 0 }}
                >
                    <ArrowBackIcon sx={{ fontSize: 20 }} />
                </IconButton>
            </Tooltip>
            <Stack
                aria-hidden
                direction="row"
                sx={{ flexShrink: 0, display: { xs: "none", sm: "flex" } }}
            >
                {people.slice(0, 3).map((person, index) => (
                    <Box
                        key={person.id}
                        sx={{
                            ml: index ? -1 : 0,
                            borderRadius: "50%",
                            overflow: "hidden",
                            border: "2px solid",
                            borderColor: "background.paper",
                        }}
                    >
                        <ItemCard
                            TileComponent={BarThumbnail}
                            coverFile={person.displayFaceFile}
                            coverFaceID={person.displayFaceID}
                        />
                    </Box>
                ))}
            </Stack>
            <Stack sx={{ minWidth: 0 }}>
                <Tooltip title={title}>
                    <Typography
                        component="h2"
                        noWrap
                        sx={{ fontSize: 24, fontWeight: 600 }}
                    >
                        {title}
                    </Typography>
                </Tooltip>
                <Typography
                    aria-live="polite"
                    sx={{ color: "text.muted", fontSize: 14 }}
                >
                    {t("photos_count", { count: fileCount })}
                </Typography>
            </Stack>
        </GalleryItemsHeaderAdapter>
    );
};
