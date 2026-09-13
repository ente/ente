import {
    CollectionDialogSearchField,
    CollectionTileButton,
} from "@/components/CollectionDialog/Primitives";
import {
    collectionDialogBodyMutedSx,
    collectionDialogCornerRadius,
    collectionDialogDividerSx,
    collectionDialogHeaderActionsSx,
    collectionDialogHeaderRowSx,
    collectionDialogHeaderSx,
    collectionDialogIconButtonSx,
    collectionDialogSurfaceStroke,
    collectionDialogSurfaceStrokeDark,
    collectionDialogTitleSx,
} from "@/components/CollectionDialog/styles";
import { PeopleSortOptions } from "@/components/PeopleSortOptions";
import { useWrapAsyncOperation } from "@/components/utils/use-wrap-async";
import { sortPeople, type PeopleSortBy } from "@/utils/people-sort";
import {
    ArrowDownDoubleIcon,
    ArrowUpDoubleIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AddIcon from "@mui/icons-material/Add";
import CloseIcon from "@mui/icons-material/Close";
import EditIcon from "@mui/icons-material/Edit";
import HideImageOutlinedIcon from "@mui/icons-material/HideImageOutlined";
import MoreHorizIcon from "@mui/icons-material/MoreHoriz";
import PushPinIcon from "@mui/icons-material/PushPin";
import PushPinOutlinedIcon from "@mui/icons-material/PushPinOutlined";
import {
    Box,
    Button,
    Dialog,
    DialogContent,
    IconButton,
    Stack,
    Tooltip,
    Typography,
    styled,
    useMediaQuery,
} from "@mui/material";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useBaseContext } from "ente-base/context";
import { SlideUpTransition } from "ente-new/photos/components/mui/SlideUpTransition";
import {
    ItemCard,
    LargeTileButton,
    LargeTileCreateNewButton,
    LargeTileTextOverlay,
} from "ente-new/photos/components/Tiles";
import {
    addCGroup,
    addClusterToCGroup,
    ignoreCluster,
    pinCGroup,
    renameCGroup,
    unpinCGroup,
} from "ente-new/photos/services/ml";
import type { FaceCluster } from "ente-new/photos/services/ml/cluster";
import type {
    CGroupPerson,
    ClusterPerson,
    Person,
} from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import memoize from "memoize-one";
import React, { useEffect, useId, useMemo, useRef, useState } from "react";
import AutoSizer from "react-virtualized-auto-sizer";
import {
    VariableSizeList,
    areEqual,
    type ListChildComponentProps,
} from "react-window";

interface AllPeopleProps {
    open: boolean;
    onClose: () => void;
    people: Person[];
    allPeople: Person[];
    onSelectPerson: (id: string) => void;
    peopleSortBy: PeopleSortBy;
    onChangePeopleSortBy: (by: PeopleSortBy) => void;
}

export const AllPeople: React.FC<AllPeopleProps> = ({
    open,
    onClose,
    people,
    allPeople,
    onSelectPerson,
    peopleSortBy,
    onChangePeopleSortBy,
}) => {
    const titleID = useId();
    const fullScreen = useMediaQuery("(max-width: 428px)");
    const { showMiniDialog } = useBaseContext();
    const [searchTerm, setSearchTerm] = useState("");
    const [showingAllPeople, setShowingAllPeople] = useState(false);
    const [personToRename, setPersonToRename] = useState<CGroupPerson>();
    const [clusterToName, setClusterToName] = useState<ClusterPerson>();

    const handleExited = () => {
        setSearchTerm("");
        setShowingAllPeople(false);
    };

    const handleSelectPerson = (personID: string) => {
        onSelectPerson(personID);
        onClose();
    };

    const handleRenamePerson = async (name: string) => {
        if (!personToRename) return;
        await renameCGroup(personToRename.cgroup, name);
        setPersonToRename(undefined);
    };

    const handlePinPerson = useWrapAsyncOperation(
        async (person: CGroupPerson) =>
            person.isPinned
                ? unpinCGroup(person.cgroup)
                : pinCGroup(person.cgroup),
    );

    const handleIgnorePerson = (person: ClusterPerson) => {
        showMiniDialog({
            title: t("ignore_person_confirm"),
            message: t("ignore_person_confirm_message"),
            continue: {
                text: t("ignore"),
                color: "primary",
                action: () => ignoreCluster(person.cluster),
            },
        });
    };

    const hasSearchQuery = !!searchTerm.trim();

    const extraPeople = useMemo(() => {
        const visiblePersonIDs = new Set(people.map(({ id }) => id));
        const extra = allPeople.filter(
            (person) =>
                !visiblePersonIDs.has(person.id) &&
                !(person.type == "cgroup" && person.isHidden),
        );
        return sortPeople(extra, peopleSortBy);
    }, [allPeople, people, peopleSortBy]);

    const handleToggleShowingAllPeople = () => {
        setShowingAllPeople((value) => !value);
    };

    const searchablePeople = useMemo(
        () =>
            showingAllPeople || people.length == 0
                ? sortPeople(people.concat(extraPeople), peopleSortBy)
                : people,
        [extraPeople, people, peopleSortBy, showingAllPeople],
    );

    const filteredSearchPeople = useMemo(() => {
        if (!searchTerm.trim()) {
            return searchablePeople;
        }

        const searchLower = searchTerm.toLowerCase();
        return searchablePeople.filter((person) =>
            person.name?.toLowerCase().includes(searchLower),
        );
    }, [searchTerm, searchablePeople]);

    const primaryPeople = hasSearchQuery
        ? filteredSearchPeople
        : people.length == 0
          ? extraPeople
          : people;
    const expandedPeople =
        !hasSearchQuery && showingAllPeople && people.length > 0
            ? extraPeople
            : [];

    const visiblePeopleCount = primaryPeople.length + expandedPeople.length;
    const totalPeopleCount = hasSearchQuery
        ? searchablePeople.length
        : visiblePeopleCount;

    return (
        <>
            <AllPeopleDialog
                {...{ open, onClose, fullScreen }}
                aria-labelledby={titleID}
                fullWidth
                slots={{ transition: SlideUpTransition }}
                slotProps={{ transition: { onExited: handleExited } }}
            >
                <Title
                    id={titleID}
                    onClose={onClose}
                    peopleCount={visiblePeopleCount}
                    totalCount={totalPeopleCount}
                    searchTerm={searchTerm}
                    onSearchChange={setSearchTerm}
                    peopleSortBy={peopleSortBy}
                    onChangePeopleSortBy={onChangePeopleSortBy}
                />
                <Box sx={collectionDialogDividerSx} />
                <AllPeopleContent
                    primaryPeople={primaryPeople}
                    expandedPeople={expandedPeople}
                    hasSearchQuery={hasSearchQuery}
                    showMoreFacesButton={
                        people.length > 0 && extraPeople.length > 0
                    }
                    showingAllPeople={showingAllPeople}
                    onToggleShowingAllPeople={handleToggleShowingAllPeople}
                    onSelectPerson={handleSelectPerson}
                    onRenamePerson={setPersonToRename}
                    onPinPerson={handlePinPerson}
                    onAddName={setClusterToName}
                    onIgnorePerson={handleIgnorePerson}
                />
            </AllPeopleDialog>
            <SingleInputDialog
                open={!!personToRename}
                onClose={() => setPersonToRename(undefined)}
                title={t("rename_person")}
                label={t("name")}
                placeholder={t("enter_name")}
                autoComplete="name"
                initialValue={personToRename?.name ?? ""}
                submitButtonColor="primary"
                submitButtonTitle={t("rename")}
                onSubmit={handleRenamePerson}
            />
            <AddPersonDialog
                open={!!clusterToName}
                onClose={() => setClusterToName(undefined)}
                people={people}
                cluster={clusterToName?.cluster}
            />
        </>
    );
};

const Column3To2Breakpoint = 559;
const PeopleGridGap = 8;
const PeopleGridPaddingInline = 20;
const PeopleGridPaddingBottom = 20;
const ShowMoreFacesButtonHeight = 56;
const ShowMoreFacesButtonVerticalGap = 16;
const ShowMoreFacesRowItemSize =
    ShowMoreFacesButtonHeight + 2 * ShowMoreFacesButtonVerticalGap;
const ExpandedPeopleTopSpacing = 4;
const PeopleListTopSpacing = 16;
const personCardShellClassName = "all-people-person-card";

const AllPeopleDialog = styled(Dialog)(({ theme }) => ({
    "& .MuiDialog-container": { justifyContent: "flex-end" },
    "& .MuiPaper-root": { maxWidth: "500px" },
    "& .MuiDialog-paper": {
        border: `1px solid ${collectionDialogSurfaceStroke}`,
        backgroundColor: "#f4f4f4",
        backgroundImage: "none",
        boxShadow: "none",
        ...theme.applyStyles("dark", {
            borderColor: collectionDialogSurfaceStrokeDark,
            backgroundColor: "#1b1b1b",
        }),
        borderRadius: `${collectionDialogCornerRadius}px`,
        overflow: "hidden",
        "&:not(.MuiDialog-paperFullScreen) .MuiDialogContent-root": {
            marginBottom: 0,
        },
        "&.MuiDialog-paperFullScreen": { borderRadius: 0, border: "none" },
    },
    "& .MuiDialogContent-root": { padding: theme.spacing(2) },
    [theme.breakpoints.down(Column3To2Breakpoint)]: {
        "& .MuiPaper-root": { width: "324px" },
        "& .MuiDialogContent-root": { padding: 6 },
    },
}));

type TitleProps = {
    id: string;
    peopleCount: number;
    totalCount: number;
    searchTerm: string;
    onSearchChange: (value: string) => void;
    peopleSortBy: PeopleSortBy;
    onChangePeopleSortBy: (by: PeopleSortBy) => void;
} & Pick<AllPeopleProps, "onClose">;

const Title: React.FC<TitleProps> = ({
    id,
    onClose,
    peopleCount,
    totalCount,
    searchTerm,
    onSearchChange,
    peopleSortBy,
    onChangePeopleSortBy,
}) => (
    <Stack sx={collectionDialogHeaderSx}>
        <Stack direction="row" sx={collectionDialogHeaderRowSx}>
            <Stack sx={{ minWidth: 0, gap: "2px" }}>
                <Typography id={id} component="h2" sx={collectionDialogTitleSx}>
                    {t("people")}
                </Typography>
                <Typography sx={collectionDialogBodyMutedSx}>
                    {searchTerm
                        ? `${peopleCount} / ${totalCount} ${t("people")}`
                        : `${peopleCount} ${t("people")}`}
                </Typography>
            </Stack>
            <Stack direction="row" sx={collectionDialogHeaderActionsSx}>
                <PeopleSortOptions
                    activeSortBy={peopleSortBy}
                    onChangeSortBy={onChangePeopleSortBy}
                    nestedInDialog
                    albumStyleTrigger
                />
                <IconButton
                    aria-label={t("close")}
                    onClick={onClose}
                    sx={collectionDialogIconButtonSx}
                >
                    <CloseIcon sx={{ fontSize: 18 }} />
                </IconButton>
            </Stack>
        </Stack>
        <SearchField value={searchTerm} onChange={onSearchChange} />
    </Stack>
);

interface SearchFieldProps {
    value: string;
    onChange: (value: string) => void;
}

const SearchField: React.FC<SearchFieldProps> = ({ value, onChange }) => {
    const inputRef = useRef<HTMLInputElement>(null);

    useEffect(() => {
        const timeout = window.setTimeout(() => {
            inputRef.current?.focus();
            inputRef.current?.select();
        }, 0);

        return () => window.clearTimeout(timeout);
    }, []);

    return (
        <CollectionDialogSearchField
            inputRef={inputRef}
            placeholder={`${t("people_search_hint")}...`}
            value={value}
            onChange={onChange}
        />
    );
};

interface AllPeopleContentProps {
    primaryPeople: Person[];
    expandedPeople: Person[];
    hasSearchQuery: boolean;
    showMoreFacesButton: boolean;
    showingAllPeople: boolean;
    onToggleShowingAllPeople: () => void;
    onSelectPerson: (id: string) => void;
    onRenamePerson: (person: CGroupPerson) => void;
    onPinPerson: (person: CGroupPerson) => void | Promise<void>;
    onAddName: (person: ClusterPerson) => void;
    onIgnorePerson: (person: ClusterPerson) => void;
}

type PeopleListItem =
    | { type: "people"; people: Person[]; topSpacing?: boolean }
    | { type: "showMoreButton" };

interface ItemData extends Pick<
    AllPeopleContentProps,
    | "showingAllPeople"
    | "onToggleShowingAllPeople"
    | "onSelectPerson"
    | "onRenamePerson"
    | "onPinPerson"
    | "onAddName"
    | "onIgnorePerson"
> {
    items: PeopleListItem[];
    tileSize: number;
}

const createItemData = memoize(
    (
        items: PeopleListItem[],
        showingAllPeople: boolean,
        onToggleShowingAllPeople: () => void,
        onSelectPerson: (id: string) => void,
        onRenamePerson: (person: CGroupPerson) => void,
        onPinPerson: (person: CGroupPerson) => void | Promise<void>,
        onAddName: (person: ClusterPerson) => void,
        onIgnorePerson: (person: ClusterPerson) => void,
        tileSize: number,
    ) => ({
        items,
        tileSize,
        showingAllPeople,
        onToggleShowingAllPeople,
        onSelectPerson,
        onRenamePerson,
        onPinPerson,
        onAddName,
        onIgnorePerson,
    }),
);

const peopleListItems = (
    people: Person[],
    columns: number,
    firstRowTopSpacing = false,
): PeopleListItem[] => {
    const items: PeopleListItem[] = [];
    for (let index = 0; index < people.length; index += columns) {
        items.push({
            type: "people",
            people: people.slice(index, index + columns),
            topSpacing: firstRowTopSpacing && index == 0,
        });
    }
    return items;
};

const peopleListItemSize = (
    item: PeopleListItem | undefined,
    tileSize: number,
) => {
    switch (item?.type) {
        case "showMoreButton":
            return ShowMoreFacesRowItemSize;
        default:
            return (
                tileSize +
                PeopleGridGap +
                (item?.topSpacing ? ExpandedPeopleTopSpacing : 0)
            );
    }
};

const PeopleRow = React.memo(
    ({ data, index, style }: ListChildComponentProps<ItemData>) => {
        const {
            items,
            tileSize,
            showingAllPeople,
            onToggleShowingAllPeople,
            onSelectPerson,
            onRenamePerson,
            onPinPerson,
            onAddName,
            onIgnorePerson,
        } = data;
        const item = items[index]!;

        if (item.type == "showMoreButton") {
            return (
                <div style={style}>
                    <ShowMoreFacesButton
                        showingAllPeople={showingAllPeople}
                        onClick={onToggleShowingAllPeople}
                    />
                </div>
            );
        }

        return (
            <div style={style}>
                <Stack
                    direction="row"
                    sx={{
                        boxSizing: "border-box",
                        height: "100%",
                        "--tile-size": `${tileSize}px`,
                        px: `${PeopleGridPaddingInline}px`,
                        pt: item.topSpacing
                            ? `${ExpandedPeopleTopSpacing}px`
                            : 0,
                        pb: `${PeopleGridGap}px`,
                        gap: `${PeopleGridGap}px`,
                    }}
                >
                    {item.people.map((person) => (
                        <PersonCard
                            key={person.id}
                            person={person}
                            onSelectPerson={onSelectPerson}
                            onRenamePerson={onRenamePerson}
                            onPinPerson={onPinPerson}
                            onAddName={onAddName}
                            onIgnorePerson={onIgnorePerson}
                        />
                    ))}
                </Stack>
            </div>
        );
    },
    areEqual,
);

const AllPeopleContent: React.FC<AllPeopleContentProps> = ({
    primaryPeople,
    expandedPeople,
    hasSearchQuery,
    showMoreFacesButton,
    showingAllPeople,
    onToggleShowingAllPeople,
    onSelectPerson,
    onRenamePerson,
    onPinPerson,
    onAddName,
    onIgnorePerson,
}) => {
    const isTwoColumn = useMediaQuery(`(width < ${Column3To2Breakpoint}px)`);
    const columns = isTwoColumn ? 2 : 3;
    const listOuterRef = useRef<HTMLDivElement>(null);
    const listRef = useRef<VariableSizeList<ItemData>>(null);
    const contentRef = useRef<HTMLDivElement>(null);
    const [contentWidth, setContentWidth] = useState(0);
    const noResults = hasSearchQuery && primaryPeople.length === 0;
    useEffect(() => {
        const element = contentRef.current;
        if (!element) return;
        const observer = new ResizeObserver(([entry]) => {
            if (entry) setContentWidth(entry.contentRect.width);
        });
        observer.observe(element);
        return () => observer.disconnect();
    }, [noResults]);
    const tileSize = Math.max(
        0,
        Math.floor(
            (contentWidth -
                2 * PeopleGridPaddingInline -
                (columns - 1) * PeopleGridGap) /
                columns,
        ),
    );

    useEffect(() => {
        // Refresh cached row heights without resetting the scroll position.
        listRef.current?.resetAfterIndex(0);
    }, [tileSize]);

    const shouldShowMoreFacesButton = showMoreFacesButton && !hasSearchQuery;
    const shouldShowExpandedPeople =
        showingAllPeople && expandedPeople.length > 0;

    const items = useMemo(() => {
        const items = peopleListItems(primaryPeople, columns);

        if (shouldShowMoreFacesButton) {
            items.push({ type: "showMoreButton" });
        }

        if (shouldShowMoreFacesButton && shouldShowExpandedPeople) {
            items.push(...peopleListItems(expandedPeople, columns, true));
        }

        return items;
    }, [
        columns,
        expandedPeople,
        primaryPeople,
        shouldShowExpandedPeople,
        shouldShowMoreFacesButton,
    ]);

    const handleToggleShowingAllPeople = () => {
        onToggleShowingAllPeople();
        if (!showingAllPeople && shouldShowMoreFacesButton) {
            window.requestAnimationFrame(() => {
                listOuterRef.current?.scrollBy({
                    top: ShowMoreFacesRowItemSize,
                    behavior: "smooth",
                });
            });
        }
    };

    const itemData = createItemData(
        items,
        showingAllPeople,
        handleToggleShowingAllPeople,
        onSelectPerson,
        onRenamePerson,
        onPinPerson,
        onAddName,
        onIgnorePerson,
        tileSize,
    );

    if (hasSearchQuery && primaryPeople.length === 0) {
        return (
            <DialogContent sx={{ height: "80svh" }}>
                <CenteredMessage>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("no_results")}
                    </Typography>
                </CenteredMessage>
            </DialogContent>
        );
    }

    const itemSize = (index: number) =>
        peopleListItemSize(items[index], tileSize);
    const listContentHeight =
        PeopleListTopSpacing +
        PeopleGridPaddingBottom +
        items.reduce(
            (height, item) => height + peopleListItemSize(item, tileSize),
            0,
        );
    const primaryRowCount = Math.ceil(primaryPeople.length / columns);
    const listKey = `${columns}-${shouldShowMoreFacesButton ? "with-button" : "no-button"}-${primaryRowCount}`;

    return (
        <DialogContent
            sx={{
                "&&": { padding: 0 },
                height:
                    hasSearchQuery || items.length === 0
                        ? "80svh"
                        : `min(80svh, ${listContentHeight}px)`,
                display: "flex",
                flexDirection: "column",
            }}
        >
            <Box
                ref={contentRef}
                sx={{
                    flex: 1,
                    minHeight: 0,
                    pt: `${PeopleListTopSpacing}px`,
                    pb: `${PeopleGridPaddingBottom}px`,
                }}
            >
                <AutoSizer>
                    {({ width, height }) => (
                        <VariableSizeList
                            {...{ width, height }}
                            ref={listRef}
                            outerRef={listOuterRef}
                            key={listKey}
                            itemCount={items.length}
                            itemSize={itemSize}
                            itemData={itemData}
                        >
                            {PeopleRow}
                        </VariableSizeList>
                    )}
                </AutoSizer>
            </Box>
        </DialogContent>
    );
};

interface ShowMoreFacesButtonProps {
    showingAllPeople: boolean;
    onClick: () => void;
}

const ShowMoreFacesButton: React.FC<ShowMoreFacesButtonProps> = ({
    showingAllPeople,
    onClick,
}) => (
    <Box
        sx={{
            px: `${PeopleGridPaddingInline}px`,
            py: `${ShowMoreFacesButtonVerticalGap}px`,
        }}
    >
        <Button
            fullWidth
            variant="text"
            onClick={onClick}
            startIcon={
                <HugeiconsIcon
                    icon={
                        showingAllPeople
                            ? ArrowUpDoubleIcon
                            : ArrowDownDoubleIcon
                    }
                    size={20}
                    strokeWidth={1.5}
                />
            }
            sx={{
                color: "text.base",
                backgroundColor: "fill.faint",
                border: 0,
                borderRadius: "16px",
                height: `${ShowMoreFacesButtonHeight}px`,
                minHeight: `${ShowMoreFacesButtonHeight}px`,
                "&:hover": { backgroundColor: "fill.muted" },
            }}
        >
            {showingAllPeople
                ? t("show_less_faces", { defaultValue: "Show fewer faces" })
                : t("show_more_faces", { defaultValue: "Show more faces" })}
        </Button>
    </Box>
);

const CenteredMessage = styled(Box)({
    display: "flex",
    justifyContent: "center",
    alignItems: "center",
    height: "100%",
});

interface PersonCardProps {
    person: Person;
    onSelectPerson: (id: string) => void;
    onRenamePerson: (person: CGroupPerson) => void;
    onPinPerson: (person: CGroupPerson) => void | Promise<void>;
    onAddName: (person: ClusterPerson) => void;
    onIgnorePerson: (person: ClusterPerson) => void;
}

const PersonCard: React.FC<PersonCardProps> = ({
    person,
    onSelectPerson,
    onRenamePerson,
    onPinPerson,
    onAddName,
    onIgnorePerson,
}) => (
    <PersonCardShell className={personCardShellClassName}>
        <ItemCard
            TileComponent={CollectionTileButton}
            coverFile={person.displayFaceFile}
            coverFaceID={person.displayFaceID}
            onClick={() => onSelectPerson(person.id)}
        >
            <LargeTileTextOverlay>
                {person.name && (
                    <Tooltip title={person.name} arrow>
                        <Typography
                            variant="body"
                            sx={{
                                maxWidth: "118px",
                                overflow: "hidden",
                                textOverflow: "ellipsis",
                                display: "-webkit-box",
                                WebkitLineClamp: 2,
                                WebkitBoxOrient: "vertical",
                            }}
                        >
                            {person.name}
                        </Typography>
                    </Tooltip>
                )}
                <Typography variant="small" sx={{ opacity: 0.7 }}>
                    {t("photos_count", { count: person.fileIDs.length })}
                </Typography>
            </LargeTileTextOverlay>
            {person.isPinned && (
                <PinnedIconContainer>
                    <PushPinIcon sx={{ fontSize: 20, color: "white" }} />
                </PinnedIconContainer>
            )}
        </ItemCard>
        <PersonActionMenu
            person={person}
            onRenamePerson={onRenamePerson}
            onPinPerson={onPinPerson}
            onAddName={onAddName}
            onIgnorePerson={onIgnorePerson}
        />
    </PersonCardShell>
);

const PersonCardShell = styled("div")`
    position: relative;
    flex: none;
    width: var(--tile-size);
    height: var(--tile-size);
`;

const PinnedIconContainer = styled(Box)`
    position: absolute;
    inset-inline-end: 8px;
    inset-block-end: 8px;
    display: flex;
`;

interface PersonActionMenuProps {
    person: Person;
    onRenamePerson: (person: CGroupPerson) => void;
    onPinPerson: (person: CGroupPerson) => void | Promise<void>;
    onAddName: (person: ClusterPerson) => void;
    onIgnorePerson: (person: ClusterPerson) => void;
}

const PersonActionMenu: React.FC<PersonActionMenuProps> = ({
    person,
    onRenamePerson,
    onPinPerson,
    onAddName,
    onIgnorePerson,
}) => {
    const menuOptions =
        person.type === "cgroup"
            ? [
                  <OverflowMenuOption
                      key="rename"
                      compact
                      startIcon={<EditIcon />}
                      onClick={() => onRenamePerson(person)}
                  >
                      {t("rename")}
                  </OverflowMenuOption>,
                  person.isPinned ? (
                      <OverflowMenuOption
                          key="unpin"
                          compact
                          startIcon={<PushPinOutlinedIcon />}
                          onClick={() => void onPinPerson(person)}
                      >
                          {t("unpin_person")}
                      </OverflowMenuOption>
                  ) : (
                      <OverflowMenuOption
                          key="pin"
                          compact
                          startIcon={<PushPinIcon />}
                          onClick={() => void onPinPerson(person)}
                      >
                          {t("pin_person")}
                      </OverflowMenuOption>
                  ),
              ]
            : [
                  <OverflowMenuOption
                      key="add-name"
                      compact
                      startIcon={<AddIcon />}
                      onClick={() => onAddName(person)}
                  >
                      {t("add_a_name")}
                  </OverflowMenuOption>,
                  <OverflowMenuOption
                      key="ignore"
                      compact
                      startIcon={<HideImageOutlinedIcon />}
                      onClick={() => onIgnorePerson(person)}
                  >
                      {t("ignore")}
                  </OverflowMenuOption>,
              ];

    return (
        <ActionMenuContainer>
            <OverflowMenu
                ariaID={`person-modal-options-${person.id}`}
                triggerButtonIcon={<MoreHorizIcon sx={{ fontSize: 18 }} />}
                triggerButtonSxProps={{
                    color: "white",
                    minWidth: 24,
                    minHeight: 24,
                    padding: "2px",
                    opacity: 0.9,
                    "&:hover": { backgroundColor: "transparent", opacity: 1 },
                }}
                menuPaperSxProps={{ minWidth: 176, width: 176 }}
            >
                {menuOptions}
            </OverflowMenu>
        </ActionMenuContainer>
    );
};

const ActionMenuContainer = styled(Box)`
    position: absolute;
    inset-block-start: 8px;
    inset-inline-end: 8px;
    z-index: 1;
    opacity: 0;
    pointer-events: none;
    transition: opacity 120ms ease;

    .${personCardShellClassName}:hover &,
    .${personCardShellClassName}:focus-within & {
        opacity: 1;
        pointer-events: auto;
    }

    @media (hover: none) {
        opacity: 1;
        pointer-events: auto;
    }
`;

interface AddPersonDialogProps {
    open: boolean;
    onClose: () => void;
    people: Person[];
    cluster: FaceCluster | undefined;
}

const AddPersonDialog: React.FC<AddPersonDialogProps> = ({
    open,
    onClose,
    people,
    cluster,
}) => {
    const isFullScreen = useMediaQuery("(max-width: 490px)");
    const [openNameInput, setOpenNameInput] = useState(false);

    const cgroupPeople: CGroupPerson[] = people.filter(
        (person): person is CGroupPerson => person.type != "cluster",
    );

    useEffect(() => {
        if (!open) {
            setOpenNameInput(false);
            return;
        }
        if (!cgroupPeople.length) {
            setOpenNameInput(true);
        }
    }, [open, cgroupPeople.length]);

    const handleAddPerson = () => setOpenNameInput(true);

    const handleAddPersonBySelect = useWrapAsyncOperation(
        async (personID: string) => {
            if (!cluster) return;
            const person = cgroupPeople.find((p) => p.id == personID);
            if (!person) return;

            await addClusterToCGroup(person.cgroup, cluster);
            setOpenNameInput(false);
            onClose();
        },
    );

    const handleAddPersonWithName = async (name: string) => {
        if (!cluster) return;
        await addCGroup(name, cluster);
        setOpenNameInput(false);
        onClose();
    };

    return (
        <>
            <Dialog
                open={open && !openNameInput && cgroupPeople.length > 0}
                onClose={onClose}
                fullWidth
                fullScreen={isFullScreen}
                slotProps={{ paper: { sx: { maxWidth: "490px" } } }}
            >
                <DialogTitle_>
                    <Typography variant="h3">{t("add_name")}</Typography>
                    <DialogCloseIconButton {...{ onClose }} />
                </DialogTitle_>
                <DialogContent_>
                    <LargeTileCreateNewButton onClick={handleAddPerson}>
                        {t("new_person")}
                    </LargeTileCreateNewButton>
                    {cgroupPeople.map((person) => (
                        <PersonPickerCard
                            key={person.id}
                            person={person}
                            onPersonClick={handleAddPersonBySelect}
                        />
                    ))}
                </DialogContent_>
            </Dialog>

            <SingleInputDialog
                open={openNameInput}
                onClose={() => {
                    setOpenNameInput(false);
                    if (!cgroupPeople.length) {
                        onClose();
                    }
                }}
                title={t("new_person")}
                label={t("add_name")}
                placeholder={t("enter_name")}
                autoComplete="name"
                submitButtonColor="primary"
                submitButtonTitle={t("add")}
                onSubmit={handleAddPersonWithName}
            />
        </>
    );
};

const DialogTitle_ = styled(Box)({
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "10px 8px 6px 24px",
});

const DialogContent_ = styled(DialogContent)`
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
`;

interface PersonPickerCardProps {
    person: Person;
    onPersonClick: (personID: string) => void;
}

const PersonPickerCard: React.FC<PersonPickerCardProps> = ({
    person,
    onPersonClick,
}) => (
    <ItemCard
        TileComponent={LargeTileButton}
        coverFile={person.displayFaceFile}
        coverFaceID={person.displayFaceID}
        onClick={() => onPersonClick(person.id)}
    >
        <LargeTileTextOverlay>
            <Typography>{person.name ?? ""}</Typography>
        </LargeTileTextOverlay>
    </ItemCard>
);
