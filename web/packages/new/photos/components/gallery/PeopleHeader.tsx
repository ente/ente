import AddIcon from "@mui/icons-material/Add";
import CheckIcon from "@mui/icons-material/Check";
import ClearIcon from "@mui/icons-material/Clear";
import EditIcon from "@mui/icons-material/Edit";
import HideImageOutlinedIcon from "@mui/icons-material/HideImageOutlined";
import ListAltOutlinedIcon from "@mui/icons-material/ListAltOutlined";
import PushPinIcon from "@mui/icons-material/PushPin";
import PushPinOutlinedIcon from "@mui/icons-material/PushPinOutlined";
import RestoreIcon from "@mui/icons-material/Restore";
import VisibilityOutlinedIcon from "@mui/icons-material/VisibilityOutlined";
import {
    Dialog,
    DialogActions,
    DialogContent,
    DialogTitle,
    IconButton,
    List,
    ListItem,
    Stack,
    styled,
    ToggleButton,
    ToggleButtonGroup,
    Tooltip,
    Typography,
    useMediaQuery,
} from "@mui/material";
import { CenteredFill, SpacedRow } from "ente-base/components/containers";
import { ActivityErrorIndicator } from "ente-base/components/ErrorIndicator";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { DialogCloseIconButton } from "ente-base/components/mui/DialogCloseIconButton";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { LoadingButton } from "ente-base/components/mui/LoadingButton";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import {
    useModalVisibility,
    type ModalVisibilityProps,
} from "ente-base/components/utils/modal";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
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
import type { FaceCluster } from "../../services/ml/cluster";
import { SuggestionFaceList } from "../PeopleList";
import {
    ItemCard,
    LargeTileButton,
    LargeTileCreateNewButton,
    LargeTileTextOverlay,
} from "../Tiles";
import { useWrapAsyncOperation } from "../utils/use-wrap-async";
import type { GalleryBarImplProps } from "./BarImpl";
import { GalleryItemsHeaderAdapter, GalleryItemsSummary } from "./ListHeader";

type PeopleHeaderProps = Pick<
    GalleryBarImplProps,
    "people" | "onSelectPerson"
> & { person: Person };

export const PeopleHeader: React.FC<PeopleHeaderProps> = ({
    people,
    onSelectPerson,
    person,
}) => {
    return (
        <GalleryItemsHeaderAdapter>
            <SpacedRow>
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

    // While technically it is possible for the cgroup not to have a name, logic
    // wise we shouldn't be ending up here without a name (this state is
    // expected to be reached only for unignored named persons).
    const name = cgroup.data.name ?? "";

    return (
        <>
            <GalleryItemsSummary
                name={name}
                fileCount={person.fileIDs.length}
            />
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
                submitButtonColor="primary"
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
            <GalleryItemsSummary
                name={t("ignored")}
                nameProps={{ color: "text.muted" }}
                fileCount={person.fileIDs.length}
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
            <GalleryItemsSummary
                name={t("unnamed_person")}
                nameProps={{ color: "text.muted" }}
                fileCount={person.fileIDs.length}
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
        /**
         * The cluster to add to the selected person (existing or new).
         */
        cluster: FaceCluster;
    };

/**
 * A dialog allowing the user to select one of the existing named persons they
 * have, or create a new one, and then associate the provided cluster to it,
 * creating or updating a remote "person".
 */
const AddPersonDialog: React.FC<AddPersonDialogProps> = ({
    open,
    onClose,
    people,
    onSelectPerson,
    cluster,
}) => {
    const isFullScreen = useMediaQuery("(max-width: 490px)");

    const [openNameInput, setOpenNameInput] = useState(false);

    const cgroupPeople: CGroupPerson[] = people.filter(
        (p) => p.type != "cluster",
    );

    const handleAddPerson = () => setOpenNameInput(true);

    const handleAddPersonBySelect = useWrapAsyncOperation(
        async (personID: string) => {
            onClose();
            const person = cgroupPeople.find((p) => p.id == personID)!;
            await addClusterToCGroup(person.cgroup, cluster);
            onSelectPerson(personID);
        },
    );

    const handleAddPersonWithName = async (name: string) => {
        const personID = await addCGroup(name, cluster);
        onSelectPerson(personID);
    };

    // [Note: Calling setState during rendering]
    //
    // Calling setState during rendering should be avoided when there are
    // cleaner alternatives, but it is not completely verboten, and it has
    // documented semantics:
    //
    // > React will discard the currently rendering component's output and
    // > immediately attempt to render it again with the new state.
    // >
    // > https://react.dev/reference/react/useState

    // If we're opened without any existing people that can be selected, jump
    // directly to the add person dialog.
    if (open && !openNameInput && !cgroupPeople.length) {
        onClose();
        setOpenNameInput(true);
        return <></>;
    }

    return (
        <>
            <Dialog
                {...{ open, onClose }}
                fullWidth
                fullScreen={isFullScreen}
                slotProps={{ paper: { sx: { maxWidth: "490px" } } }}
            >
                <SpacedRow sx={{ padding: "10px 8px 6px 0" }}>
                    <DialogTitle variant="h3">{t("add_name")}</DialogTitle>
                    <DialogCloseIconButton {...{ onClose }} />
                </SpacedRow>
                <DialogContent_>
                    <LargeTileCreateNewButton onClick={handleAddPerson}>
                        {t("new_person")}
                    </LargeTileCreateNewButton>
                    {cgroupPeople.map((person) => (
                        <PersonButton
                            key={person.id}
                            person={person}
                            onPersonClick={handleAddPersonBySelect}
                        />
                    ))}
                </DialogContent_>
            </Dialog>

            <SingleInputDialog
                open={openNameInput}
                onClose={() => setOpenNameInput(false)}
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

const DialogContent_ = styled(DialogContent)`
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
`;

interface PersonButtonProps {
    person: Person;
    onPersonClick: (personID: string) => void;
}

const PersonButton: React.FC<PersonButtonProps> = ({
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

type SuggestionsDialogProps = ModalVisibilityProps & { person: CGroupPerson };

interface SuggestionsDialogState {
    activity: "fetching" | "saving" | undefined;
    /**
     * This is a workaround for the lack of stable identity of the person prop
     * passed to the dialog (on which we trigger the suggestion computation.)
     */
    personID: string | undefined;
    /**
     * True if "fetching" failed.
     */
    fetchFailed: boolean;
    /**
     * True if we should show the previously saved choice view instead of the
     * new suggestions.
     */
    showChoices: boolean;
    /** Fetched choices. */
    choices: SCItem[];
    /** Fetched suggestions. */
    suggestions: SCItem[];
    /**
     * An entry corresponding to each
     * - saved choice for which the user has changed their mind.
     * - suggestion that the user has either explicitly assigned or rejected.
     */
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
                // If this was a suggestion, prune previous updates since the
                // use has toggled the item back to its original unset state.
                updates.delete(item.id);
            } else if (item.assigned !== undefined && value === item.assigned) {
                // If this is a choice, prune updates which match the choice's
                // original assigned state.
                updates.delete(item.id);
            } else {
                const update = (() => {
                    switch (value) {
                        case true:
                            // true corresponds to update "assign".
                            return "assign";
                        case false:
                            // false maps to different updates for suggestions
                            // vs choices.
                            return item.assigned === undefined
                                ? "rejectSuggestion"
                                : "rejectSavedChoice";
                        case undefined:
                            // undefined means reset.
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
            // Reset the person ID when closing the dialog so that the
            // suggestions are recomputed the next time the dialog is reopened
            // (even for the same person).
            //
            // We cannot reset the suggestions themselves since they would cause
            // the dialog to lose its visual state during the closing animation.
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

        // Avoid recomputing when the person object changes without its identity
        // changing. This is a workaround, a better fix would be to fix upstream
        // to guarantee a stable identity of the person object itself.
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
            maxWidth="sm"
            fullWidth
            fullScreen={isSmallWidth}
            slotProps={{ paper: { sx: { minHeight: "80svh" } } }}
        >
            <SpacedRow
                sx={[
                    { padding: "20px 16px 16px 16px" },
                    state.showChoices
                        ? { backgroundColor: "fill.faint" }
                        : { backgroundColor: "transparent" },
                ]}
            >
                <Stack sx={{ gap: "8px" }}>
                    <DialogTitle sx={{ "&&&": { p: 0 } }}>
                        {state.showChoices
                            ? t("saved_choices")
                            : t("review_suggestions")}
                    </DialogTitle>
                    <Typography sx={{ color: "text.muted" }}>
                        {person.name ?? " "}
                    </Typography>
                </Stack>
                {state.choices.length > 1 && (
                    <IconButton
                        disableTouchRipple
                        onClick={() => dispatch({ type: "toggleHistory" })}
                        aria-label={
                            !state.showChoices
                                ? t("saved_choices")
                                : t("review_suggestions")
                        }
                        sx={[
                            state.showChoices
                                ? { backgroundColor: "fill.muted" }
                                : { backgroundColor: "transparent" },
                        ]}
                    >
                        <RestoreIcon />
                    </IconButton>
                )}
            </SpacedRow>
            <DialogContent
                /* Reset scroll position on switching view */
                key={`${state.showChoices}`}
                sx={{ display: "flex", "&&&": { pt: 0 } }}
            >
                {state.activity == "fetching" ? (
                    <CenteredFill>
                        <ActivityIndicator>
                            {t("people_suggestions_finding")}
                        </ActivityIndicator>
                    </CenteredFill>
                ) : state.fetchFailed ? (
                    <CenteredFill>
                        <ActivityErrorIndicator />
                    </CenteredFill>
                ) : state.showChoices ? (
                    <SuggestionOrChoiceList
                        items={state.choices}
                        updates={state.updates}
                        onUpdateItem={handleUpdateItem}
                    />
                ) : state.suggestions.length == 0 ? (
                    <CenteredFill>
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
            <DialogActions sx={{ "&&": { pt: "12px" } }}>
                <FocusVisibleButton
                    fullWidth
                    color="secondary"
                    onClick={handleClose}
                >
                    {t("close")}
                </FocusVisibleButton>
                <LoadingButton
                    fullWidth
                    disabled={!hasUnsavedChanges}
                    loading={state.activity == "saving"}
                    color="accent"
                    onClick={handleSave}
                >
                    {t("save")}
                </LoadingButton>
            </DialogActions>
        </Dialog>
    );
};

interface SuggestionOrChoiceListProps {
    items: SCItem[];
    updates: PersonSuggestionUpdates;
    /**
     * Callback invoked when the user changes the value associated with the
     * given suggestion or choice.
     */
    onUpdateItem: (item: SCItem, value: boolean | undefined) => void;
}

const SuggestionOrChoiceList: React.FC<SuggestionOrChoiceListProps> = ({
    items,
    updates,
    onUpdateItem,
}) => (
    <List dense sx={{ width: "100%" }}>
        {items.map((item) => (
            <ListItem
                key={item.id}
                sx={{ px: 0, pb: "24px", justifyContent: "space-between" }}
            >
                <Stack sx={{ gap: "10px" }}>
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        {/* Use the face count as as stand-in for the photo count */}
                        {t("photos_count", { count: item.faces.length })}
                    </Typography>
                    <SuggestionFaceList faces={item.previewFaces} />
                </Stack>
                {!item.fixed && (
                    <ToggleButtonGroup
                        value={itemValueFromUpdate(item, updates)}
                        exclusive
                        onChange={(_, v) => onUpdateItem(item, toItemValue(v))}
                    >
                        <ToggleButton value="no" aria-label={t("no")}>
                            <ClearIcon />
                        </ToggleButton>
                        <ToggleButton value="yes" aria-label={t("yes")}>
                            <CheckIcon />
                        </ToggleButton>
                    </ToggleButtonGroup>
                )}
            </ListItem>
        ))}
    </List>
);

const itemValueFromUpdate = (
    item: SCItem,
    updates: PersonSuggestionUpdates,
) => {
    // Use the in-memory state if available. For choices, fallback to their
    // original state.
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
    // This dance is needed for TypeScript to recognize the type.
    v == "yes" ? true : v == "no" ? false : undefined;
