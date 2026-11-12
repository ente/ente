import { sortPeople } from "@/utils/people-sort";
import { Box, Typography } from "@mui/material";
import { t } from "i18next";
import { useEffect, useMemo } from "react";
import { GalleryMedia } from "../../media/GalleryMedia";
import { GallerySectionLayout } from "../../navigation/GallerySectionLayout";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";
import type { GallerySectionProps } from "../types";
import { CombinedPeopleHeader } from "./CombinedPeopleHeader";
import { derivePeopleFilteredFiles, derivePeopleView } from "./people-files";
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
    const {
        personIDs,
        extraVisiblePersonIDs: retainedPersonIDs,
        peopleSelectionMode = false,
    } = navigation.destination;
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
    const { exitPeopleSelection } = usePhotosNavigation();
    useEffect(() => {
        if (!peopleSelectionMode) return;
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.key !== "Escape" || event.defaultPrevented) return;
            if (
                event.target instanceof Element &&
                event.target.closest('[role="dialog"], [role="menu"]')
            )
                return;
            exitPeopleSelection();
        };
        document.addEventListener("keydown", onKeyDown);
        return () => document.removeEventListener("keydown", onKeyDown);
    }, [peopleSelectionMode, exitPeopleSelection]);
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
    const activePerson =
        view.activePeople.length === 1 ? view.activePeople[0] : undefined;
    const combined = view.activePeople.length > 1;
    const visiblePeople = view.visiblePeople;
    const header = useMemo(
        () => ({
            component: combined ? (
                <CombinedPeopleHeader
                    people={view.activePeople}
                    fileCount={files.length}
                />
            ) : activePerson ? (
                <PeopleHeader person={activePerson} people={visiblePeople} />
            ) : (
                <></>
            ),
            height: 72,
        }),
        [
            activePerson,
            visiblePeople,
            combined,
            view.activePeople,
            files.length,
        ],
    );
    return (
        <GallerySectionLayout
            presentation={presentation}
            navigation={
                <PeopleNavigation
                    {...presentation}
                    people={people}
                    selectedPersonIDs={activePersonIDs}
                    selectionMode={peopleSelectionMode}
                    peopleSortBy={preferences.peopleSortBy}
                    onChangePeopleSortBy={preferences.setPeopleSortBy}
                />
            }
        >
            {!library.isFirstLoad && !view.activePeople.length ? (
                <PeopleOverview
                    people={view.visiblePeople}
                    allPeople={view.people}
                    peopleSortBy={preferences.peopleSortBy}
                />
            ) : combined && !files.length ? (
                <Box sx={{ flex: 1, minWidth: 0 }}>
                    {header.component}
                    <Typography
                        role="status"
                        sx={{ p: 4, textAlign: "center", color: "text.muted" }}
                    >
                        {t("people_all_empty")}
                    </Typography>
                </Box>
            ) : (
                <GalleryMedia
                    {...{ library, operations, navigation }}
                    header={header}
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
        </GallerySectionLayout>
    );
};
