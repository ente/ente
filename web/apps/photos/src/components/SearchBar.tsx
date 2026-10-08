import { sidebarTheme } from "@/components/sidebar/theme";
import { sidebarSearchOptionsForString } from "@/services/search/sidebar-search-registry";
import { Search01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import ArrowForwardIosIcon from "@mui/icons-material/ArrowForwardIos";
import CalendarIcon from "@mui/icons-material/CalendarMonth";
import CloseIcon from "@mui/icons-material/Close";
import ImageIcon from "@mui/icons-material/Image";
import NoLocationIcon from "@mui/icons-material/LocationOffOutlined";
import LocationIcon from "@mui/icons-material/LocationOn";
import CameraIcon from "@mui/icons-material/PhotoCameraOutlined";
import SettingsIcon from "@mui/icons-material/Settings";
import {
    Box,
    Dialog,
    IconButton,
    Stack,
    styled,
    ThemeProvider,
    Tooltip,
    Typography,
    useTheme,
    type Theme,
} from "@mui/material";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import {
    hlsGenerationStatusSnapshot,
    isHLSGenerationSupported,
} from "ente-gallery/services/video";
import { SearchPeopleList } from "ente-new/photos/components/PeopleList";
import { ItemCard } from "ente-new/photos/components/Tiles";
import { UnstyledButton } from "ente-new/photos/components/UnstyledButton";
import {
    useHLSGenerationStatusSnapshot,
    useMLStatusSnapshot,
    usePeopleStateSnapshot,
} from "ente-new/photos/components/utils/use-snapshot";
import {
    isMLSupported,
    mlStatusSnapshot,
    peopleStateSnapshot,
} from "ente-new/photos/services/ml";
import { searchOptionsForString } from "ente-new/photos/services/search";
import type { SearchOption } from "ente-new/photos/services/search/types";
import { nullToUndefined } from "ente-utils/transform";
import { t } from "i18next";
import pDebounce from "p-debounce";
import React, { useEffect, useMemo, useRef, useState } from "react";
import {
    components as SelectComponents,
    type ControlProps,
    type InputActionMeta,
    type InputProps,
    type OptionProps,
    type SelectInstance,
    type StylesConfig,
} from "react-select";
import AsyncSelect from "react-select/async";

export interface SearchBarProps {
    isInSearchMode: boolean;
    onSelectSearchOption: (
        o: SearchOption | undefined,
        options?: { shouldExitSearchMode?: boolean },
    ) => void;
    onSelectPeople: () => void;
    onSelectPerson: (personID: string) => void;
}

export const SearchBar: React.FC<SearchBarProps> = (props) => {
    const isSmallWidth = useIsSmallWidth();
    const [open, setOpen] = useState(false);
    const [searchResetKey, setSearchResetKey] = useState(0);
    const [previousIsInSearchMode, setPreviousIsInSearchMode] = useState(
        props.isInSearchMode,
    );

    // Reset the kept-mounted input for every path that leaves an active search.
    if (previousIsInSearchMode !== props.isInSearchMode) {
        setPreviousIsInSearchMode(props.isInSearchMode);
        if (previousIsInSearchMode) setSearchResetKey((key) => key + 1);
    }
    const shortcut =
        typeof navigator !== "undefined" && /mac/i.test(navigator.userAgent)
            ? "⌘K"
            : "Ctrl+K";

    const showSearch = () => setOpen(true);
    const closeSearch = () => setOpen(false);
    const clearSearch = () => {
        props.onSelectSearchOption(undefined, { shouldExitSearchMode: true });
        setOpen(false);
    };

    useEffect(() => {
        const handleKeyDown = (event: KeyboardEvent) => {
            if ((event.metaKey || event.ctrlKey) && event.key === "k") {
                event.preventDefault();
                setOpen(true);
            }
        };

        document.addEventListener("keydown", handleKeyDown);
        return () => document.removeEventListener("keydown", handleKeyDown);
    }, []);

    return (
        <>
            {props.isInSearchMode && (
                <Tooltip title={t("close")}>
                    <IconButton
                        aria-label={t("close")}
                        onClick={clearSearch}
                        sx={{ mr: "8px" }}
                    >
                        <CloseIcon />
                    </IconButton>
                </Tooltip>
            )}
            <Tooltip title={`Search (${shortcut})`}>
                <FocusVisibleButton
                    color="secondary"
                    aria-label={t("search")}
                    aria-haspopup="dialog"
                    onClick={showSearch}
                    sx={{
                        minWidth: 0,
                        width: isSmallWidth ? 40 : 48,
                        height: isSmallWidth ? 40 : 48,
                        p: 0,
                        mr: "8px",
                        borderRadius: "16px",
                    }}
                >
                    <HugeiconsIcon icon={Search01Icon} size={20} />
                </FocusVisibleButton>
            </Tooltip>
            <ThemeProvider theme={sidebarTheme}>
                <Dialog
                    open={open}
                    onClose={closeSearch}
                    keepMounted
                    disableRestoreFocus
                    fullWidth
                    maxWidth={false}
                    slotProps={{
                        backdrop: {
                            sx: { backgroundColor: "rgba(0,0,0,0.4)" },
                        },
                        paper: {
                            "aria-label": t("search"),
                            sx: {
                                width: "621px",
                                maxWidth: "calc(100% - 24px)",
                                m: "12px",
                                maxHeight: "calc(100dvh - 24px)",
                                p: "20px",
                                borderRadius: "20px",
                                bgcolor: "background.default",
                                backgroundImage: "none",
                                border: "1px solid",
                                borderColor: "stroke.faint",
                                boxShadow: "0 24px 60px rgba(0,0,0,.25)",
                                overflow: "auto",
                            },
                        },
                    }}
                >
                    <SearchInput
                        key={searchResetKey}
                        {...props}
                        open={open}
                        onClose={closeSearch}
                    />
                </Dialog>
            </ThemeProvider>
        </>
    );
};

const SearchInput: React.FC<
    SearchBarProps & { open: boolean; onClose: () => void }
> = ({
    onSelectSearchOption,
    onSelectPeople,
    onSelectPerson,
    open,
    onClose,
}) => {
    const selectRef = useRef<SelectInstance<SearchOption> | null>(null);
    // Subscribe even though reads happen through peopleStateSnapshot().
    usePeopleStateSnapshot();
    // undefined makes react-select switch from controlled to uncontrolled.
    const [value, setValue] = useState<SearchOption | null>(null);
    const [inputValue, setInputValue] = useState("");
    const [isKeyboardNavigating, setIsKeyboardNavigating] = useState(false);

    const theme = useTheme();

    const styles = useMemo(
        () => createSelectStyles(theme, isKeyboardNavigating),
        [theme, isKeyboardNavigating],
    );
    const components = useMemo(() => ({ Control, Input, Option }), []);

    useEffect(() => {
        if (open) selectRef.current?.focus();
        else selectRef.current?.blur();
    }, [open]);

    const handleChange = (value: SearchOption | null) => {
        const type = value?.suggestion.type;
        if (
            type == "collection" ||
            type == "person" ||
            type == "sidebarAction"
        ) {
            setValue(null);
            setInputValue("");
        } else {
            setValue(value);
            setInputValue(value?.suggestion.label ?? "");
        }

        onSelectSearchOption(nullToUndefined(value), {
            shouldExitSearchMode: true,
        });

        // blurInputOnSelect leaves react-select's menu open.
        if (value) {
            selectRef.current?.blur();
            if (
                type == "collection" ||
                type == "person" ||
                type == "sidebarAction"
            ) {
                // Clear AsyncSelect's old results after blur preserves the query.
                selectRef.current?.onInputChange("", {
                    action: "set-value",
                    prevInputValue: inputValue,
                });
            }
            onClose();
        }
    };

    const handleInputChange = (value: string, actionMeta: InputActionMeta) => {
        // AsyncSelect otherwise clears loaded options when the input blurs.
        if (
            actionMeta.action === "input-blur" ||
            actionMeta.action === "menu-close"
        ) {
            return inputValue;
        }
        if (actionMeta.action == "input-change") {
            setIsKeyboardNavigating(false);
            setInputValue(value);

            if (value === "") {
                setValue(null);
                setInputValue("");
                onSelectSearchOption(undefined, {
                    shouldExitSearchMode: false,
                });
            }
        }
        return value;
    };

    const resetSearch = () => {
        selectRef.current?.blur();
        selectRef.current?.onInputChange("", {
            action: "set-value",
            prevInputValue: inputValue,
        });

        setValue(null);
        setInputValue("");

        onSelectSearchOption(undefined, { shouldExitSearchMode: true });
        onClose();
    };

    const handleSelectPeople = () => {
        resetSearch();
        onSelectPeople();
    };

    const handleSelectPerson = (personID: string) => {
        resetSearch();
        onSelectPerson(personID);
    };

    const handleFocus = () => {
        // Refocusing needs an input nudge to reopen unchanged suggestions.
        if (inputValue) {
            selectRef.current?.onInputChange(inputValue, {
                action: "set-value",
                prevInputValue: "",
            });
        }
    };

    const handleBlur = () => {
        setIsKeyboardNavigating(false);
    };

    const handleKeyDown = (event: React.KeyboardEvent) => {
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            setIsKeyboardNavigating(true);
        }
        if (event.key === "Escape") {
            selectRef.current?.blur();
            onClose();
        }
    };

    return (
        <SearchInputWrapper onMouseMove={() => setIsKeyboardNavigating(false)}>
            <AsyncSelect
                ref={selectRef}
                value={value}
                components={components}
                styles={styles}
                loadOptions={loadOptions}
                onChange={handleChange}
                inputValue={inputValue}
                onInputChange={handleInputChange}
                onKeyDown={handleKeyDown}
                isClearable
                aria-label={t("search")}
                escapeClearsValue
                menuIsOpen={
                    open && (inputValue !== "" || shouldShowEmptyState(""))
                }
                onFocus={handleFocus}
                onBlur={handleBlur}
                placeholder={t("search_hint")}
                loadingMessage={() => null}
                noOptionsMessage={({ inputValue }) => {
                    if (inputValue) {
                        return t("no_results");
                    }
                    if (shouldShowEmptyState(inputValue)) {
                        return (
                            <EmptyState
                                onSelectPeople={handleSelectPeople}
                                onSelectPerson={handleSelectPerson}
                            />
                        );
                    }
                    return null;
                }}
            />
        </SearchInputWrapper>
    );
};

const SearchInputWrapper = styled("div")`
    display: flex;
    width: 100%;
    align-items: center;
    justify-content: center;
    gap: 8px;
    background: transparent;
    margin: auto;
`;

const loadOptions = pDebounce(async (input: string) => {
    const sidebarActions = sidebarSearchOptionsForString(input);
    const photoOptions = await searchOptionsForString(input);

    return [...photoOptions, ...sidebarActions];
}, 250);

const createSelectStyles = (
    theme: Theme,
    isKeyboardNavigating: boolean,
): StylesConfig<SearchOption, false> => ({
    container: (style) => ({ ...style, flex: 1 }),
    control: (style) => ({
        ...style,
        minHeight: "52px",
        borderRadius: "12px",
        backgroundColor: theme.vars.palette.background.paper,
        borderColor: theme.vars.palette.stroke.faint,
        boxShadow: "none",
        fontSize: "14px",
        fontWeight: 500,
        ":hover": {
            borderColor: theme.vars.palette.stroke.faint,
            cursor: "text",
        },
    }),
    input: (styles) => ({
        ...styles,
        color: theme.vars.palette.text.base,
        overflowX: "hidden",
    }),
    menu: (style) => ({
        ...style,
        position: "relative",
        top: "auto",
        marginTop: "24px",
        backgroundColor: "transparent",
        boxShadow: "none",
    }),
    menuList: (style) => ({
        ...style,
        display: "flex",
        flexDirection: "column",
        gap: "8px",
        padding: 0,
        scrollbarWidth: "thin",
        scrollbarColor: `${theme.vars.palette.stroke.muted} transparent`,
        "@supports selector(::-webkit-scrollbar)": {
            scrollbarWidth: "auto",
            scrollbarColor: "auto",
            "&::-webkit-scrollbar": { width: "4px" },
            "&::-webkit-scrollbar-track": { backgroundColor: "transparent" },
            "&::-webkit-scrollbar-thumb": {
                backgroundColor: theme.vars.palette.stroke.muted,
                borderRadius: "4px",
            },
            "&::-webkit-scrollbar-thumb:hover": {
                backgroundColor: theme.vars.palette.text.muted,
            },
            "&::-webkit-scrollbar-button": { display: "none" },
        },
    }),
    option: (style, { isFocused }) => ({
        ...style,
        padding: 0,
        backgroundColor: "transparent !important",
        "& :hover": { cursor: "pointer" },
        "& .option-contents":
            isFocused && isKeyboardNavigating
                ? {
                      outline: `2px solid ${theme.vars.palette.accent.main}`,
                      outlineOffset: "-2px",
                  }
                : {},
    }),
    placeholder: (style) => ({
        ...style,
        color: theme.vars.palette.text.muted,
        whiteSpace: "nowrap",
        overflowX: "hidden",
    }),
    dropdownIndicator: (style) => ({ ...style, display: "none" }),
    indicatorSeparator: (style) => ({ ...style, display: "none" }),
    clearIndicator: (style) => ({ ...style, display: "none" }),
});

const Control = ({ children, ...props }: ControlProps<SearchOption, false>) => {
    return (
        <SelectComponents.Control {...props}>
            <Stack direction="row" sx={{ alignItems: "center", flex: 1 }}>
                <Box
                    sx={{
                        display: "inline-flex",
                        pl: "16px",
                        color: "text.muted",
                    }}
                >
                    {iconForOption(props.getValue()[0])}
                </Box>
                {children}
            </Stack>
        </SelectComponents.Control>
    );
};

const iconForOption = (option: SearchOption | undefined) => {
    switch (option?.suggestion.type) {
        case "fileName":
            return <ImageIcon />;
        case "date":
            return <CalendarIcon />;
        case "cameraMake":
        case "cameraModel":
            return <CameraIcon />;
        case "sidebarAction":
            return <SettingsIcon />;
        case "location":
        case "city":
            return <LocationIcon />;
        case "noLocation":
            return <NoLocationIcon />;
        default:
            return <HugeiconsIcon icon={Search01Icon} />;
    }
};

const handleInputKeyDown: React.KeyboardEventHandler<HTMLInputElement> = (
    event,
) => {
    if (event.key === "Home" || event.key === "End") {
        event.stopPropagation();
    }
};

// Keep the search text visible after react-select loses focus.
const Input: React.FC<InputProps<SearchOption, false>> = (props) => (
    <SelectComponents.Input
        {...props}
        isHidden={false}
        onKeyDown={handleInputKeyDown}
    />
);

// noOptionsMessage must return null or react-select leaves an empty menu div.
const shouldShowEmptyState = (inputValue: string) => {
    if (inputValue) return false;

    if (!isMLSupported && !isHLSGenerationSupported) {
        return false;
    }

    const mlStatus = mlStatusSnapshot();
    const vpStatus = hlsGenerationStatusSnapshot();

    const isMLInactive =
        !mlStatus || mlStatus.phase == "disabled" || mlStatus.phase == "done";
    const isVideoProcessing =
        vpStatus?.enabled && vpStatus.status == "processing";

    if (isMLInactive && !isVideoProcessing) {
        const people = peopleStateSnapshot()?.visiblePeople;
        const hasPeople = people && people.length > 0;
        if (!hasPeople) {
            return false;
        }
    }

    return true;
};

const EmptyState: React.FC<
    Pick<SearchBarProps, "onSelectPeople" | "onSelectPerson">
> = ({ onSelectPeople, onSelectPerson }) => {
    const mlStatus = useMLStatusSnapshot();
    const people = usePeopleStateSnapshot()?.visiblePeople;
    const vpStatus = useHLSGenerationStatusSnapshot();

    let label: string | undefined;
    switch (mlStatus?.phase) {
        case undefined:
        case "disabled":
        case "done":
            if (vpStatus?.enabled && vpStatus.status == "processing") {
                label = t("processing_videos_status");
            }
            break;
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
    }

    const hasPeople = people && people.length > 0;
    if (!hasPeople && !label) {
        return <></>;
    }

    return (
        <Box sx={{ textAlign: "left" }}>
            {people && people.length > 0 && (
                <>
                    <SearchPeopleHeader onClick={onSelectPeople} />
                    <SearchPeopleList {...{ people, onSelectPerson }} />
                </>
            )}
            {label && (
                <Typography variant="mini" sx={{ mt: "5px", mb: "4px" }}>
                    {label}
                </Typography>
            )}
        </Box>
    );
};

const SearchPeopleHeader: React.FC<ButtonishProps> = ({ onClick }) => (
    <UnstyledButton {...{ onClick }}>
        <Typography
            sx={{ color: "text.muted", ":hover": { color: "text.base" } }}
        >
            {t("people")}
        </Typography>
    </UnstyledButton>
);

const Option: React.FC<OptionProps<SearchOption, false>> = (props) => (
    <SelectComponents.Option {...props}>
        <OptionContents data={props.data} />
    </SelectComponents.Option>
);

const OptionContents = ({ data: option }: { data: SearchOption }) => {
    const { suggestion, fileCount, previewFiles } = option;
    const person = suggestion.type === "person" ? suggestion.person : undefined;
    const hasCover = suggestion.type === "collection" || !!person;
    const coverFile = person?.displayFaceFile ?? previewFiles[0];

    return (
        <Stack
            direction="row"
            className="option-contents"
            sx={{
                minHeight: 56,
                alignItems: "center",
                gap: "12px",
                p: "8px 12px 8px 8px",
                borderRadius: "12px",
                textAlign: "left",
                color: "text.base",
                bgcolor: "background.paper",
                "&:hover": { bgcolor: "fill.fainter" },
            }}
        >
            {hasCover ? (
                <Box
                    aria-hidden
                    sx={{
                        flexShrink: 0,
                        borderRadius: person ? "50%" : "8px",
                        overflow: "hidden",
                    }}
                >
                    <ItemCard
                        key={`${coverFile?.id ?? "empty"}:${person?.displayFaceID ?? ""}`}
                        TileComponent={ResultCover}
                        coverFile={coverFile}
                        coverFaceID={person?.displayFaceID}
                    />
                </Box>
            ) : (
                <Stack
                    aria-hidden
                    sx={{
                        width: 40,
                        height: 40,
                        flexShrink: 0,
                        alignItems: "center",
                        justifyContent: "center",
                        color: "text.muted",
                        "& svg": { width: 20, height: 20 },
                    }}
                >
                    {iconForOption(option)}
                </Stack>
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
            {!hasCover && suggestion.type !== "sidebarAction" && (
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
                    {previewFiles.map((file) => (
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
        </Stack>
    );
};

const ResultCover = styled("div")({
    position: "relative",
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
            return t("location");

        case "location":
            return t("location");

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
