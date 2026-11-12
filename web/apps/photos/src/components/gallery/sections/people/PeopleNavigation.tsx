import { PeopleSortOptions } from "@/components/PeopleSortOptions";
import type { PeopleSortBy } from "@/utils/people-sort";
import { PinIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import CheckIcon from "@mui/icons-material/Check";
import { Box, ButtonBase, useMediaQuery, useTheme } from "@mui/material";
import { ItemCard } from "ente-new/photos/components/Tiles";
import type { Person } from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, {
    memo,
    useEffect,
    useEffectEvent,
    useMemo,
    useRef,
    useState,
} from "react";
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
import { createPeoplePress } from "./people-press";

interface PeopleNavigationProps extends GalleryBarPresentationProps {
    people: Person[];
    selectedPersonIDs: string[];
    selectionMode: boolean;
    peopleSortBy: PeopleSortBy;
    onChangePeopleSortBy: (sort: PeopleSortBy) => void;
}
export const PeopleNavigation = ({
    people,
    selectedPersonIDs,
    selectionMode,
    peopleSortBy,
    onChangePeopleSortBy,
    collapsed,
    mobileDrawerProps,
}: PeopleNavigationProps) => {
    const {
        selectPerson,
        showPeople,
        beginPeopleSelection,
        togglePerson,
        exitPeopleSelection,
    } = usePhotosNavigation();
    const { onClose } = mobileDrawerProps;
    const mobile = useMediaQuery(useTheme().breakpoints.down("md"));
    const [searchQuery, setSearchQuery] = useState("");
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
    const revealSelection = useEffectEvent(() => {
        if (isSearching || selectionMode) return;
        const index = matchingPeople.findIndex((person) =>
            selectedPersonIDs.includes(person.id),
        );
        if (index !== -1) listRef.current?.scrollToItem(index, "smart");
    });
    useEffect(() => {
        revealSelection();
    }, [collapsed, mobile, mobileDrawerProps.open]);
    const itemData = useMemo(
        () => ({
            people: matchingPeople,
            selectedPersonIDs,
            selectionMode,
            onSelectPerson: (id: string) => {
                if (selectionMode) togglePerson(id);
                else {
                    selectPerson(id);
                    onClose();
                }
            },
            onHoldPerson: beginPeopleSelection,
        }),
        [
            matchingPeople,
            selectedPersonIDs,
            selectionMode,
            selectPerson,
            togglePerson,
            beginPeopleSelection,
            onClose,
        ],
    );
    return (
        <Box
            sx={{
                display: mobile ? "contents" : undefined,
                height: "100%",
                minHeight: 0,
            }}
            onKeyDownCapture={(event) => {
                if (event.key === "Escape" && selectionMode) {
                    event.preventDefault();
                    event.stopPropagation();
                    exitPeopleSelection();
                }
            }}
        >
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
                        <AutoSizer>
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
        </Box>
    );
};
const PersonRow = memo(
    ({
        data,
        index,
        style,
    }: ListChildComponentProps<{
        people: Person[];
        selectedPersonIDs: string[];
        selectionMode: boolean;
        onSelectPerson: (id: string) => void;
        onHoldPerson: (id: string) => void;
    }>) => (
        <div style={style}>
            <PersonCard
                person={data.people[index]!}
                selected={data.selectedPersonIDs.includes(
                    data.people[index]!.id,
                )}
                selectionMode={data.selectionMode}
                onHoldPerson={data.onHoldPerson}
                onSelectPerson={data.onSelectPerson}
            />
        </div>
    ),
    areEqual,
);
interface PersonCardProps {
    person: Person;
    selected: boolean;
    selectionMode: boolean;
    onSelectPerson: (personID: string) => void;
    onHoldPerson: (personID: string) => void;
}

const PersonCard: React.FC<PersonCardProps> = ({
    person,
    selected,
    selectionMode,
    onSelectPerson,
    onHoldPerson,
}) => {
    const press = useMemo(
        () => createPeoplePress(() => onHoldPerson(person.id)),
        [onHoldPerson, person.id],
    );
    useEffect(() => {
        window.addEventListener("scroll", press.cancel, true);
        window.addEventListener("blur", press.cancel);
        return () => {
            press.cancel();
            window.removeEventListener("scroll", press.cancel, true);
            window.removeEventListener("blur", press.cancel);
        };
    }, [press]);
    return (
        <BarCard
            aria-label={person.name || t("unnamed_person")}
            aria-current={selected ? "true" : undefined}
            aria-pressed={selected}
            onPointerDown={(event) => {
                if (event.button !== 0 || !event.isPrimary) return;
                press.start(event.clientX, event.clientY);
            }}
            onPointerMove={(event) => press.move(event.clientX, event.clientY)}
            onPointerUp={press.end}
            onPointerCancel={press.cancel}
            onPointerLeave={press.cancel}
            onContextMenu={(event) => {
                event.preventDefault();
                press.cancel();
            }}
            onKeyDown={(event) => {
                if (event.key === "Enter" && event.shiftKey) {
                    event.preventDefault();
                    if (!event.repeat) onHoldPerson(person.id);
                }
            }}
            onClick={(event) => {
                const suppressed = press.consumeClick();
                if (event.detail === 0 || !suppressed)
                    onSelectPerson(person.id);
            }}
            sx={{
                userSelect: "none",
                WebkitTouchCallout: "none",
                touchAction: "pan-y",
            }}
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
            {selectionMode && selected ? (
                <CheckIcon aria-hidden sx={{ fontSize: 18, flexShrink: 0 }} />
            ) : person.isPinned ? (
                <CollectionBarCardIcon_ aria-hidden>
                    <HugeiconsIcon icon={PinIcon} size={14} />
                </CollectionBarCardIcon_>
            ) : null}
        </BarCard>
    );
};
