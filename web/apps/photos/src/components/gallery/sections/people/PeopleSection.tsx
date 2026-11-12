import { sortPeople } from "@/utils/people-sort";
import { useEffect, useMemo } from "react";
import { GallerySectionLayout } from "../../navigation/GallerySectionLayout";
import type { GallerySectionProps } from "../types";
import { derivePeopleView } from "./people-files";
import { PeopleNavigation } from "./PeopleNavigation";
import { PeopleOverview } from "./PeopleOverview";
import { PersonPhotos } from "./PersonPhotos";

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
    const { retainPerson } = navigation;
    useEffect(() => {
        retainPerson(view.activePerson?.id, extraVisiblePerson?.id);
    }, [view.activePerson?.id, extraVisiblePerson?.id, retainPerson]);
    const people = useMemo(
        () => sortPeople(view.visiblePeople, preferences.peopleSortBy),
        [view.visiblePeople, preferences.peopleSortBy],
    );
    const activePerson = view.activePerson;
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
            {activePerson ? (
                <PersonPhotos
                    key={activePerson.id}
                    {...{ library, operations, navigation, view, activePerson }}
                />
            ) : !library.isFirstLoad ? (
                <PeopleOverview
                    people={view.visiblePeople}
                    allPeople={view.people}
                    peopleSortBy={preferences.peopleSortBy}
                />
            ) : null}
        </GallerySectionLayout>
    );
};
