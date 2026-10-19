// TODO: Move this code back into gallery.tsx.

import { FaceConsent } from "@/components/sidebar/preferences/MLSettings";
import { useWrapAsyncOperation } from "@/components/utils/use-wrap-async";
import CheckIcon from "@mui/icons-material/Check";
import CloseIcon from "@mui/icons-material/Close";
import SortIcon from "@mui/icons-material/Sort";
import {
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    Menu,
    Stack,
    Tooltip,
    Typography,
} from "@mui/material";
import { CenteredFill, SpacedRow } from "ente-base/components/containers";
import { OverflowMenuOption } from "ente-base/components/OverflowMenu";
import {
    v2CloseButtonSx,
    v2HeaderRowSx,
    v2PaperSx,
    v2TitleSx,
} from "ente-base/components/SingleInput.styles";
import type { ModalVisibilityProps } from "ente-base/components/utils/modal";
import { useModalVisibility } from "ente-base/components/utils/modal";
import {
    GalleryItemsHeaderAdapter,
    GalleryItemsSummary,
} from "ente-new/photos/components/gallery/ListHeader";
import { useMLStatusSnapshot } from "ente-new/photos/components/utils/use-snapshot";
import { enableML } from "ente-new/photos/services/ml";
import type { SearchSuggestion } from "ente-new/photos/services/search/types";
import { t } from "i18next";
import React, { useRef, useState } from "react";

export { GalleryEmptyState } from "./GalleryEmptyState";

export interface RemotePullOpts {
    silent?: boolean;
    source?: string;
    strict?: boolean;
}
export type SelectionContext =
    | {
          mode: "albums" | "hidden-albums" | "archive-albums";
          collectionID: number;
      }
    | { mode: "people"; personID: string };

interface SearchResultsHeaderProps {
    searchSuggestion: SearchSuggestion;
    fileCount: number;
    // undefined preserves source order; true is oldest-first; false is newest-first.
    sortAsc: boolean | undefined;
    onSortOrderChange: (asc: boolean | undefined) => void;
}

export const SearchResultsHeader: React.FC<SearchResultsHeaderProps> = ({
    searchSuggestion,
    fileCount,
    sortAsc,
    onSortOrderChange,
}) => {
    const sortButtonRef = useRef<HTMLButtonElement | null>(null);
    const { show: showSortOrderMenu, props: sortOrderMenuVisibilityProps } =
        useModalVisibility();

    const isClipSearch = searchSuggestion.type === "clip";

    const handleRelevanceClick = () => {
        onSortOrderChange(undefined);
    };

    const handleAscClick = () => {
        onSortOrderChange(true);
    };

    const handleDescClick = () => {
        onSortOrderChange(false);
    };

    return (
        <GalleryItemsHeaderAdapter>
            <Typography
                variant="h6"
                sx={{ fontWeight: "regular", color: "text.muted" }}
            >
                {t("search_results")}
            </Typography>
            <SpacedRow>
                <GalleryItemsSummary
                    name={searchSuggestion.label}
                    fileCount={fileCount}
                />
                {fileCount > 0 && (
                    <Tooltip title={t("sort_by")}>
                        <IconButton
                            ref={sortButtonRef}
                            onClick={showSortOrderMenu}
                        >
                            <SortIcon />
                        </IconButton>
                    </Tooltip>
                )}
            </SpacedRow>
            <SearchSortOrderMenu
                {...sortOrderMenuVisibilityProps}
                sortButtonRef={sortButtonRef}
                sortAsc={sortAsc}
                isClipSearch={isClipSearch}
                onRelevanceClick={handleRelevanceClick}
                onAscClick={handleAscClick}
                onDescClick={handleDescClick}
            />
        </GalleryItemsHeaderAdapter>
    );
};

interface SearchSortOrderMenuProps {
    open: boolean;
    onClose: () => void;
    sortButtonRef: React.RefObject<HTMLButtonElement | null>;
    sortAsc: boolean | undefined;
    isClipSearch: boolean;
    onRelevanceClick: () => void;
    onAscClick: () => void;
    onDescClick: () => void;
}

const SearchSortOrderMenu: React.FC<SearchSortOrderMenuProps> = ({
    open,
    onClose,
    sortButtonRef,
    sortAsc,
    isClipSearch,
    onRelevanceClick,
    onAscClick,
    onDescClick,
}) => {
    const handleRelevanceClick = () => {
        onRelevanceClick();
        onClose();
    };

    const handleAscClick = () => {
        onAscClick();
        onClose();
    };

    const handleDescClick = () => {
        onDescClick();
        onClose();
    };

    return (
        <Menu
            id="search-results-sort"
            anchorEl={sortButtonRef.current}
            open={open}
            onClose={onClose}
            slotProps={{
                list: {
                    disablePadding: true,
                    "aria-labelledby": "search-results-sort",
                },
            }}
            anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
            transformOrigin={{ vertical: "top", horizontal: "right" }}
        >
            {isClipSearch && (
                <OverflowMenuOption
                    onClick={handleRelevanceClick}
                    endIcon={sortAsc === undefined ? <CheckIcon /> : undefined}
                >
                    {t("most_relevant")}
                </OverflowMenuOption>
            )}
            <OverflowMenuOption
                onClick={handleDescClick}
                endIcon={sortAsc === false ? <CheckIcon /> : undefined}
            >
                {t("newest_first")}
            </OverflowMenuOption>
            <OverflowMenuOption
                onClick={handleAscClick}
                endIcon={sortAsc === true ? <CheckIcon /> : undefined}
            >
                {t("oldest_first")}
            </OverflowMenuOption>
        </Menu>
    );
};

export const PeopleEmptyState: React.FC = () => {
    const mlStatus = useMLStatusSnapshot();

    switch (mlStatus?.phase) {
        case "disabled":
            return null;
        case "done":
            return (
                <PeopleEmptyStateMessage>
                    {t("people_empty_too_few")}
                </PeopleEmptyStateMessage>
            );
        default:
            return (
                <PeopleEmptyStateMessage>
                    {t("syncing_wait")}
                </PeopleEmptyStateMessage>
            );
    }
};

const PeopleEmptyStateMessage: React.FC<React.PropsWithChildren> = ({
    children,
}) => (
    <CenteredFill>
        <Typography
            sx={{
                color: "text.muted",
                mx: 1,
                // Offset the hidden 86px bar and bias the message upward.
                paddingBlockEnd: "126px",
            }}
        >
            {children}
        </Typography>
    </CenteredFill>
);

export const PeopleConsentDialog: React.FC<
    ModalVisibilityProps & { onEnabled: () => void }
> = ({ open, onClose, onEnabled }) => {
    const submittingRef = useRef(false);
    const [submitting, setSubmitting] = useState(false);

    const handleClose = () => {
        if (!submittingRef.current) onClose();
    };

    const handleConsent = useWrapAsyncOperation(async () => {
        if (submittingRef.current) return;
        submittingRef.current = true;
        setSubmitting(true);
        try {
            await enableML();
            onEnabled();
            onClose();
        } finally {
            submittingRef.current = false;
            setSubmitting(false);
        }
    });

    return (
        <Dialog
            open={open}
            onClose={handleClose}
            maxWidth={false}
            slotProps={{ paper: { sx: v2PaperSx } }}
            aria-labelledby="people-consent-title"
        >
            <Stack sx={{ p: "20px", gap: "20px" }}>
                <Stack direction="row" sx={v2HeaderRowSx}>
                    <DialogTitle
                        id="people-consent-title"
                        sx={{ ...v2TitleSx, "&&": { p: 0 } }}
                    >
                        {t("ml_search")}
                    </DialogTitle>
                    <IconButton
                        aria-label={t("close")}
                        onClick={handleClose}
                        disabled={submitting}
                        sx={v2CloseButtonSx}
                    >
                        <CloseIcon sx={{ fontSize: 18 }} />
                    </IconButton>
                </Stack>
                <DialogContent sx={{ "&&": { p: 0 } }}>
                    <FaceConsent
                        onConsent={handleConsent}
                        onCancel={handleClose}
                        submitting={submitting}
                    />
                </DialogContent>
            </Stack>
        </Dialog>
    );
};
