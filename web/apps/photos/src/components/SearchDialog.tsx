import {
    schedulePhotoSearch,
    searchCategories,
    searchCategoryForType,
    type SearchCategory,
} from "@/services/search/search-dialog";
import { sidebarSearchOptionsForString } from "@/services/search/sidebar-search-registry";
import { Search01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import AutoAwesomeIcon from "@mui/icons-material/AutoAwesome";
import CalendarIcon from "@mui/icons-material/CalendarMonth";
import CloseIcon from "@mui/icons-material/Close";
import ImageIcon from "@mui/icons-material/Image";
import LocationOffIcon from "@mui/icons-material/LocationOffOutlined";
import LocationIcon from "@mui/icons-material/LocationOn";
import CameraIcon from "@mui/icons-material/PhotoCameraOutlined";
import SettingsIcon from "@mui/icons-material/Settings";
import {
    Box,
    Button,
    CircularProgress,
    Dialog,
    IconButton,
    InputBase,
    Stack,
    Tab,
    Tabs,
    Tooltip,
    Typography,
    styled,
} from "@mui/material";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import log from "ente-base/log";
import { isHLSGenerationSupported } from "ente-gallery/services/video";
import { SearchPeopleList } from "ente-new/photos/components/PeopleList";
import { ItemCard } from "ente-new/photos/components/Tiles";
import {
    useHLSGenerationStatusSnapshot,
    useMLStatusSnapshot,
    usePeopleStateSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import { isMLSupported } from "ente-new/photos/services/ml";
import { searchOptionsForString } from "ente-new/photos/services/search";
import type { SearchOption } from "ente-new/photos/services/search/types";
import { t } from "i18next";
import React, { useEffect, useMemo, useRef, useState } from "react";

export interface SearchDialogProps extends ModalVisibilityProps {
    onSelectSearchOption: (option: SearchOption) => void;
    onSelectPeople: () => void;
    onSelectPerson: (personID: string) => void;
}

export const SearchButton: React.FC<ButtonishProps> = ({ onClick }) => {
    const small = useIsSmallWidth();
    const shortcut =
        typeof navigator !== "undefined" && /mac/i.test(navigator.userAgent)
            ? "⌘K"
            : "Ctrl+K";
    return (
        <Tooltip title={t("search_shortcut", { shortcut })}>
            <FocusVisibleButton
                color="secondary"
                aria-label={t("search")}
                aria-haspopup="dialog"
                onClick={onClick}
                sx={{
                    minWidth: 0,
                    width: small ? 40 : 48,
                    height: small ? 40 : 48,
                    p: 0,
                    borderRadius: "16px",
                }}
            >
                <HugeiconsIcon icon={Search01Icon} size={20} />
            </FocusVisibleButton>
        </Tooltip>
    );
};

export const SearchDialog: React.FC<SearchDialogProps> = ({
    open,
    onClose,
    onSelectSearchOption,
    onSelectPeople,
    onSelectPerson,
}) => {
    const [query, setQuery] = useState("");
    const [category, setCategory] = useState<SearchCategory>("all");
    const [retry, setRetry] = useState(0);
    const [photoResults, setPhotoResults] = useState<{
        query: string;
        options: SearchOption[];
        loading: boolean;
        failed: boolean;
    }>({ query: "", options: [], loading: false, failed: false });
    const inputRef = useRef<HTMLInputElement>(null);
    const resultsRef = useRef<HTMLDivElement>(null);
    const afterExit = useRef<(() => void) | undefined>(undefined);
    const normalizedQuery = query.trim();

    useEffect(() => {
        if (!open || !normalizedQuery) return;
        setPhotoResults({
            query: normalizedQuery,
            options: [],
            loading: true,
            failed: false,
        });
        return schedulePhotoSearch(
            normalizedQuery,
            searchOptionsForString,
            ({ options, failed, error }) => {
                if (failed)
                    log.warn(
                        "Search dialog could not load photo results",
                        error,
                    );
                setPhotoResults({
                    query: normalizedQuery,
                    options,
                    loading: false,
                    failed,
                });
            },
        );
    }, [open, normalizedQuery, retry]);

    const sidebarOptions = useMemo(
        () =>
            normalizedQuery
                ? sidebarSearchOptionsForString(normalizedQuery)
                : [],
        [normalizedQuery],
    );
    const options = [
        ...(photoResults.query === normalizedQuery ? photoResults.options : []),
        ...sidebarOptions,
    ];
    const groups = searchCategories
        .filter((c) => c !== "all")
        .map((id) => ({
            id,
            options: options.filter(
                (o) => searchCategoryForType(o.suggestion.type) === id,
            ),
        }));
    const shownGroups = groups.filter(
        (g) => (category === "all" || category === g.id) && g.options.length,
    );
    const shownOptions = shownGroups.flatMap((g) => g.options);
    const loading =
        !!normalizedQuery &&
        (photoResults.query !== normalizedQuery || photoResults.loading);
    const failed =
        !!normalizedQuery &&
        photoResults.query === normalizedQuery &&
        photoResults.failed;

    const choose = (action: () => void) => {
        if (!open || afterExit.current) return;
        afterExit.current = action;
        onClose();
    };
    const dismiss = () => {
        afterExit.current = undefined;
        onClose();
    };
    const handleExited = () => {
        const action = afterExit.current;
        afterExit.current = undefined;
        action?.();
    };
    const handleKeyDown = (event: React.KeyboardEvent) => {
        if (event.key === "Escape") {
            event.stopPropagation();
            dismiss();
            return;
        }
        if (
            (event.metaKey || event.ctrlKey) &&
            event.key.toLowerCase() === "k"
        ) {
            event.preventDefault();
            event.stopPropagation();
            inputRef.current?.focus();
            return;
        }
        // Keep gallery selection shortcuts out of the dialog; preserve native text selection.
        if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "a")
            event.stopPropagation();
        const target = event.target as HTMLElement;
        const rows = Array.from(
            resultsRef.current?.querySelectorAll<HTMLButtonElement>(
                "button[data-search-result]",
            ) ?? [],
        );
        if (
            event.key === "Enter" &&
            target === inputRef.current &&
            rows.length
        ) {
            event.preventDefault();
            rows[0]?.click();
        } else if (
            (event.key === "ArrowDown" || event.key === "ArrowUp") &&
            rows.length &&
            (target === inputRef.current ||
                target.closest("[data-search-result]"))
        ) {
            event.preventDefault();
            const current = rows.indexOf(
                target.closest<HTMLButtonElement>("[data-search-result]")!,
            );
            const next =
                current < 0
                    ? event.key === "ArrowDown"
                        ? 0
                        : rows.length - 1
                    : (current +
                          (event.key === "ArrowDown" ? 1 : -1) +
                          rows.length) %
                      rows.length;
            rows[next]?.focus();
            rows[next]?.scrollIntoView({ block: "nearest" });
        }
    };

    return (
        <Dialog
            data-search-dialog
            open={open}
            onClose={dismiss}
            aria-label={t("search")}
            maxWidth={false}
            fullWidth
            onKeyDown={handleKeyDown}
            slotProps={{
                transition: {
                    onExited: handleExited,
                    onEntered: () => inputRef.current?.focus(),
                },
                backdrop: { sx: { backgroundColor: "rgba(0,0,0,0.4)" } },
                container: { sx: { alignItems: "flex-start" } },
                paper: {
                    sx: {
                        width: "621px",
                        maxWidth: "calc(100% - 24px)",
                        m: { xs: "12px", sm: "84px 12px 24px" },
                        maxHeight: {
                            xs: "calc(100dvh - 24px)",
                            sm: "calc(100dvh - 108px)",
                        },
                        p: "20px",
                        gap: "24px",
                        borderRadius: "20px",
                        bgcolor: "background.default",
                        backgroundImage: "none",
                        border: "1px solid",
                        borderColor: "stroke.faint",
                        boxShadow: "0 24px 60px rgba(0,0,0,.25)",
                        overflow: "hidden",
                    },
                },
            }}
        >
            <Stack
                direction="row"
                sx={{
                    alignItems: "center",
                    flexShrink: 0,
                    gap: "10px",
                    px: "16px",
                    height: "52px",
                    borderRadius: "12px",
                    bgcolor: "background.paper",
                    border: "1px solid",
                    borderColor: "stroke.faint",
                }}
            >
                <Box sx={{ display: "flex", color: "text.muted" }}>
                    <HugeiconsIcon icon={Search01Icon} size={20} />
                </Box>
                <InputBase
                    inputRef={inputRef}
                    autoFocus
                    fullWidth
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder={t("search_hint")}
                    inputProps={{
                        "aria-label": t("search"),
                        "aria-controls": "search-dialog-results",
                        autoComplete: "off",
                    }}
                    sx={{ minWidth: 0, fontSize: 14, fontWeight: 500 }}
                />
                {query && (
                    <IconButton
                        size="small"
                        aria-label={t("search_clear")}
                        onClick={() => {
                            setQuery("");
                            inputRef.current?.focus();
                        }}
                    >
                        <CloseIcon fontSize="small" />
                    </IconButton>
                )}
                <IconButton
                    size="small"
                    aria-label={t("close")}
                    onClick={dismiss}
                >
                    <Typography component="span" variant="mini">
                        Esc
                    </Typography>
                </IconButton>
            </Stack>
            {normalizedQuery && (
                <Tabs
                    value={category}
                    onChange={(_, value: SearchCategory) => setCategory(value)}
                    variant="scrollable"
                    scrollButtons="auto"
                    aria-label={t("search_results")}
                    sx={{
                        minHeight: 36,
                        flexShrink: 0,
                        borderBottom: "1px solid",
                        borderColor: "stroke.faint",
                        "& .MuiTabs-indicator": { bgcolor: "text.base" },
                        "& .MuiTab-root": {
                            minWidth: 0,
                            minHeight: 36,
                            p: 0,
                            mr: "24px",
                            fontSize: 14,
                            textTransform: "none",
                            color: "text.muted",
                        },
                        "& .Mui-selected": {
                            color: "text.base",
                            fontWeight: 600,
                        },
                    }}
                >
                    {searchCategories.map((id) => {
                        const count =
                            id === "all"
                                ? options.length
                                : (groups.find((g) => g.id === id)?.options
                                      .length ?? 0);
                        return (
                            <Tab
                                key={id}
                                value={id}
                                id={`search-tab-${id}`}
                                aria-controls="search-dialog-results"
                                label={
                                    <Stack
                                        direction="row"
                                        sx={{ alignItems: "center", gap: 0.5 }}
                                    >
                                        {categoryLabel(id)}
                                        {count > 0 && (
                                            <Typography
                                                component="span"
                                                variant="mini"
                                                sx={{ color: "text.muted" }}
                                            >
                                                {count}
                                            </Typography>
                                        )}
                                    </Stack>
                                }
                            />
                        );
                    })}
                </Tabs>
            )}
            <Stack
                ref={resultsRef}
                id="search-dialog-results"
                role={normalizedQuery ? "tabpanel" : undefined}
                aria-labelledby={
                    normalizedQuery ? `search-tab-${category}` : undefined
                }
                sx={{ gap: "24px", minHeight: 0, overflowY: "auto" }}
            >
                {!normalizedQuery ? (
                    <SearchPeopleAndStatus
                        onSelectPeople={() => choose(onSelectPeople)}
                        onSelectPerson={(id) =>
                            choose(() => onSelectPerson(id))
                        }
                    />
                ) : (
                    <>
                        {loading && (
                            <Stack
                                direction="row"
                                role="status"
                                sx={{
                                    alignItems: "center",
                                    gap: 1,
                                    color: "text.muted",
                                }}
                            >
                                <CircularProgress size={16} />
                                <Typography variant="small">
                                    {t("loading")}
                                </Typography>
                            </Stack>
                        )}
                        {failed && (
                            <Stack
                                role="alert"
                                sx={{ gap: 1, alignItems: "flex-start" }}
                            >
                                <Typography
                                    variant="small"
                                    sx={{ color: "text.muted" }}
                                >
                                    {t("search_error")}
                                </Typography>
                                <Button
                                    size="small"
                                    color="secondary"
                                    onClick={() => setRetry((v) => v + 1)}
                                >
                                    {t("retry")}
                                </Button>
                            </Stack>
                        )}
                        {shownGroups.map((group) => (
                            <Stack key={group.id} sx={{ gap: "12px" }}>
                                <Stack
                                    direction="row"
                                    sx={{
                                        justifyContent: "space-between",
                                        alignItems: "center",
                                    }}
                                >
                                    <Typography variant="h6">
                                        {categoryLabel(group.id)}
                                    </Typography>
                                    <Typography
                                        variant="mini"
                                        sx={{ color: "text.muted" }}
                                    >
                                        {t("search_result_count", {
                                            count: group.options.length,
                                        })}
                                    </Typography>
                                </Stack>
                                <Stack sx={{ gap: "4px" }}>
                                    {group.options.map((option, i) => (
                                        <SearchResultRow
                                            key={`${group.id}-${i}`}
                                            option={option}
                                            onClick={() =>
                                                choose(() =>
                                                    onSelectSearchOption(
                                                        option,
                                                    ),
                                                )
                                            }
                                        />
                                    ))}
                                </Stack>
                            </Stack>
                        ))}
                        {!loading && !failed && shownOptions.length === 0 && (
                            <Stack
                                sx={{
                                    alignItems: "center",
                                    textAlign: "center",
                                    gap: "16px",
                                    py: "20px",
                                }}
                            >
                                <Box
                                    component="img"
                                    src="/images/auth-ducky.svg"
                                    alt=""
                                    sx={{
                                        width: 130,
                                        height: 100,
                                        objectFit: "contain",
                                    }}
                                />
                                <Typography variant="h3">
                                    {t("search_no_matches")}
                                </Typography>
                                <Typography
                                    variant="small"
                                    sx={{ color: "text.muted" }}
                                >
                                    {t(
                                        category === "all"
                                            ? "search_try_another"
                                            : "search_empty_category",
                                    )}
                                </Typography>
                                {category !== "all" && (
                                    <Button
                                        color="secondary"
                                        onClick={() => setCategory("all")}
                                    >
                                        {t("search_see_all")}
                                    </Button>
                                )}
                            </Stack>
                        )}
                    </>
                )}
            </Stack>
            <Stack
                direction="row"
                sx={{
                    justifyContent: "space-between",
                    alignItems: "center",
                    flexShrink: 0,
                    pt: "12px",
                    borderTop: "1px solid",
                    borderColor: "stroke.faint",
                    color: "text.muted",
                }}
            >
                <Typography
                    variant="mini"
                    sx={{ display: { xs: "none", sm: "block" } }}
                >
                    {t("search_navigate_hint")}
                </Typography>
                <Typography variant="mini" role="status">
                    {normalizedQuery && !loading
                        ? t("search_result_count", {
                              count: shownOptions.length,
                          })
                        : ""}
                </Typography>
            </Stack>
        </Dialog>
    );
};

const categoryLabel = (category: SearchCategory) =>
    t(category === "places" ? "search_places" : category);

const SearchPeopleAndStatus: React.FC<
    Pick<SearchDialogProps, "onSelectPeople" | "onSelectPerson">
> = ({ onSelectPeople, onSelectPerson }) => {
    const mlStatus = useMLStatusSnapshot();
    const people = usePeopleStateSnapshot()?.visiblePeople;
    const video = useHLSGenerationStatusSnapshot();
    if (!isMLSupported && !isHLSGenerationSupported) return null;
    let label: string | undefined;
    switch (mlStatus?.phase) {
        case "scheduled":
            label = t("indexing_scheduled");
            break;
        case "indexing":
            label = t("indexing_photos");
            break;
        case "fetching":
            label = t("indexing_fetching");
            break;
        case "clustering":
            label = t("indexing_people");
            break;
        default:
            if (
                isHLSGenerationSupported &&
                video?.enabled &&
                video.status === "processing"
            )
                label = t("processing_videos_status");
    }
    if (!people?.length && !label) return null;
    return (
        <Stack sx={{ gap: "16px" }}>
            {!!people?.length && (
                <>
                    <Stack
                        direction="row"
                        sx={{
                            alignItems: "center",
                            justifyContent: "space-between",
                        }}
                    >
                        <Typography variant="h6">{t("people")}</Typography>
                        <Button
                            variant="text"
                            color="secondary"
                            size="small"
                            onClick={onSelectPeople}
                        >
                            {t("search_view_all")}
                        </Button>
                    </Stack>
                    <SearchPeopleList
                        people={people}
                        onSelectPerson={onSelectPerson}
                    />
                </>
            )}
            {label && (
                <Stack
                    direction="row"
                    role="status"
                    sx={{ alignItems: "center", gap: 1, color: "text.muted" }}
                >
                    <CircularProgress size={14} />
                    <Typography variant="small">{label}</Typography>
                </Stack>
            )}
        </Stack>
    );
};

const SearchResultRow: React.FC<{
    option: SearchOption;
    onClick: () => void;
}> = ({ option, onClick }) => {
    const { suggestion, fileCount, previewFiles } = option;
    const group = searchCategoryForType(suggestion.type);
    const person = suggestion.type === "person" ? suggestion.person : undefined;
    return (
        <ResultButton data-search-result onClick={onClick}>
            {group === "photos" || group === "settings" ? (
                <Stack
                    sx={{
                        width: 40,
                        height: 40,
                        flexShrink: 0,
                        alignItems: "center",
                        justifyContent: "center",
                        color: "text.muted",
                    }}
                >
                    {iconForOption(option)}
                </Stack>
            ) : (
                <Box
                    aria-hidden
                    sx={{
                        flexShrink: 0,
                        borderRadius: person ? "50%" : "8px",
                        overflow: "hidden",
                    }}
                >
                    <ItemCard
                        TileComponent={ResultCover}
                        coverFile={person?.displayFaceFile ?? previewFiles[0]}
                        coverFaceID={person?.displayFaceID}
                    />
                </Box>
            )}
            <Stack sx={{ flex: 1, minWidth: 0, gap: "4px" }}>
                <Typography
                    sx={{
                        fontSize: 14,
                        fontWeight: 500,
                        overflowWrap: "anywhere",
                    }}
                >
                    {suggestion.label}
                </Typography>
                <Typography
                    variant="mini"
                    sx={{ color: "text.muted", overflowWrap: "anywhere" }}
                >
                    {suggestion.type === "sidebarAction"
                        ? suggestion.path.join(" › ")
                        : `${labelForOption(option)} · ${t("photos_count", { count: fileCount })}`}
                </Typography>
            </Stack>
            {group === "photos" && (
                <Stack
                    direction="row"
                    aria-hidden
                    sx={{
                        gap: "4px",
                        flexShrink: 0,
                        "& > :not(:first-of-type)": {
                            display: { xs: "none", sm: "block" },
                        },
                    }}
                >
                    {previewFiles.slice(0, 3).map((file) => (
                        <ItemCard
                            key={file.id}
                            coverFile={file}
                            TileComponent={ResultPreview}
                        />
                    ))}
                </Stack>
            )}
            <ArrowForwardIosIcon
                sx={{ fontSize: 12, color: "text.muted", flexShrink: 0 }}
            />
        </ResultButton>
    );
};

const ResultButton = styled("button")(({ theme }) => ({
    width: "100%",
    minHeight: 56,
    display: "flex",
    alignItems: "center",
    gap: 12,
    padding: "8px 12px 8px 8px",
    border: 0,
    borderRadius: 12,
    textAlign: "left",
    cursor: "pointer",
    color: theme.vars.palette.text.base,
    backgroundColor: theme.vars.palette.background.paper,
    "&:hover": { backgroundColor: theme.vars.palette.fill.fainter },
    "&:focus-visible": {
        outline: `2px solid ${theme.vars.palette.accent.main}`,
        outlineOffset: -2,
    },
}));
const ResultCover = styled("div")({
    width: 40,
    height: 40,
    overflow: "hidden",
    "& img": { width: "100%", height: "100%", objectFit: "cover" },
});
const ResultPreview = styled(ResultCover)({
    width: 36,
    height: 36,
    borderRadius: 6,
});

const iconForOption = (option: SearchOption) => {
    switch (option.suggestion.type) {
        case "date":
            return <CalendarIcon fontSize="small" />;
        case "cameraMake":
        case "cameraModel":
            return <CameraIcon fontSize="small" />;
        case "noLocation":
            return <LocationOffIcon fontSize="small" />;
        case "location":
        case "city":
            return <LocationIcon fontSize="small" />;
        case "clip":
            return <AutoAwesomeIcon fontSize="small" />;
        case "sidebarAction":
            return <SettingsIcon fontSize="small" />;
        default:
            return <ImageIcon fontSize="small" />;
    }
};
const labelForOption = (option: SearchOption) => {
    switch (option.suggestion.type) {
        case "collection":
            return t("album");
        case "fileType":
            return t("file_type");
        case "fileName":
            return t("file_name");
        case "fileCaption":
            return t("description");
        case "cameraMake":
            return t("camera_make");
        case "cameraModel":
            return t("camera_model");
        case "date":
            return t("date");
        case "noLocation":
        case "location":
        case "city":
            return t("location");
        case "clip":
            return t("magic");
        case "person":
            return t("people");
        case "sidebarAction":
            return t("settings");
    }
};
