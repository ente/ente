import {
    DashboardSquare01Icon,
    Link04Icon,
    Location01Icon,
    User02Icon,
} from "@hugeicons/core-free-icons";
import type { HugeiconsIcon } from "@hugeicons/react";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { isMLSupported } from "ente-new/photos/services/ml";
import { t } from "i18next";
import type { ComponentProps, ComponentType } from "react";
import { AlbumsSection } from "./AlbumsSection";
import { DuplicatesView } from "./DuplicatesView";
import { GallerySectionLayout } from "./GallerySectionLayout";
import { LargeFilesView } from "./LargeFilesView";
import { LinksSection } from "./LinksSection";
import { PeopleSection } from "./PeopleSection";
import type { PhotosNavigationActions } from "./PhotosNavigationContext";
import { PlacesSection } from "./PlacesSection";
import { SearchSection } from "./SearchSection";
import { resolveAlbumDestination } from "./album-files";
import { resolveLinksDestination } from "./link-selection";
import type {
    GalleryDestination,
    GalleryNavigationState,
} from "./navigation-state";
import { resolvePeopleDestination } from "./people-files";
import type { GalleryState } from "./reducer";
import type { GallerySectionProps } from "./section-types";

interface SectionEntry {
    navigation: GalleryNavigationState;
    mobile: boolean;
    open: () => boolean;
    openPanel: () => void;
    closeDrawer: () => void;
    togglePanel: () => void;
}
export interface GallerySectionDefinition {
    View: ComponentType<GallerySectionProps>;
    hasNavigation: boolean;
    resolve?: (
        library: GalleryState,
        destination: GalleryDestination,
    ) => GalleryDestination;
    enter?: (actions: PhotosNavigationActions) => boolean;
    rail?: {
        label: () => string;
        icon: ComponentProps<typeof HugeiconsIcon>["icon"];
        available?: () => boolean;
        select?: (entry: SectionEntry) => void;
        selected?: (
            navigation: GalleryNavigationState,
            panelOpen: boolean,
        ) => boolean;
    };
}

const albumsEntry: NonNullable<GallerySectionDefinition["enter"]> = (actions) =>
    actions.changeMode("albums");
const albumsSelection: NonNullable<
    NonNullable<GallerySectionDefinition["rail"]>["select"]
> = ({ navigation, mobile, open, openPanel, togglePanel }) => {
    const { destination, overlay } = navigation;
    const search = overlay !== undefined;
    const sameMode =
        destination.albumMode === "albums" ||
        destination.albumFilter !== undefined;
    const reopening =
        mobile &&
        (destination.albumMode === "hidden-albums" ||
            destination.albumMode === "archive-albums");
    if (
        !search &&
        destination.section === "albums" &&
        ((sameMode && destination.collectionID !== PseudoCollectionID.all) ||
            reopening)
    )
        togglePanel();
    else if (open()) openPanel();
};
const peopleEntry: NonNullable<GallerySectionDefinition["enter"]> = (actions) =>
    actions.changeMode("people");
const peopleSelection: NonNullable<
    NonNullable<GallerySectionDefinition["rail"]>["select"]
> = ({ navigation, mobile, open, closeDrawer, togglePanel, openPanel }) => {
    if (!mobile) {
        closeDrawer();
        open();
    } else if (
        !navigation.overlay &&
        navigation.destination.section === "people"
    )
        togglePanel();
    else if (open()) openPanel();
};
const linksEntry: NonNullable<GallerySectionDefinition["enter"]> = (actions) =>
    actions.changeMode("links");
const placesEntry: NonNullable<GallerySectionDefinition["enter"]> = (
    actions,
) => {
    actions.showLibraryMap();
    return true;
};
const placesSelection: NonNullable<
    NonNullable<GallerySectionDefinition["rail"]>["select"]
> = ({ open, openPanel }) => {
    open();
    openPanel();
};
const placesSelected: NonNullable<
    NonNullable<GallerySectionDefinition["rail"]>["selected"]
> = (navigation) =>
    navigation.overlay?.section !== "search" &&
    navigation.destination.section === "places";
const duplicatesView: GallerySectionDefinition["View"] = ({
    operations,
    presentation,
}) => (
    <GallerySectionLayout presentation={presentation}>
        <DuplicatesView onRemoteFilesPull={operations.onRemoteFilesPull} />
    </GallerySectionLayout>
);
const largeFilesView: GallerySectionDefinition["View"] = ({
    operations,
    presentation,
}) => (
    <GallerySectionLayout presentation={presentation}>
        <LargeFilesView onRemoteFilesPull={operations.onRemoteFilesPull} />
    </GallerySectionLayout>
);
export const gallerySections = {
    albums: {
        View: AlbumsSection,
        resolve: resolveAlbumDestination,
        hasNavigation: true,
        enter: albumsEntry,
        rail: {
            label: () => t("albums"),
            icon: DashboardSquare01Icon,
            select: albumsSelection,
        },
    },
    people: {
        View: PeopleSection,
        resolve: resolvePeopleDestination,
        hasNavigation: true,
        enter: peopleEntry,
        rail: {
            label: () => t("people"),
            icon: User02Icon,
            available: () => isMLSupported,
            select: peopleSelection,
        },
    },
    links: {
        View: LinksSection,
        resolve: resolveLinksDestination,
        hasNavigation: true,
        enter: linksEntry,
        rail: { label: () => t("links"), icon: Link04Icon },
    },
    places: {
        View: PlacesSection,
        hasNavigation: true,
        enter: placesEntry,
        rail: {
            label: () => t("map"),
            icon: Location01Icon,
            select: placesSelection,
            selected: placesSelected,
        },
    },
    search: { View: SearchSection, hasNavigation: false },
    duplicates: { hasNavigation: false, View: duplicatesView },
    "large-files": { hasNavigation: false, View: largeFilesView },
} satisfies Record<string, GallerySectionDefinition>;

export type GallerySectionID = keyof typeof gallerySections;
export const sectionDefinition = (
    id: GallerySectionID,
): GallerySectionDefinition => gallerySections[id];

export const selectRailSection = (
    definition: GallerySectionDefinition,
    id: string,
    entry: SectionEntry,
) => {
    if (definition.rail?.select) definition.rail.select(entry);
    else if (
        !entry.navigation.overlay &&
        entry.navigation.destination.section === id
    )
        entry.togglePanel();
    else if (entry.open()) entry.openPanel();
};
