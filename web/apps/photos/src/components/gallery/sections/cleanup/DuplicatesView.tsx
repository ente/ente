import {
    deduceDuplicates,
    removeSelectedDuplicateGroups,
    type DuplicateGroup,
} from "@/services/dedup";
import DoneIcon from "@mui/icons-material/Done";
import SortIcon from "@mui/icons-material/Sort";
import {
    Box,
    Button,
    Checkbox,
    LinearProgress,
    Stack,
    styled,
    Tooltip,
    Typography,
} from "@mui/material";
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
import {
    DuplicateItemTile,
    ItemCard,
    TileBottomTextOverlay,
} from "ente-new/photos/components/Tiles";
import { t } from "i18next";
import React, { memo, useCallback, useEffect, useReducer } from "react";
import Autosizer from "react-virtualized-auto-sizer";
import {
    areEqual,
    VariableSizeList,
    type ListChildComponentProps,
} from "react-window";

interface DuplicatesViewProps {
    onRemoteFilesPull: () => Promise<void>;
}

export function DuplicatesView({ onRemoteFilesPull }: DuplicatesViewProps) {
    const { onGenericError } = useBaseContext();

    const [state, dispatch] = useReducer(dedupReducer, initialDedupState);

    useEffect(() => {
        let isCurrent = true;
        dispatch({ type: "analyze" });
        void deduceDuplicates()
            .then((duplicateGroups) => {
                if (isCurrent)
                    dispatch({ type: "analysisCompleted", duplicateGroups });
            })
            .catch((e: unknown) => {
                if (isCurrent) {
                    log.error("Failed to detect duplicates", e);
                    dispatch({ type: "analysisFailed" });
                }
            });
        return () => {
            isCurrent = false;
        };
    }, []);

    const handleRemoveDuplicates = useCallback(() => {
        dispatch({ type: "dedupe" });
        void removeSelectedDuplicateGroups(
            state.duplicateGroups,
            (progress: number) =>
                dispatch({ type: "setDedupeProgress", progress }),
            onRemoteFilesPull,
        )
            .then((removedGroupIDs) =>
                dispatch({ type: "dedupeCompleted", removedGroupIDs }),
            )

            .catch((e: unknown) => {
                onGenericError(e);
                dispatch({ type: "dedupeFailed" });
            });
    }, [state.duplicateGroups, onGenericError, onRemoteFilesPull]);

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
        <Stack sx={{ flex: 1, minHeight: 0, px: { xs: "16px", md: "24px" } }}>
            <Navbar
                duplicateGroups={state.duplicateGroups}
                disabled={state.dedupeProgress !== undefined}
                sortOrder={state.sortOrder}
                onChangeSortOrder={(sortOrder) =>
                    dispatch({ type: "changeSortOrder", sortOrder })
                }
                onDeselectAll={() => dispatch({ type: "deselectAll" })}
            />
            {contents}
        </Stack>
    );
}

type SortOrder = "prunableCount" | "prunableSize";

interface DedupState {
    analysisStatus: undefined | "started" | "failed" | "completed";
    duplicateGroups: DuplicateGroup[];
    sortOrder: SortOrder;
    prunableCount: number;
    prunableSize: number;
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
            duplicateGroups[action.index] = {
                ...duplicateGroup,
                isSelected: !duplicateGroup.isSelected,
            };
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

const sortedCopyOfDuplicateGroups = (
    duplicateGroups: DuplicateGroup[],
    sortOrder: DedupState["sortOrder"],
) =>
    [...duplicateGroups].sort((a, b) =>
        sortOrder == "prunableSize"
            ? b.prunableSize - a.prunableSize
            : b.prunableCount - a.prunableCount,
    );

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
    duplicateGroups: DuplicateGroup[];
    disabled: boolean;
    sortOrder: SortOrder;
    onChangeSortOrder: (sortOrder: SortOrder) => void;
    onDeselectAll: () => void;
}

const Navbar: React.FC<NavbarProps> = ({
    duplicateGroups,
    disabled,
    sortOrder,
    onChangeSortOrder,
    onDeselectAll,
}) => {
    const totalSize = duplicateGroups.reduce(
        (sum, group) => sum + group.prunableSize,
        0,
    );
    return (
        <Stack
            direction="row"
            sx={{
                alignItems: "flex-start",
                justifyContent: "space-between",
                gap: 2,
                flexWrap: "wrap",
                mb: "24px",
            }}
        >
            <Stack sx={{ gap: "2px", flex: "1 1 280px" }}>
                <Typography
                    component="h1"
                    sx={{
                        fontFamily: "'Outfit Variable', sans-serif",
                        fontSize: "24px",
                        fontWeight: 600,
                        lineHeight: "32px",
                    }}
                >
                    {t("duplicates")}
                </Typography>
                {duplicateGroups.length > 0 && (
                    <Typography
                        sx={{
                            fontSize: "13px",
                            lineHeight: "19px",
                            color: "text.muted",
                        }}
                    >
                        {t("duplicates_summary", {
                            count: duplicateGroups.length,
                            size: formattedByteSize(totalSize),
                        })}
                    </Typography>
                )}
            </Stack>
            {duplicateGroups.length > 0 && (
                <Stack direction="row" sx={{ alignItems: "center" }}>
                    <Button
                        variant="text"
                        color="secondary"
                        disabled={
                            disabled ||
                            !duplicateGroups.some((group) => group.isSelected)
                        }
                        onClick={onDeselectAll}
                        sx={{
                            height: "40px",
                            px: "18px",
                            borderRadius: "24px",
                            fontSize: "12px",
                            fontWeight: 500,
                            color: "text.muted",
                        }}
                    >
                        {t("deselect_all")}
                    </Button>
                    <SortMenu {...{ sortOrder, onChangeSortOrder }} />
                </Stack>
            )}
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
    "duplicateGroups" | "onToggleSelection"
> &
    DeduplicateButtonProps;

const Duplicates: React.FC<DuplicatesProps> = ({
    duplicateGroups,
    onToggleSelection,
    ...deduplicateButtonProps
}) => (
    <Stack sx={{ flex: 1, minHeight: 0 }}>
        <Box sx={{ flex: 1, overflow: "hidden", paddingBlockEnd: 1 }}>
            <Autosizer>
                {({ width, height }) => (
                    <DuplicatesList
                        {...{
                            width,
                            height,
                            duplicateGroups,
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
    width: number;
    height: number;
    duplicateGroups: DuplicateGroup[];
    onToggleSelection: (index: number) => void;
}

type DuplicatesListItemData = Pick<
    DuplicatesListProps,
    "duplicateGroups" | "onToggleSelection"
> & { columns: number };

const DuplicatesList: React.FC<DuplicatesListProps> = ({
    width,
    height,
    duplicateGroups,
    onToggleSelection,
}) => {
    // Leave room for a conventional scrollbar and some space beside the tiles.
    const scrollbarAllowance = 24;
    const columns = Math.max(
        1,
        Math.floor((width - scrollbarAllowance + 10) / 142),
    );
    return (
        <VariableSizeList
            // Invalidate cached heights when groups are reordered or wrap differently.
            key={`${columns}-${duplicateGroups.map((group) => `${group.id}:${group.items.length}`).join(",")}`}
            {...{ width, height }}
            itemData={{ duplicateGroups, onToggleSelection, columns }}
            itemCount={duplicateGroups.length}
            itemSize={(index) => {
                const rows = Math.ceil(
                    duplicateGroups[index]!.items.length / columns,
                );
                return 20 + 10 + rows * 132 + (rows - 1) * 10 + 20;
            }}
            itemKey={(index, data: DuplicatesListItemData) =>
                data.duplicateGroups[index]!.id
            }
        >
            {ListItem}
        </VariableSizeList>
    );
};

const ListItem: React.FC<ListChildComponentProps<DuplicatesListItemData>> =
    memo(({ index, style, data }) => {
        const group = data.duplicateGroups[index]!;
        const label = t("duplicate_saved_times", { count: group.items.length });
        return (
            <Stack style={style} sx={{ gap: "10px", pb: "20px" }}>
                <SpacedRow sx={{ height: "20px", flexShrink: 0, gap: 1 }}>
                    <Stack
                        component="label"
                        direction="row"
                        sx={{
                            gap: "10px",
                            alignItems: "center",
                            cursor: "pointer",
                        }}
                    >
                        <Checkbox
                            color="accent"
                            checked={group.isSelected}
                            onChange={() => data.onToggleSelection(index)}
                            size="small"
                            sx={{
                                p: 0,
                                width: "20px",
                                height: "20px",
                                flexShrink: 0,
                                "& .MuiSvgIcon-root": {
                                    fontSize: "20px",
                                    display: "block",
                                },
                            }}
                        />
                        <Typography
                            sx={{
                                fontSize: "13px",
                                fontWeight: 500,
                                lineHeight: "20px",
                                display: "flex",
                                alignItems: "center",
                            }}
                        >
                            {label}
                        </Typography>
                    </Stack>
                    <Typography
                        sx={{
                            fontSize: "12px",
                            lineHeight: "17px",
                            color: "text.muted",
                            whiteSpace: "nowrap",
                        }}
                    >
                        {t("duplicate_frees_size", {
                            size: formattedByteSize(group.prunableSize),
                        })}
                    </Typography>
                </SpacedRow>
                <Box
                    sx={{
                        display: "grid",
                        gridTemplateColumns: `repeat(${data.columns}, 132px)`,
                        gap: "10px",
                    }}
                >
                    {group.items.map((item) => (
                        <ItemCard
                            key={item.file.id}
                            TileComponent={DuplicatePreview}
                            coverFile={item.file}
                        >
                            <TileBottomTextOverlay
                                sx={{ p: "8px", justifyContent: "flex-start" }}
                            >
                                <Ellipsized2LineTypography
                                    title={item.collectionName}
                                    sx={{
                                        fontSize: "12px",
                                        lineHeight: "16px",
                                        fontWeight: 400,
                                        opacity: 0.75,
                                        width: "100%",
                                    }}
                                >
                                    {item.collectionName}
                                </Ellipsized2LineTypography>
                            </TileBottomTextOverlay>
                        </ItemCard>
                    ))}
                </Box>
            </Stack>
        );
    }, areEqual);

const DuplicatePreview = styled(DuplicateItemTile)({
    width: 132,
    height: 132,
    borderRadius: "10px",
    flexShrink: 0,
    // Keep placeholder thumbnails as borderless as photo thumbnails.
    "& > div": { border: 0, borderRadius: "inherit" },
});

type DeduplicateButtonProps = Pick<
    DedupState,
    "prunableCount" | "prunableSize" | "dedupeProgress"
> & { onRemoveDuplicates: () => void };

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
                // Reserve space for every button state.
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
