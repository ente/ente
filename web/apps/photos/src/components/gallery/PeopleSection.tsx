import { sortPeople } from "@/utils/people-sort";
import { useEffect, useMemo } from "react";
import { GalleryMedia } from "./GalleryMedia";
import { GallerySectionLayout } from "./GallerySectionLayout";
import { derivePeopleFilteredFiles, derivePeopleView } from "./people-files";
import { PeopleHeader } from "./PeopleHeader";
import { PeopleNavigation } from "./PeopleNavigation";
import { PeopleOverview } from "./PeopleOverview";
import type { GallerySectionProps } from "./section-types";

export const PeopleSection = ({
    library,
    operations,
    navigation,
    preferences,
    presentation,
}: GallerySectionProps) => {
    const { personID, extraVisiblePersonID } = navigation.destination;
    const { view, extraVisiblePerson } = useMemo(
        () =>
            derivePeopleView(
                library.peopleState,
                library.tempDeletedFileIDs,
                library.tempHiddenFileIDs,
                personID,
                library.peopleState?.people.find(
                    (p) => p.id === extraVisiblePersonID,
                ),
            ),
        [
            library.peopleState,
            library.tempDeletedFileIDs,
            library.tempHiddenFileIDs,
            personID,
            extraVisiblePersonID,
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
    const { retainPerson } = navigation;
    useEffect(() => {
        retainPerson(view.activePerson?.id, extraVisiblePerson?.id);
    }, [view.activePerson?.id, extraVisiblePerson?.id, retainPerson]);
    const people = useMemo(
        () => sortPeople(view.visiblePeople, preferences.peopleSortBy),
        [view.visiblePeople, preferences.peopleSortBy],
    );
    const activePerson = view.activePerson;
    const visiblePeople = view.visiblePeople;
    const header = useMemo(
        () => ({
            component: activePerson ? (
                <PeopleHeader person={activePerson} people={visiblePeople} />
            ) : (
                <></>
            ),
            height: 72,
        }),
        [activePerson, visiblePeople],
    );
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
                <GalleryMedia
                    {...{ library, operations, navigation }}
                    header={header}
                    source={{
                        mode: "people",
                        modePlus: "people",
                        files,
                        activeCollectionID: undefined,
                        activePersonID: activePerson?.id,
                        activeCollectionSummary: undefined,
                        disableGrouping: false,
                    }}
                />
            )}
        </GallerySectionLayout>
    );
};
