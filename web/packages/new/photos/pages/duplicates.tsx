import ArrowBackIcon from "@mui/icons-material/ArrowBack";
import DoneIcon from "@mui/icons-material/Done";
import RemoveCircleOutlinedIcon from "@mui/icons-material/RemoveCircleOutlined";
import SortIcon from "@mui/icons-material/Sort";
import {
    Box,
    Checkbox,
    Divider,
    IconButton,
    LinearProgress,
    Stack,
    styled,
    Tooltip,
    Typography,
} from "@mui/material";
import { useRedirectIfNeedsCredentials } from "ente-accounts/components/utils/use-redirect";
import { CenteredFill, SpacedRow } from "ente-base/components/containers";
import { ActivityErrorIndicator } from "ente-base/components/ErrorIndicator";
import { ActivityIndicator } from "ente-base/components/mui/ActivityIndicator";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import {
    OverflowMenu,
    OverflowMenuOption,
} from "ente-base/components/OverflowMenu";
import { Ellipsized2LineTypography } from "ente-base/components/Typography";
import { useBaseContext } from "ente-base/context";
import log from "ente-base/log";
import { formattedByteSize } from "ente-gallery/utils/units";
import { t } from "i18next";
import { useRouter } from "next/router";
import React, {
    memo,
    useCallback,
    useEffect,
    useMemo,
    useReducer,
} from "react";
import Autosizer from "react-virtualized-auto-sizer";
import {
    areEqual,
    VariableSizeList,
    type ListChildComponentProps,
} from "react-window";
import {
    DuplicateItemTile,
    ItemCard,
    TileBottomTextOverlay,
} from "../components/Tiles";
import {
    computeThumbnailGridLayoutParams,
    type ThumbnailGridLayoutParams,
} from "../components/utils/thumbnail-grid-layout";
import {
    deduceDuplicates,
    removeSelectedDuplicateGroups,
    type DuplicateGroup,
} from "../services/dedup";

const Page: React.FC = () => {
    const { onGenericError } = useBaseContext();

    const [state, dispatch] = useReducer(dedupReducer, initialDedupState);

    useRedirectIfNeedsCredentials("/duplicates");

    useEffect(() => {
        dispatch({ type: "analyze" });
        void deduceDuplicates()
            .then((duplicateGroups) =>
                dispatch({ type: "analysisCompleted", duplicateGroups }),
            )
            .catch((e: unknown) => {
                log.error("Failed to detect duplicates", e);
                dispatch({ type: "analysisFailed" });
            });
    }, []);

    const handleRemoveDuplicates = useCallback(() => {
        dispatch({ type: "dedupe" });
        void removeSelectedDuplicateGroups(
            state.duplicateGroups,
            (progress: number) =>
                dispatch({ type: "setDedupeProgress", progress }),
        )
            .then((removedGroupIDs) =>
                dispatch({ type: "dedupeCompleted", removedGroupIDs }),
            )

            .catch((e: unknown) => {
                onGenericError(e);
                dispatch({ type: "dedupeFailed" });
            });
    }, [state.duplicateGroups, onGenericError]);

    const contents = (() => {
        switch (state.analysisStatus) {
            case undefined:
            case "started":
                return <Loading />;
            case "failed":
                return <LoadFailed />;
            case "completed":
                if (state.duplicateGroups.length == 0) {
                    return <NoDuplicatesFound />;
                } else {
                    return (
                        <Duplicates
                            duplicateGroups={state.duplicateGroups}
                            sortOrder={state.sortOrder}
                            onToggleSelection={(index) =>
                                dispatch({ type: "toggleSelection", index })
                            }
                            prunableCount={state.prunableCount}
                            prunableSize={state.prunableSize}
                            dedupeProgress={state.dedupeProgress}
                            onRemoveDuplicates={handleRemoveDuplicates}
                        />
                    );
                }
        }
    })();

    return (
        <Stack sx={{ height: "100vh" }}>
            <Navbar
                sortOrder={state.sortOrder}
                onChangeSortOrder={(sortOrder) =>
                    dispatch({ type: "changeSortOrder", sortOrder })
                }
                onDeselectAll={() => dispatch({ type: "deselectAll" })}
            />
            {contents}
        </Stack>
    );
};

export default Page;

type SortOrder = "prunableCount" | "prunableSize";

interface DedupState {
    /** Status of the analysis ("loading") process. */
    analysisStatus: undefined | "started" | "failed" | "completed";
    /**
     * Groups of duplicates.
     *
     * These are groups of files that our algorithm has detected as exact
     * duplicates, augmented with UI state and various cached properties to make
     * them more amenable to be directly used by the UI component.
     *
     * These are sorted in order of display, reflecting the {@link sortType}
     * user preference.
     */
    duplicateGroups: DuplicateGroup[];
    /**
     * The attribute to use for sorting {@link duplicateGroups}.
     */
    sortOrder: SortOrder;
    /**
     * The number of files that will be pruned if the user decides to dedup the
     * current selection.
     */
    prunableCount: number;
    /**
     * The size (in bytes) that can be saved if the user decides to dedup the
     * current selection.
     */
    prunableSize: number;
    /**
     * If a dedupe is in progress, then this will indicate its progress
     * percentage (a number between 0 and 100).
     */
    dedupeProgress: number | undefined;
}

type DedupAction =
    | { type: "analyze" }
    | { type: "analysisFailed" }
    | { type: "analysisCompleted"; duplicateGroups: DuplicateGroup[] }
    | { type: "changeSortOrder"; sortOrder: SortOrder }
    | { type: "toggleSelection"; index: number }
    | { type: "deselectAll" }
    | { type: "dedupe" }
    | { type: "setDedupeProgress"; progress: number }
    | { type: "dedupeFailed" }
    | { type: "dedupeCompleted"; removedGroupIDs: Set<string> };

const initialDedupState: DedupState = {
    analysisStatus: undefined,
    duplicateGroups: [],
    sortOrder: "prunableSize",
    prunableCount: 0,
    prunableSize: 0,
    dedupeProgress: undefined,
};

const dedupReducer: React.Reducer<DedupState, DedupAction> = (
    state,
    action,
) => {
    switch (action.type) {
        case "analyze":
            return { ...state, analysisStatus: "started" };
        case "analysisFailed":
            return { ...state, analysisStatus: "failed" };
        case "analysisCompleted": {
            const duplicateGroups = sortedCopyOfDuplicateGroups(
                action.duplicateGroups,
                state.sortOrder,
            );
            const selected = duplicateGroups.map(() => true);
            const { prunableCount, prunableSize } =
                deducePrunableCountAndSize(duplicateGroups);
            return {
                ...state,
                analysisStatus: "completed",
                duplicateGroups,
                selected,
                prunableCount,
                prunableSize,
            };
        }

        case "changeSortOrder": {
            const sortOrder = action.sortOrder;
            const duplicateGroups = sortedCopyOfDuplicateGroups(
                state.duplicateGroups,
                sortOrder,
            );
            return { ...state, sortOrder, duplicateGroups };
        }

        case "toggleSelection": {
            const duplicateGroups = [...state.duplicateGroups];
            const duplicateGroup = duplicateGroups[action.index]!;
            duplicateGroup.isSelected = !duplicateGroup.isSelected;
            const { prunableCount, prunableSize } =
                deducePrunableCountAndSize(duplicateGroups);
            return { ...state, duplicateGroups, prunableCount, prunableSize };
        }

        case "deselectAll": {
            const duplicateGroups = state.duplicateGroups.map(
                (duplicateGroup) => ({ ...duplicateGroup, isSelected: false }),
            );
            const { prunableCount, prunableSize } =
                deducePrunableCountAndSize(duplicateGroups);
            return { ...state, duplicateGroups, prunableCount, prunableSize };
        }

        case "dedupe":
            return { ...state, dedupeProgress: 0 };

        case "setDedupeProgress": {
            return { ...state, dedupeProgress: action.progress };
        }

        case "dedupeFailed":
            return { ...state, dedupeProgress: undefined };

        case "dedupeCompleted": {
            const duplicateGroups = state.duplicateGroups.filter(
                ({ id }) => !action.removedGroupIDs.has(id),
            );
            const { prunableCount, prunableSize } =
                deducePrunableCountAndSize(duplicateGroups);
            return {
                ...state,
                duplicateGroups,
                prunableCount,
                prunableSize,
                dedupeProgress: undefined,
            };
        }
    }
};

/**
 * Return a copy of the given {@link duplicateGroups}, also sorting them as per
 * the given {@link sortOrder}.
 *
 * Helper method for the reducer.
 */
const sortedCopyOfDuplicateGroups = (
    duplicateGroups: DuplicateGroup[],
    sortOrder: DedupState["sortOrder"],
) =>
    [...duplicateGroups].sort((a, b) =>
        sortOrder == "prunableSize"
            ? b.prunableSize - a.prunableSize
            : b.prunableCount - a.prunableCount,
    );

/** Helper method for the reducer. */
const deducePrunableCountAndSize = (duplicateGroups: DuplicateGroup[]) => {
    const prunableCount = duplicateGroups.reduce(
        (sum, { prunableCount, isSelected }) =>
            sum + (isSelected ? prunableCount : 0),
        0,
    );
    const prunableSize = duplicateGroups.reduce(
        (sum, { prunableSize, isSelected }) =>
            sum + (isSelected ? prunableSize : 0),
        0,
    );
    return { prunableCount, prunableSize };
};

interface NavbarProps {
    /**
     * The current sort order.
     */
    sortOrder: SortOrder;
    /**
     * Called when the user changes the sort order using the sort order menu
     * visible via the navbar.
     */
    onChangeSortOrder: (sortOrder: SortOrder) => void;
    /**
     * Called when the user selects the deselect all option.
     */
    onDeselectAll: () => void;
}

const Navbar: React.FC<NavbarProps> = ({
    sortOrder,
    onChangeSortOrder,
    onDeselectAll,
}) => {
    const router = useRouter();

    return (
        <Stack
            direction="row"
            sx={(theme) => ({
                alignItems: "center",
                justifyContent: "space-between",
                padding: "8px 4px",
                borderBottom: `1px solid ${theme.vars.palette.divider}`,
            })}
        >
            <Box sx={{ minWidth: "100px" /* 2 icons + gap */ }}>
                <IconButton onClick={router.back}>
                    <ArrowBackIcon />
                </IconButton>
            </Box>
            <Typography variant="h6">{t("remove_duplicates")}</Typography>
            <Stack direction="row" sx={{ gap: "4px" }}>
                <SortMenu {...{ sortOrder, onChangeSortOrder }} />
                <OptionsMenu {...{ onDeselectAll }} />
            </Stack>
        </Stack>
    );
};

type SortMenuProps = Pick<NavbarProps, "sortOrder" | "onChangeSortOrder">;

const SortMenu: React.FC<SortMenuProps> = ({
    sortOrder,
    onChangeSortOrder,
}) => (
    <OverflowMenu
        ariaID="duplicates-sort"
        triggerButtonIcon={
            <Tooltip title={t("sort_by")}>
                <SortIcon />
            </Tooltip>
        }
    >
        <OverflowMenuOption
            endIcon={sortOrder == "prunableSize" ? <DoneIcon /> : undefined}
            onClick={() => onChangeSortOrder("prunableSize")}
        >
            {t("total_size")}
        </OverflowMenuOption>
        <OverflowMenuOption
            endIcon={sortOrder == "prunableCount" ? <DoneIcon /> : undefined}
            onClick={() => onChangeSortOrder("prunableCount")}
        >
            {t("count")}
        </OverflowMenuOption>
    </OverflowMenu>
);

type OptionsMenuProps = Pick<NavbarProps, "onDeselectAll">;

const OptionsMenu: React.FC<OptionsMenuProps> = ({ onDeselectAll }) => (
    <OverflowMenu ariaID="duplicates-options">
        <OverflowMenuOption
            startIcon={<RemoveCircleOutlinedIcon />}
            onClick={onDeselectAll}
        >
            {t("deselect_all")}
        </OverflowMenuOption>
    </OverflowMenu>
);

const Loading: React.FC = () => (
    <CenteredFill>
        <ActivityIndicator />
    </CenteredFill>
);

const LoadFailed: React.FC = () => (
    <CenteredFill>
        <ActivityErrorIndicator />
    </CenteredFill>
);

const NoDuplicatesFound: React.FC = () => (
    <CenteredFill>
        <Typography sx={{ color: "text.muted", textAlign: "center" }}>
            {t("no_duplicates")}
        </Typography>
    </CenteredFill>
);

type DuplicatesProps = Pick<
    DuplicatesListProps,
    "duplicateGroups" | "sortOrder" | "onToggleSelection"
> &
    DeduplicateButtonProps;

const Duplicates: React.FC<DuplicatesProps> = ({
    duplicateGroups,
    sortOrder,
    onToggleSelection,
    ...deduplicateButtonProps
}) => (
    <Stack sx={{ flex: 1 }}>
        <Box sx={{ flex: 1, overflow: "hidden", paddingBlockEnd: 1 }}>
            <Autosizer>
                {({ width, height }) => (
                    <DuplicatesList
                        {...{
                            width,
                            height,
                            duplicateGroups,
                            sortOrder,
                            onToggleSelection,
                        }}
                    />
                )}
            </Autosizer>
        </Box>
        <Stack sx={{ margin: 1 }}>
            <DeduplicateButton {...deduplicateButtonProps} />
        </Stack>
    </Stack>
);

interface DuplicatesListProps {
    /**
     * The width (px) that the list should size itself to.
     */
    width: number;
    /**
     * The height (px) that the list should size itself to.
     */
    height: number;
    /**
     * Groups of duplicates. Guaranteed to be non-empty.
     */
    duplicateGroups: DuplicateGroup[];
    /**
     * The current {@link SortOrder} that is being used for sorting {@link duplicateGroups}.
     */
    sortOrder: SortOrder;
    /**
     * Called when the user toggles the selection for the duplicate group at the
     * given {@link index}.
     */
    onToggleSelection: (index: number) => void;
}

type DuplicatesListItemData = Pick<
    DuplicatesListProps,
    "duplicateGroups" | "onToggleSelection"
> & { layoutParams: ThumbnailGridLayoutParams };

const DuplicatesList: React.FC<DuplicatesListProps> = ({
    width,
    height,
    duplicateGroups,
    sortOrder,
    onToggleSelection,
}) => {
    const layoutParams = useMemo(
        () => computeThumbnailGridLayoutParams(width),
        [width],
    );

    const itemData = { layoutParams, duplicateGroups, onToggleSelection };
    const itemCount = duplicateGroups.length;
    const itemSize = (index: number) => {
        // The height of the header is driven by the height of the Checkbox,
        // which is 42px high, and the divider, which is 1px. The rest of the
        // height comes from the fixed paddings, margins on the header, the
        // divider, and on the row itself.
        const fixedHeight = 24 + 42 + 4 + 1 + 20 + 16;

        const duplicateGroup = duplicateGroups[index]!;
        const rowCount = Math.ceil(
            duplicateGroup.items.length / layoutParams.columns,
        );
        const rowHeight = layoutParams.itemHeight + layoutParams.gap;

        return fixedHeight + rowCount * rowHeight;
    };
    const itemKey = (index: number, itemData: DuplicatesListItemData) =>
        itemData.duplicateGroups[index]!.id;

    // Derive a key based on aspects whose change should cause the list to be
    // recreated. This is the easiest way I've found to get react-window to
    // invalidate `itemSize` values when, say, the width changes.
    const key = `${width}-${sortOrder}`;

    return (
        <VariableSizeList
            key={key}
            style={
                {
                    "--et-padding-inline": `${layoutParams.paddingInline}px`,
                } as React.CSSProperties
            }
            {...{ height, width, itemData, itemCount, itemSize, itemKey }}
        >
            {ListItem}
        </VariableSizeList>
    );
};

const ListItem: React.FC<ListChildComponentProps<DuplicatesListItemData>> =
    memo(({ index, style, data }) => {
        const { layoutParams, duplicateGroups, onToggleSelection } = data;

        // For smaller screens, hide to divider to reduce visual noise. For
        // larger screens, the divider is helpful in guiding the user's eyes to
        // the checkbox which is otherwise at the right end of the header.
        const hideDivider = layoutParams.isSmallerLayout;

        const duplicateGroup = duplicateGroups[index]!;
        const items = duplicateGroup.items;
        const count = items.length;
        const itemSize = formattedByteSize(duplicateGroup.itemSize);
        const checked = duplicateGroup.isSelected;
        const onChange = () => onToggleSelection(index);

        return (
            <Stack
                {...{ style }}
                sx={[
                    { paddingBlockEnd: "16px" },
                    checked ? { opacity: 1 } : { opacity: 0.8 },
                ]}
            >
                <SpacedRow
                    sx={{
                        mx: 1,
                        paddingInline: "var(--et-padding-inline)",
                        paddingBlock: "24px 0px",
                    }}
                >
                    <Typography
                        sx={{ color: checked ? "text.base" : "text.muted" }}
                    >
                        {t("duplicate_group_description", { count, itemSize })}
                    </Typography>
                    {/* The size of this Checkbox is 42px. */}
                    <Checkbox {...{ checked, onChange }} />
                </SpacedRow>
                <Divider
                    variant="middle"
                    sx={[
                        { marginBlock: "4px 20px" },
                        hideDivider ? { opacity: 0 } : { opacity: 0.8 },
                    ]}
                />
                <ItemGrid {...{ layoutParams }}>
                    {items.map((item, j) => (
                        <ItemCard
                            key={j}
                            TileComponent={DuplicateItemTile}
                            coverFile={item.file}
                        >
                            <TileBottomTextOverlay>
                                <Ellipsized2LineTypography variant="small">
                                    {item.collectionName}
                                </Ellipsized2LineTypography>
                            </TileBottomTextOverlay>
                        </ItemCard>
                    ))}
                </ItemGrid>
            </Stack>
        );
    }, areEqual);

type ItemGridProps = Pick<DuplicatesListItemData, "layoutParams">;

const ItemGrid = styled("div", {
    shouldForwardProp: (prop) => prop != "layoutParams",
})<ItemGridProps>(
    ({ layoutParams }) => `
    display: grid;
    padding-inline: ${layoutParams.paddingInline}px;
    grid-template-columns: repeat(${layoutParams.columns}, ${layoutParams.itemWidth}px);
    grid-auto-rows: ${layoutParams.itemHeight}px;
    gap: ${layoutParams.gap}px;
`,
);

type DeduplicateButtonProps = Pick<
    DedupState,
    "prunableCount" | "prunableSize" | "dedupeProgress"
> & {
    /**
     * Called when the user presses the button to remove duplicates.
     */
    onRemoveDuplicates: () => void;
};

const DeduplicateButton: React.FC<DeduplicateButtonProps> = ({
    prunableCount,
    prunableSize,
    dedupeProgress,
    onRemoveDuplicates,
}) => (
    <FocusVisibleButton
        sx={{ minWidth: "min(100%, 320px)", margin: "auto" }}
        disabled={prunableCount == 0 || dedupeProgress !== undefined}
        onClick={onRemoveDuplicates}
    >
        <Stack
            sx={{
                gap: 1,
                // Prevent a layout shift by giving a minHeight that is larger
                // than all expected states.
                minHeight: "45px",
                justifyContent: "center",
                flex: 1,
            }}
        >
            {dedupeProgress !== undefined ? (
                <LinearProgress
                    sx={{ borderRadius: "4px" }}
                    variant={
                        dedupeProgress === 0 ? "indeterminate" : "determinate"
                    }
                    value={dedupeProgress}
                />
            ) : (
                <>
                    <Typography>
                        {t("remove_duplicates_button_count", {
                            count: prunableCount,
                        })}
                    </Typography>
                    <Typography variant="small" sx={{ fontWeight: "regular" }}>
                        {formattedByteSize(prunableSize)}
                    </Typography>
                </>
            )}
        </Stack>
    </FocusVisibleButton>
);
