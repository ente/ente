import { sortPeople } from "@/utils/people-sort";
import { Box, Typography } from "@mui/material";
import { t } from "i18next";
import { useEffect, useMemo } from "react";
import { GalleryMedia } from "../../media/GalleryMedia";
import { GallerySectionLayout } from "../../navigation/GallerySectionLayout";
import type { GallerySectionProps } from "../types";
import {
    derivePeopleFilteredFiles,
    derivePeopleView,
    peopleFilterSuggestions,
} from "./people-files";
import { PeopleFilterRow } from "./PeopleFilterRow";
import { PeopleHeader } from "./PeopleHeader";
import { PeopleNavigation } from "./PeopleNavigation";
import { PeopleOverview } from "./PeopleOverview";

export const PeopleSection = ({
    library,
    operations,
    navigation,
    preferences,
    presentation,
}: GallerySectionProps) => {
    const { personIDs, extraVisiblePersonIDs: retainedPersonIDs } =
        navigation.destination;
    const { view, extraVisiblePersonIDs } = useMemo(
        () =>
            derivePeopleView(
                library.peopleState,
                library.tempDeletedFileIDs,
                library.tempHiddenFileIDs,
                personIDs,
                retainedPersonIDs,
            ),
        [
            library.peopleState,
            library.tempDeletedFileIDs,
            library.tempHiddenFileIDs,
            personIDs,
            retainedPersonIDs,
        ],
    );
    const files = useMemo(
        () =>
            derivePeopleFilteredFiles(
                library.collectionFiles,
                library.hiddenFileIDs,
                view,
                library.user?.id,
            ),
        [
            library.collectionFiles,
            library.hiddenFileIDs,
            view,
            library.user?.id,
        ],
    );
    const { retainPeople } = navigation;
    const activePersonIDs = useMemo(
        () => view.activePeople.map((person) => person.id),
        [view.activePeople],
    );
    useEffect(() => {
        if (library.peopleState)
            retainPeople(activePersonIDs, extraVisiblePersonIDs);
    }, [
        library.peopleState,
        activePersonIDs,
        extraVisiblePersonIDs,
        retainPeople,
    ]);
    const people = useMemo(
        () => sortPeople(view.visiblePeople, preferences.peopleSortBy),
        [view.visiblePeople, preferences.peopleSortBy],
    );
    const filterPeople = useMemo(
        () => peopleFilterSuggestions(view.people, view.activePeople, files),
        [view.people, view.activePeople, files],
    );
    const activePerson = view.activePeople[0];
    return (
        <GallerySectionLayout
            presentation={presentation}
            navigation={
                <PeopleNavigation
                    {...presentation}
                    people={people}
                    activePerson={activePerson}
                    peopleSortBy={preferences.peopleSortBy}
                    onChangePeopleSortBy={preferences.setPeopleSortBy}
                />
            }
        >
            {!library.isFirstLoad && !activePerson ? (
                <PeopleOverview
                    people={view.visiblePeople}
                    allPeople={view.people}
                    peopleSortBy={preferences.peopleSortBy}
                />
            ) : (
                <>
                    {activePerson && (
                        <Box sx={{ px: 3, pb: 1, flexShrink: 0, minWidth: 0 }}>
                            <PeopleHeader
                                person={activePerson}
                                people={view.visiblePeople}
                                fileCount={files.length}
                            />
                            <PeopleFilterRow
                                key={activePerson.id}
                                people={filterPeople}
                                selectedPersonIDs={activePersonIDs}
                            />
                        </Box>
                    )}
                    {view.activePeople.length > 1 && !files.length ? (
                        <Typography
                            role="status"
                            sx={{
                                p: 4,
                                textAlign: "center",
                                color: "text.muted",
                            }}
                        >
                            {t("people_all_empty")}
                        </Typography>
                    ) : (
                        <GalleryMedia
                            {...{ library, operations, navigation }}
                            source={{
                                mode: "people",
                                modePlus: "people",
                                files,
                                activeCollectionID: undefined,
                                activePersonIDs,
                                activeCollectionSummary: undefined,
                                disableGrouping: false,
                            }}
                        />
                    )}
                </>
            )}
        </GallerySectionLayout>
    );
};
