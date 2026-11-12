import { PeopleSortOptions } from "@/components/PeopleSortOptions";
import type { PeopleSortBy } from "@/utils/people-sort";
import { PinIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { Box, ButtonBase, useMediaQuery, useTheme } from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, { memo, useEffect, useMemo, useRef, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    FixedSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";
import { usePhotosNavigation } from "../../navigation/PhotosNavigationContext";

import {
    BarCard,
    BarThumbnail,
    CardText,
    CollectionBarCardIcon_,
    NavigationEmptyState,
    NavigationFrame,
    type GalleryBarPresentationProps,
} from "../../navigation/NavigationPrimitives";
interface PeopleNavigationProps extends GalleryBarPresentationProps {
    people: Person[];
    activePerson: Person | undefined;
    peopleSortBy: PeopleSortBy;
    onChangePeopleSortBy: (sort: PeopleSortBy) => void;
}
export const PeopleNavigation = ({
    people,
    activePerson,
    peopleSortBy,
    onChangePeopleSortBy,
    collapsed,
    mobileDrawerProps,
}: PeopleNavigationProps) => {
    const { selectPerson, showPeople } = usePhotosNavigation();
    const { onClose } = mobileDrawerProps;
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const [searchQuery, setSearchQuery] = useState("");
    const [viewportHeight, setViewportHeight] = useState(0);
    const listRef = useRef<FixedSizeList>(null);
    const query = searchQuery.trim().toLowerCase();
    const isSearching = !!query;
    const matchingPeople = useMemo(
        () =>
            isSearching
                ? people.filter((p) => p.name?.toLowerCase().includes(query))
                : people,
        [people, isSearching, query],
    );
    useEffect(() => {
        if (mobile ? !mobileDrawerProps.open : collapsed) setSearchQuery("");
    }, [mobile, mobileDrawerProps.open, collapsed]);
    useEffect(() => {
        if (isSearching) listRef.current?.scrollTo(0);
    }, [searchQuery, isSearching]);
    useEffect(() => {
        if (isSearching) return;
        const index = matchingPeople.findIndex((p) => p.id == activePerson?.id);
        if (index != -1) listRef.current?.scrollToItem(index, "smart");
    }, [
        matchingPeople,
        activePerson,
        collapsed,
        mobile,
        mobileDrawerProps.open,
        viewportHeight,
        isSearching,
    ]);
    const itemData = useMemo(
        () => ({
            people: matchingPeople,
            activePerson,
            onSelectPerson: (id: string) => {
                selectPerson(id);
                onClose();
            },
        }),
        [matchingPeople, activePerson, selectPerson, onClose],
    );
    return (
        <NavigationFrame
            title={
                <ButtonBase
                    onClick={() => {
                        setSearchQuery("");
                        showPeople();
                        onClose();
                    }}
                    sx={{
                        font: "inherit",
                        justifyContent: "flex-start",
                        borderRadius: 1,
                        "&:hover": { color: "text.muted" },
                        "&.Mui-focusVisible": {
                            outline: "2px solid",
                            outlineColor: "primary.main",
                            outlineOffset: 2,
                        },
                    }}
                >
                    {t("people")}
                </ButtonBase>
            }
            actions={
                <PeopleSortOptions
                    variant="v2"
                    activeSortBy={peopleSortBy}
                    onChangeSortBy={onChangePeopleSortBy}
                />
            }
            searchPlaceholder={t("people_search_hint")}
            searchQuery={searchQuery}
            setSearchQuery={setSearchQuery}
            mobileDrawerProps={mobileDrawerProps}
        >
            {isSearching && !matchingPeople.length ? (
                <NavigationEmptyState />
            ) : (
                <Box sx={{ flex: 1, minHeight: 0, minWidth: 0 }}>
                    <AutoSizer
                        onResize={({ height }) => setViewportHeight(height)}
                    >
                        {({ width, height }) => (
                            <FixedSizeList
                                ref={listRef}
                                width={width}
                                height={height}
                                itemData={itemData}
                                itemKey={(index, data) =>
                                    `people-${data.people[index]!.id}-${data.people[index]!.displayFaceID}`
                                }
                                itemCount={matchingPeople.length}
                                itemSize={mobile ? 46 : 50}
                                style={{ overflowX: "hidden" }}
                            >
                                {PersonRow}
                            </FixedSizeList>
                        )}
                    </AutoSizer>
                </Box>
            )}
        </NavigationFrame>
    );
};
const PersonRow = memo(
    ({
        data,
        index,
        style,
    }: ListChildComponentProps<{
        people: Person[];
        activePerson: Person | undefined;
        onSelectPerson: (id: string) => void;
    }>) => (
        <div style={style}>
            <PersonCard
                person={data.people[index]!}
                activePerson={data.activePerson}
                onSelectPerson={data.onSelectPerson}
            />
        </div>
    ),
    areEqual,
);
interface PersonCardProps {
    person: Person;
    activePerson: Person | undefined;
    onSelectPerson: (personID: string) => void;
}

const PersonCard: React.FC<PersonCardProps> = ({
    person,
    activePerson,
    onSelectPerson,
}) => (
    <BarCard
        aria-label={person.name || t("unnamed_person")}
        aria-current={activePerson?.id === person.id ? "true" : undefined}
        title={person.name || t("unnamed_person")}
        onClick={() => onSelectPerson(person.id)}
    >
        <Box
            aria-hidden
            sx={{ flexShrink: 0, borderRadius: "50%", overflow: "hidden" }}
        >
            <ItemCard
                TileComponent={BarThumbnail}
                coverFile={person.displayFaceFile}
                coverFaceID={person.displayFaceID}
            />
        </Box>
        <CardText>{person.name || t("unnamed_person")}</CardText>
        {person.isPinned && (
            <CollectionBarCardIcon_ aria-hidden>
                <HugeiconsIcon icon={PinIcon} size={14} />
            </CollectionBarCardIcon_>
        )}
    </BarCard>
);
