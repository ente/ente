import {
    CollectionDialogSearchField,
    CollectionDialogTileButton,
    CollectionDialogTileCover,
} from "@/components/CollectionDialog/Primitives";
import {
    collectionDialogFullScreenQuery,
    collectionDialogHeaderRowSx,
    collectionDialogHeaderSx,
    collectionDialogIconButtonSx,
    collectionDialogPaperSx,
    collectionDialogTitleSx,
} from "@/components/CollectionDialog/styles";
import { useWrapAsyncOperation } from "@/components/utils/use-wrap-async";
import {
    Add01Icon,
    ArrowLeft02Icon,
    Cancel01Icon,
    Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import AddIcon from "@mui/icons-material/Add";
import ClearIcon from "@mui/icons-material/Clear";
import EditIcon from "@mui/icons-material/Edit";
import HideImageOutlinedIcon from "@mui/icons-material/HideImageOutlined";
import ListAltOutlinedIcon from "@mui/icons-material/ListAltOutlined";
import PushPinIcon from "@mui/icons-material/PushPin";
import PushPinOutlinedIcon from "@mui/icons-material/PushPinOutlined";
import RestoreIcon from "@mui/icons-material/Restore";
import VisibilityOutlinedIcon from "@mui/icons-material/VisibilityOutlined";
import {
    Box,
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    List,
    ListItem,
    Stack,
    ToggleButton,
    ToggleButtonGroup,
    Tooltip,
    Typography,
    useMediaQuery,
    useTheme,
    type Theme,
} from "@mui/material";
import { CenteredFill, SpacedRow } from "ente-base/components/containers";
import { ActivityErrorIndicator } from "ente-base/components/ErrorIndicator";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import {
    v2CancelButtonSx,
    v2SubmitButtonSx,
} from "ente-base/components/SingleInput.styles";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { isSxArray } from "ente-base/components/utils/sx";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import {
    GalleryItemsCoverTile,
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import { SuggestionFaceList } from "ente-new/photos/components/PeopleList";
import { ItemCard } from "ente-new/photos/components/Tiles";
import {
    addCGroup,
    addClusterToCGroup,
    applyPersonSuggestionUpdates,
    deleteCGroup,
    ignoreCluster,
    pinCGroup,
    renameCGroup,
    suggestionsAndChoicesForPerson,
    unpinCGroup,
} from "ente-new/photos/services/ml";
import type { FaceCluster } from "ente-new/photos/services/ml/cluster";
import type {
    CGroupPerson,
    ClusterPerson,
    Person,
    PersonSuggestionsAndChoices,
    PersonSuggestionUpdates,
    PreviewableCluster,
} from "ente-new/photos/services/ml/people";
import { t } from "i18next";
import React, { useEffect, useReducer, useState } from "react";
import type { GalleryBarImplProps } from "./BarImpl";

type PeopleHeaderProps = Pick<
    GalleryBarImplProps,
    "people" | "onSelectPerson"
> & { person: Person; onBack: () => void };

export const PeopleHeader: React.FC<PeopleHeaderProps> = ({
    people,
    onSelectPerson,
    person,
    onBack,
}) => {
    return (
        <GalleryItemsHeaderAdapter
            sx={{ display: "flex", alignItems: "center", gap: 1 }}
        >
            <Tooltip title={t("go_back")}>
                <IconButton
                    aria-label={t("go_back")}
                    onClick={onBack}
                    sx={{
                        display: { xs: "none", sm: "inline-flex" },
                        width: 32,
                        height: 32,
                        flexShrink: 0,
                    }}
                >
                    <HugeiconsIcon icon={ArrowLeft02Icon} size={20} />
                </IconButton>
            </Tooltip>
            <SpacedRow sx={{ gap: 2, flex: 1, minWidth: 0 }}>
                {person.type == "cgroup" ? (
                    person.isHidden ? (
                        <IgnoredPersonHeader person={person} />
                    ) : (
                        <CGroupPersonHeader person={person} />
                    )
                ) : (
                    <ClusterPersonHeader
                        person={person}
                        {...{ people, onSelectPerson }}
                    />
                )}
            </SpacedRow>
        </GalleryItemsHeaderAdapter>
    );
};

const PersonHeaderSummary = ({
    person,
    ...summaryProps
}: { person: Person } & Pick<
    React.ComponentProps<typeof GalleryItemsSummary>,
    "name" | "nameProps" | "onNameClick"
>) => {
    const showCover = useMediaQuery(useTheme().breakpoints.up("sm"));
    return (
        <Stack
            direction="row"
            sx={{ gap: 2, alignItems: "center", minWidth: 0 }}
        >
            {showCover && (
                <Box
                    aria-hidden
                    sx={{ flexShrink: 0, alignSelf: "flex-start" }}
                >
                    <ItemCard
                        key={`${person.id}-${person.displayFaceID}`}
                        TileComponent={GalleryItemsCoverTile}
                        coverFile={person.displayFaceFile}
                        coverFaceID={person.displayFaceID}
                    />
                </Box>
            )}
            <GalleryItemsSummary
                {...summaryProps}
                fileCount={person.fileIDs.length}
                nameProps={{
                    ...summaryProps.nameProps,
                    sx: { overflowWrap: "anywhere" },
                }}
            />
        </Stack>
    );
};

interface CGroupPersonHeaderProps {
    person: CGroupPerson;
}

const CGroupPersonHeader: React.FC<CGroupPersonHeaderProps> = ({ person }) => {
    const cgroup = person.cgroup;

    const { showMiniDialog } = useBaseContext();

    const { show: showNameInput, props: nameInputVisibilityProps } =
        useModalVisibility();
    const { show: showSuggestions, props: suggestionsVisibilityProps } =
        useModalVisibility();

    const handleRename = (name: string) => renameCGroup(cgroup, name);
    const handlePin = useWrapAsyncOperation(() => pinCGroup(cgroup));
    const handleUnpin = useWrapAsyncOperation(() => unpinCGroup(cgroup));

    const handleReset = () =>
        showMiniDialog({
            title: t("reset_person_confirm"),
            message: t("reset_person_confirm_message"),
            continue: {
                text: t("reset"),
                color: "primary",
                action: () => deleteCGroup(cgroup),
            },
        });

    // This view only receives unignored, named people.
    const name =
        person.name?.trim() || cgroup.data.name?.trim() || t("unnamed_person");

    return (
        <>
            <PersonHeaderSummary person={person} name={name} />
            <OverflowMenu ariaID="person-options">
                <OverflowMenuOption
                    startIcon={<ListAltOutlinedIcon />}
                    onClick={showSuggestions}
                >
                    {t("review_suggestions")}
                </OverflowMenuOption>
                <OverflowMenuOption
                    startIcon={<EditIcon />}
                    onClick={showNameInput}
                >
                    {t("rename")}
                </OverflowMenuOption>
                {person.isPinned ? (
                    <OverflowMenuOption
                        startIcon={<PushPinOutlinedIcon />}
                        onClick={handleUnpin}
                    >
                        {t("unpin_person")}
                    </OverflowMenuOption>
                ) : (
                    <OverflowMenuOption
                        startIcon={<PushPinIcon />}
                        onClick={handlePin}
                    >
                        {t("pin_person")}
                    </OverflowMenuOption>
                )}
                <OverflowMenuOption
                    startIcon={<ClearIcon />}
                    onClick={handleReset}
                >
                    {t("reset")}
                </OverflowMenuOption>
            </OverflowMenu>

            <SingleInputDialog
                {...nameInputVisibilityProps}
                title={t("rename_person")}
                label={t("name")}
                placeholder={t("enter_name")}
                autoComplete="name"
                initialValue={name}
                submitButtonTitle={t("rename")}
                onSubmit={handleRename}
            />
            <SuggestionsDialog
                {...suggestionsVisibilityProps}
                {...{ person }}
            />
        </>
    );
};

interface IgnoredPersonHeaderProps {
    person: CGroupPerson;
}

const IgnoredPersonHeader: React.FC<IgnoredPersonHeaderProps> = ({
    person,
}) => {
    const cgroup = person.cgroup;

    const handleUndoIgnore = useWrapAsyncOperation(() => deleteCGroup(cgroup));

    return (
        <>
            <PersonHeaderSummary
                person={person}
                name={person.name?.trim() || t("ignored")}
                nameProps={{ color: "text.muted" }}
            />
            <OverflowMenu ariaID="person-options">
                <OverflowMenuOption
                    startIcon={<VisibilityOutlinedIcon />}
                    onClick={handleUndoIgnore}
                >
                    {t("show_person")}
                </OverflowMenuOption>
            </OverflowMenu>
        </>
    );
};

type ClusterPersonHeaderProps = Pick<
    PeopleHeaderProps,
    "people" | "onSelectPerson"
> & { person: ClusterPerson };

const ClusterPersonHeader: React.FC<ClusterPersonHeaderProps> = ({
    people,
    onSelectPerson,
    person,
}) => {
    const cluster = person.cluster;

    const { showMiniDialog } = useBaseContext();

    const { show: showAddPerson, props: addPersonVisibilityProps } =
        useModalVisibility();

    const confirmIgnore = () =>
        showMiniDialog({
            title: t("ignore_person_confirm"),
            message: t("ignore_person_confirm_message"),
            continue: {
                text: t("ignore"),
                color: "primary",
                action: () => ignoreCluster(cluster),
            },
        });

    return (
        <>
            <PersonHeaderSummary
                person={person}
                name={person.name?.trim() || t("unnamed_person")}
                nameProps={{ color: "text.muted" }}
                onNameClick={showAddPerson}
            />
            <Stack direction="row" sx={{ alignItems: "center", gap: 2 }}>
                <Tooltip title={t("add_a_name")}>
                    <IconButton onClick={showAddPerson}>
                        <AddIcon />
                    </IconButton>
                </Tooltip>

                <OverflowMenu ariaID="person-options">
                    <OverflowMenuOption
                        startIcon={<AddIcon />}
                        onClick={showAddPerson}
                    >
                        {t("add_a_name")}
                    </OverflowMenuOption>
                    <OverflowMenuOption
                        startIcon={<HideImageOutlinedIcon />}
                        onClick={confirmIgnore}
                    >
                        {t("ignore")}
                    </OverflowMenuOption>
                </OverflowMenu>
            </Stack>

            <AddPersonDialog
                {...addPersonVisibilityProps}
                {...{ people, onSelectPerson, cluster }}
            />
        </>
    );
};

type AddPersonDialogProps = ModalVisibilityProps &
    Pick<PeopleHeaderProps, "people" | "onSelectPerson"> & {
        cluster: FaceCluster;
    };

const AddPersonDialog: React.FC<AddPersonDialogProps> = ({
    open,
    onClose,
    people,
    onSelectPerson,
    cluster,
}) => {
    const isFullScreen = useMediaQuery(collectionDialogFullScreenQuery);

    const [openNameInput, setOpenNameInput] = useState(false);
    const [searchTerm, setSearchTerm] = useState("");

    const cgroupPeople: CGroupPerson[] = people.filter(
        (p) => p.type != "cluster",
    );
    const query = searchTerm.trim().toLowerCase();
    const filteredPeople = cgroupPeople.filter(
        (person) => !query || person.name?.toLowerCase().includes(query),
    );

    const handleClose = () => {
        setSearchTerm("");
        onClose();
    };

    const handleAddPerson = () => setOpenNameInput(true);

    const handleAddPersonBySelect = useWrapAsyncOperation(
        async (personID: string) => {
            handleClose();
            const person = cgroupPeople.find((p) => p.id == personID)!;
            await addClusterToCGroup(person.cgroup, cluster);
            onSelectPerson(personID);
        },
    );

    const handleAddPersonWithName = async (name: string) => {
        const personID = await addCGroup(name, cluster);
        onSelectPerson(personID);
    };

    // This render-time update intentionally redirects an empty list to naming.
    // React discards this render and starts another with the new state.
    if (open && !openNameInput && !cgroupPeople.length) {
        handleClose();
        setOpenNameInput(true);
        return <></>;
    }

    return (
        <>
            <Dialog
                open={open}
                onClose={handleClose}
                fullScreen={isFullScreen}
                maxWidth={false}
                aria-labelledby="add-person-title"
                slotProps={{
                    paper: {
                        sx: [
                            ...(isSxArray(collectionDialogPaperSx)
                                ? collectionDialogPaperSx
                                : [collectionDialogPaperSx]),
                            {
                                width: isFullScreen
                                    ? "100%"
                                    : "min(600px, calc(100svw - 64px))",
                                maxWidth: isFullScreen ? "100%" : 600,
                                maxHeight: isFullScreen
                                    ? "100%"
                                    : "min(600px, calc(100svh - 64px))",
                                boxSizing: "border-box",
                            },
                        ],
                    },
                }}
            >
                <Stack
                    sx={{
                        ...collectionDialogHeaderSx,
                        gap: "24px",
                        pb: 0,
                        flexShrink: 0,
                    }}
                >
                    <Stack
                        direction="row"
                        sx={{
                            ...collectionDialogHeaderRowSx,
                            alignItems: "center",
                        }}
                    >
                        <Typography
                            id="add-person-title"
                            component="h2"
                            sx={{
                                ...collectionDialogTitleSx,
                                fontFamily:
                                    '"Outfit Variable", Outfit, sans-serif',
                            }}
                        >
                            {t("add_name")}
                        </Typography>
                        <IconButton
                            aria-label={t("close")}
                            onClick={handleClose}
                            sx={collectionDialogIconButtonSx}
                        >
                            <HugeiconsIcon icon={Cancel01Icon} size={18} />
                        </IconButton>
                    </Stack>
                    <CollectionDialogSearchField
                        placeholder={`${t("people_search_hint")}...`}
                        value={searchTerm}
                        onChange={setSearchTerm}
                    />
                </Stack>
                <Box
                    sx={{
                        display: "grid",
                        gridTemplateColumns: "repeat(4, minmax(0, 1fr))",
                        "@media (width < 600px)": {
                            gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
                        },
                        "@media (width < 360px)": {
                            gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
                        },
                        columnGap: "22px",
                        rowGap: "24px",
                        alignContent: "start",
                        overflowY: "auto",
                        p: "24px 20px 20px",
                        minHeight: 0,
                    }}
                >
                    <CollectionDialogTileButton onClick={handleAddPerson}>
                        <CollectionDialogTileCover>
                            <CenteredFill
                                sx={{
                                    position: "absolute",
                                    inset: 0,
                                    color: "text.muted",
                                }}
                            >
                                <HugeiconsIcon
                                    icon={Add01Icon}
                                    size={24}
                                    strokeWidth={1.5}
                                />
                            </CenteredFill>
                        </CollectionDialogTileCover>
                        <Typography
                            component="span"
                            noWrap
                            sx={{
                                fontSize: 14,
                                lineHeight: "20px",
                                fontWeight: 500,
                                maxWidth: "100%",
                            }}
                        >
                            {t("new_person")}
                        </Typography>
                    </CollectionDialogTileButton>
                    {filteredPeople.map((person) => (
                        <PersonButton
                            key={person.id}
                            person={person}
                            onPersonClick={handleAddPersonBySelect}
                        />
                    ))}
                </Box>
            </Dialog>

            <SingleInputDialog
                open={openNameInput}
                onClose={() => setOpenNameInput(false)}
                title={t("new_person")}
                label={t("add_name")}
                placeholder={t("enter_name")}
                autoComplete="name"
                submitButtonTitle={t("add")}
                onSubmit={handleAddPersonWithName}
            />
        </>
    );
};

interface PersonButtonProps {
    person: Person;
    onPersonClick: (personID: string) => void;
}

const PersonButton: React.FC<PersonButtonProps> = ({
    person,
    onPersonClick,
}) => (
    <CollectionDialogTileButton
        title={person.name}
        onClick={() => onPersonClick(person.id)}
    >
        <ItemCard
            TileComponent={CollectionDialogTileCover}
            coverFile={person.displayFaceFile}
            coverFaceID={person.displayFaceID}
        />
        <Stack component="span" sx={{ width: "100%", minWidth: 0, gap: "4px" }}>
            <Typography
                component="span"
                noWrap
                sx={{ fontSize: 14, lineHeight: "20px", fontWeight: 500 }}
            >
                {person.name ?? ""}
            </Typography>
            <Typography
                component="span"
                noWrap
                sx={{
                    fontSize: 12,
                    lineHeight: "16px",
                    fontWeight: 500,
                    color: "text.muted",
                }}
            >
                {t("album_items_count", { count: person.fileIDs.length })}
            </Typography>
        </Stack>
    </CollectionDialogTileButton>
);

type SuggestionsDialogProps = ModalVisibilityProps & { person: CGroupPerson };

interface SuggestionsDialogState {
    activity: "fetching" | "saving" | undefined;
    // Track the ID because the person object has no stable identity.
    personID: string | undefined;
    fetchFailed: boolean;
    showChoices: boolean;
    choices: SCItem[];
    suggestions: SCItem[];
    updates: PersonSuggestionUpdates;
}

type SCItem = PreviewableCluster & { fixed?: boolean; assigned?: boolean };

type SuggestionsDialogAction =
    | { type: "fetch"; personID: string }
    | { type: "fetchFailed"; personID: string }
    | {
          type: "fetched";
          personID: string;
          suggestionsAndChoices: PersonSuggestionsAndChoices;
      }
    | { type: "updateItem"; item: SCItem; value: boolean | undefined }
    | { type: "save" }
    | { type: "toggleHistory" }
    | { type: "close" };

const initialSuggestionsDialogState: SuggestionsDialogState = {
    activity: undefined,
    personID: undefined,
    fetchFailed: false,
    showChoices: false,
    choices: [],
    suggestions: [],
    updates: new Map(),
};

const suggestionsDialogReducer: React.Reducer<
    SuggestionsDialogState,
    SuggestionsDialogAction
> = (state, action) => {
    switch (action.type) {
        case "fetch":
            return {
                ...initialSuggestionsDialogState,
                choices: [],
                suggestions: [],
                updates: new Map(),
                activity: "fetching",
                personID: action.personID,
            };
        case "fetchFailed":
            if (action.personID != state.personID) return state;
            return { ...state, activity: undefined, fetchFailed: true };
        case "fetched":
            if (action.personID != state.personID) return state;
            return {
                ...state,
                activity: undefined,
                choices: action.suggestionsAndChoices.choices,
                suggestions: action.suggestionsAndChoices.suggestions,
            };
        case "updateItem": {
            const updates = new Map(state.updates);
            const { item, value } = action;
            if (item.assigned === undefined && value === undefined) {
                updates.delete(item.id);
            } else if (item.assigned !== undefined && value === item.assigned) {
                updates.delete(item.id);
            } else {
                const update = (() => {
                    switch (value) {
                        case true:
                            return "assign";
                        case false:
                            return item.assigned === undefined
                                ? "rejectSuggestion"
                                : "rejectSavedChoice";
                        case undefined:
                            return "reset";
                    }
                })();
                updates.set(item.id, update);
            }
            return { ...state, updates };
        }
        case "toggleHistory":
            return { ...state, showChoices: !state.showChoices };
        case "save":
            return { ...state, activity: "saving" };
        case "close":
            // Reset the ID so reopening the same person recomputes suggestions.
            // Keep the lists visible during the closing animation.
            return { ...state, personID: undefined };
    }
};

const SuggestionsDialog: React.FC<SuggestionsDialogProps> = ({
    open,
    onClose,
    person,
}) => {
    const { showMiniDialog, onGenericError } = useBaseContext();

    const [state, dispatch] = useReducer(
        suggestionsDialogReducer,
        initialSuggestionsDialogState,
    );

    const isSmallWidth = useIsSmallWidth();

    const hasUnsavedChanges = state.updates.size > 0;

    const resetPersonAndClose = () => {
        dispatch({ type: "close" });
        onClose();
    };

    useEffect(() => {
        if (!open) return;

        const personID = person.id;
        if (person.id == state.personID) return;

        dispatch({ type: "fetch", personID });

        const go = async () => {
            try {
                const suggestionsAndChoices =
                    await suggestionsAndChoicesForPerson(person);
                dispatch({ type: "fetched", personID, suggestionsAndChoices });
            } catch (e) {
                log.error("Failed to fetch suggestions and choices", e);
                dispatch({ type: "fetchFailed", personID });
            }
        };

        void go();
    }, [open, person, state.personID]);

    const handleClose = () => {
        if (hasUnsavedChanges) {
            showMiniDialog({
                message: t("discard_changes_confirm_message"),
                kind: "warning",
                continue: {
                    text: t("discard_changes"),
                    color: "critical",
                    action: resetPersonAndClose,
                },
            });

            return;
        }

        resetPersonAndClose();
    };

    const handleUpdateItem = (item: SCItem, value: boolean | undefined) =>
        dispatch({ type: "updateItem", item, value });

    const handleSave = async () => {
        dispatch({ type: "save" });
        try {
            await applyPersonSuggestionUpdates(person.cgroup, state.updates);
            resetPersonAndClose();
        } catch (e) {
            log.error("Failed to save suggestion review", e);
            onGenericError(e);
        }
    };

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            maxWidth={false}
            fullScreen={isSmallWidth}
            aria-labelledby="person-suggestions-title"
            slotProps={{
                paper: {
                    sx: [
                        ...(isSxArray(collectionDialogPaperSx)
                            ? collectionDialogPaperSx
                            : [collectionDialogPaperSx]),
                        {
                            "&.MuiPaper-root": {
                                width: "min(520px, calc(100svw - 64px))",
                                maxWidth: 520,
                                height: "auto",
                                boxSizing: "border-box",
                            },
                            "&.MuiDialog-paperFullScreen": {
                                width: "100%",
                                maxWidth: "100%",
                                height: "100%",
                                border: "none",
                                borderRadius: 0,
                            },
                        },
                    ],
                },
            }}
        >
            <SpacedRow
                sx={{
                    p: "20px 20px 10px",
                    alignItems: "flex-start",
                    gap: "12px",
                    flexShrink: 0,
                }}
            >
                <Stack sx={{ gap: "2px", pt: "3px", minWidth: 0 }}>
                    <DialogTitle
                        id="person-suggestions-title"
                        sx={{
                            ...collectionDialogTitleSx,
                            fontFamily: '"Outfit Variable", Outfit, sans-serif',
                            whiteSpace: "normal",
                            overflowWrap: "anywhere",
                            "&&&": { p: 0 },
                        }}
                    >
                        {state.showChoices
                            ? t("saved_choices")
                            : t("review_suggestions")}
                    </DialogTitle>
                    <Typography
                        sx={{
                            fontSize: 12,
                            lineHeight: "15px",
                            color: "text.muted",
                            overflowWrap: "anywhere",
                        }}
                    >
                        {person.name ?? " "}
                    </Typography>
                </Stack>
                <Stack direction="row" sx={{ gap: "8px", flexShrink: 0 }}>
                    {state.choices.length > 1 && (
                        <IconButton
                            disableTouchRipple
                            onClick={() => dispatch({ type: "toggleHistory" })}
                            aria-label={
                                !state.showChoices
                                    ? t("saved_choices")
                                    : t("review_suggestions")
                            }
                            sx={collectionDialogIconButtonSx}
                        >
                            <RestoreIcon sx={{ fontSize: 18 }} />
                        </IconButton>
                    )}
                    <IconButton
                        aria-label={t("close")}
                        onClick={handleClose}
                        sx={collectionDialogIconButtonSx}
                    >
                        <HugeiconsIcon icon={Cancel01Icon} size={18} />
                    </IconButton>
                </Stack>
            </SpacedRow>
            <DialogContent
                key={`${state.showChoices}`}
                sx={{
                    display: "flex",
                    flex: isSmallWidth ? "1 1 auto" : "0 1 auto",
                    minHeight: 0,
                    "&&&": { p: "0 20px" },
                }}
            >
                {state.activity == "fetching" ? (
                    <CenteredFill sx={{ minHeight: 200 }}>
                        <ActivityIndicator>
                            {t("people_suggestions_finding")}
                        </ActivityIndicator>
                    </CenteredFill>
                ) : state.fetchFailed ? (
                    <CenteredFill sx={{ minHeight: 200 }}>
                        <ActivityErrorIndicator />
                    </CenteredFill>
                ) : state.showChoices ? (
                    <SuggestionOrChoiceList
                        items={state.choices}
                        updates={state.updates}
                        onUpdateItem={handleUpdateItem}
                    />
                ) : state.suggestions.length == 0 ? (
                    <CenteredFill sx={{ minHeight: 200 }}>
                        <Typography
                            sx={{ color: "text.muted", textAlign: "center" }}
                        >
                            {t("people_suggestions_empty")}
                        </Typography>
                    </CenteredFill>
                ) : (
                    <SuggestionOrChoiceList
                        items={state.suggestions}
                        updates={state.updates}
                        onUpdateItem={handleUpdateItem}
                    />
                )}
            </DialogContent>
            <DialogActions
                disableSpacing
                sx={{ "&&": { p: "40px 20px 20px", gap: "12px" } }}
            >
                <FocusVisibleButton
                    fullWidth
                    color="secondary"
                    onClick={handleClose}
                    sx={[v2CancelButtonSx, suggestionsDialogButtonSx]}
                >
                    {t("close")}
                </FocusVisibleButton>
                <LoadingButton
                    fullWidth
                    disabled={!hasUnsavedChanges}
                    loading={state.activity == "saving"}
                    color="accent"
                    onClick={handleSave}
                    sx={[
                        v2SubmitButtonSx,
                        suggestionsDialogButtonSx,
                        state.activity != "saving" &&
                            suggestionsDialogDisabledButtonSx,
                    ]}
                >
                    {t("save")}
                </LoadingButton>
            </DialogActions>
        </Dialog>
    );
};

const suggestionsDialogButtonSx = {
    height: 52,
    minWidth: 0,
    p: "14px 24px",
    borderRadius: "20px",
    fontSize: 14,
    fontWeight: 500,
    lineHeight: "20px",
};

const suggestionsDialogDisabledButtonSx = (theme: Theme) => ({
    "&.Mui-disabled": {
        opacity: 1,
        backgroundColor: "#eaeaea",
        color: "#d6d6d6",
        ...theme.applyStyles("dark", {
            backgroundColor: "rgba(255 255 255 / 0.12)",
            color: "rgba(255 255 255 / 0.3)",
        }),
    },
});

interface SuggestionOrChoiceListProps {
    items: SCItem[];
    updates: PersonSuggestionUpdates;
    onUpdateItem: (item: SCItem, value: boolean | undefined) => void;
}

const SuggestionOrChoiceList: React.FC<SuggestionOrChoiceListProps> = ({
    items,
    updates,
    onUpdateItem,
}) => (
    <List disablePadding sx={{ width: "100%", minWidth: 0 }}>
        {items.map((item) => (
            <ListItem
                key={item.id}
                sx={(theme) => ({
                    px: 0,
                    py: "14px",
                    gap: "16px",
                    justifyContent: "space-between",
                    "&:not(:last-child)": { borderBottom: "1px solid #ebebeb" },
                    ...theme.applyStyles("dark", {
                        "&:not(:last-child)": { borderColor: "stroke.faint" },
                    }),
                })}
            >
                <Stack sx={{ gap: "8px", minWidth: 0 }}>
                    <Typography
                        sx={{
                            fontSize: 11.5,
                            lineHeight: "14px",
                            fontWeight: 500,
                            color: "text.muted",
                        }}
                    >
                        {/* Face count stands in for photo count here. */}
                        {t("photos_count", { count: item.faces.length })}
                    </Typography>
                    <SuggestionFaceList faces={item.previewFaces} />
                </Stack>
                {!item.fixed && (
                    <ToggleButtonGroup
                        value={itemValueFromUpdate(item, updates)}
                        exclusive
                        onChange={(_, v) => onUpdateItem(item, toItemValue(v))}
                        sx={{ gap: "8px", flexShrink: 0 }}
                    >
                        <ToggleButton
                            value="no"
                            aria-label={t("no")}
                            sx={suggestionToggleButtonSx}
                        >
                            <HugeiconsIcon icon={Cancel01Icon} size={22} />
                        </ToggleButton>
                        <ToggleButton
                            value="yes"
                            aria-label={t("yes")}
                            sx={suggestionToggleButtonSx}
                        >
                            <HugeiconsIcon icon={Tick02Icon} size={22} />
                        </ToggleButton>
                    </ToggleButtonGroup>
                )}
            </ListItem>
        ))}
    </List>
);

const suggestionToggleButtonSx = (theme: Theme) => ({
    ...collectionDialogIconButtonSx(theme),
    "&&": { border: 0, borderRadius: "50%", m: 0 },
    "&.Mui-selected, &.Mui-selected:hover": {
        backgroundColor: "primary.main",
        color: "primary.contrastText",
    },
    "&.Mui-focusVisible": {
        outline: "2px solid",
        outlineColor: "stroke.base",
        outlineOffset: 2,
    },
});

const itemValueFromUpdate = (
    item: SCItem,
    updates: PersonSuggestionUpdates,
) => {
    const resolveUpdate = () => {
        switch (updates.get(item.id)) {
            case "assign":
                return true;
            case "rejectSavedChoice":
                return false;
            case "rejectSuggestion":
                return false;
            default:
                return undefined;
        }
    };
    const resolved = updates.has(item.id) ? resolveUpdate() : item.assigned;
    return resolved ? "yes" : resolved === false ? "no" : undefined;
};

const toItemValue = (v: unknown) =>
    v == "yes" ? true : v == "no" ? false : undefined;
