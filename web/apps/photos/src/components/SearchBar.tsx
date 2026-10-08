import { sidebarSearchOptionsForString } from "@/services/search/sidebar-search-registry";
import { Search01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
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
    Divider,
    IconButton,
    Stack,
    styled,
    Tooltip,
    Typography,
    useTheme,
    type Theme,
} from "@mui/material";
import { EnteLogo, EnteLogoBox } from "ente-base/components/EnteLogo";
import type { ButtonishProps } from "ente-base/components/mui";
import { FocusVisibleButton } from "ente-base/components/mui/FocusVisibleButton";
import { useIsSmallWidth } from "ente-base/components/utils/hooks";
import {
    hlsGenerationStatusSnapshot,
    isHLSGenerationSupported,
} from "ente-gallery/services/video";
import { SearchPeopleList } from "ente-new/photos/components/PeopleList";
import { ItemCard, PreviewItemTile } from "ente-new/photos/components/Tiles";
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
    const shortcut =
        typeof navigator !== "undefined" && /mac/i.test(navigator.userAgent)
            ? "⌘K"
            : "Ctrl+K";

    const showSearch = () => setOpen(true);
    const closeSearch = () => setOpen(false);

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
            <Box sx={{ flex: 1 }}>
                {isSmallWidth && (
                    <EnteLogoBox sx={{ mx: "auto", pl: "24px" }}>
                        <EnteLogo height={15} />
                    </EnteLogoBox>
                )}
            </Box>
            <Tooltip title={t("search_shortcut", { shortcut })}>
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
            <Dialog
                open={open}
                onClose={closeSearch}
                keepMounted
                fullWidth
                maxWidth={false}
                aria-label={t("search")}
                slotProps={{
                    backdrop: { sx: { backgroundColor: "rgba(0,0,0,0.4)" } },
                    paper: {
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
                <SearchInput {...props} open={open} onClose={closeSearch} />
            </Dialog>
        </>
    );
};

const SearchInput: React.FC<
    SearchBarProps & { open: boolean; onClose: () => void }
> = ({
    isInSearchMode,
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
    const [isFocused, setIsFocused] = useState(false);

    const theme = useTheme();

    const styles = useMemo(() => createSelectStyles(theme), [theme]);
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
            onClose();
        }
    };

    const handleInputChange = (value: string, actionMeta: InputActionMeta) => {
        if (actionMeta.action == "input-change") {
            setInputValue(value);

            if (value === "") {
                setValue(null);
                setInputValue("");
                onSelectSearchOption(undefined, {
                    shouldExitSearchMode: false,
                });
            }
        }
    };

    const resetSearch = () => {
        selectRef.current?.blur();

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
        setIsFocused(true);
        // Refocusing needs an input nudge to reopen unchanged suggestions.
        if (inputValue) {
            selectRef.current?.onInputChange(inputValue, {
                action: "set-value",
                prevInputValue: "",
            });
        }
    };

    const handleBlur = () => {
        setIsFocused(false);
    };

    const handleKeyDown = (event: React.KeyboardEvent) => {
        if (event.key === "Escape") {
            selectRef.current?.blur();
            onClose();
        }
    };

    return (
        <SearchInputWrapper>
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
                    isFocused && (inputValue !== "" || shouldShowEmptyState(""))
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

            {isInSearchMode && (
                <IconButton onClick={resetSearch}>
                    <CloseIcon />
                </IconButton>
            )}
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
        backgroundColor: theme.vars.palette.background.elevatedPaper,
    }),
    option: (style, { isFocused }) => ({
        ...style,
        padding: 0,
        backgroundColor: "transparent !important",
        "& :hover": { cursor: "pointer" },
        "& .option-contents": isFocused
            ? { backgroundColor: theme.vars.palette.fill.fainter }
            : {},
        "&:last-child .MuiDivider-root": { display: "none" },
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
    const isMac =
        typeof navigator !== "undefined" &&
        navigator.userAgent.toUpperCase().includes("MAC");
    const shortcutKey = isMac ? "⌘ K" : "Ctrl + K";

    const hasValue =
        props.getValue().length > 0 || props.selectProps.inputValue;

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
                {!hasValue && (
                    <Box
                        sx={{
                            display: ["none", "none", "inline-flex"],
                            alignItems: "center",
                            pr: "8px",
                            color: "text.faint",
                            fontSize: "12px",
                            fontFamily: "monospace",
                            border: "1px solid",
                            borderColor: "stroke.faint",
                            borderRadius: "4px",
                            px: "6px",
                            py: "2px",
                            mr: "8px",
                        }}
                    >
                        {shortcutKey}
                    </Box>
                )}
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
        <Divider sx={{ mx: 2, my: 1 }} />
    </SelectComponents.Option>
);

const OptionContents = ({ data: option }: { data: SearchOption }) => {
    if (option.suggestion.type === "sidebarAction") {
        return (
            <Stack
                className="option-contents"
                sx={{ gap: "4px", px: 2, py: 1 }}
            >
                <Typography variant="mini" sx={{ color: "text.muted" }}>
                    {labelForOption(option)}
                </Typography>
                <Typography
                    sx={{
                        color: "text.base",
                        fontWeight: "medium",
                        wordBreak: "break-word",
                    }}
                >
                    {option.suggestion.label}
                </Typography>
                <Typography sx={{ color: "text.muted" }}>
                    {option.suggestion.path.join(" > ")}
                </Typography>
            </Stack>
        );
    }
    return (
        <Stack className="option-contents" sx={{ gap: "4px", px: 2, py: 1 }}>
            <Typography variant="mini" sx={{ color: "text.muted" }}>
                {labelForOption(option)}
            </Typography>
            <Stack
                direction="row"
                sx={{
                    gap: 1,
                    alignItems: "center",
                    justifyContent: "space-between",
                }}
            >
                <Box>
                    <Typography
                        sx={{
                            color: "text.base",
                            fontWeight: "medium",
                            wordBreak: "break-word",
                        }}
                    >
                        {option.suggestion.label}
                    </Typography>
                    <Typography sx={{ color: "text.muted" }}>
                        {t("photos_count", { count: option.fileCount })}
                    </Typography>
                </Box>

                <Stack direction="row" sx={{ gap: 1 }}>
                    {option.previewFiles.map((file) => (
                        <ItemCard
                            key={file.id}
                            coverFile={file}
                            TileComponent={PreviewItemTile}
                        />
                    ))}
                </Stack>
            </Stack>
        </Stack>
    );
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
