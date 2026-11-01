import type { AlbumFilter } from "@/utils/album-filters";
import { PseudoCollectionID } from "ente-new/photos/services/collection-summary";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { showCollectionSummaryWithAuthentication } from "../helpers";
import type {
    GalleryNavigationState,
    NavigationAction,
} from "../navigation-state";
import type { GalleryState } from "../reducer";
import type { useGalleryLibrary } from "./use-gallery-library";
import type { useGalleryPreferences } from "./use-gallery-preferences";

export const useAlbumActions = ({
    library,
    navigation,
    send,
    preferences,
    authenticateUser,
    remoteFilesPull,
}: {
    library: GalleryState;
    navigation: GalleryNavigationState;
    send: React.Dispatch<NavigationAction>;
    preferences: ReturnType<typeof useGalleryPreferences>;
    authenticateUser: () => Promise<boolean>;
    remoteFilesPull: ReturnType<typeof useGalleryLibrary>["remoteFilesPull"];
}) => {
    const lastAuthentication = useRef(0);
    const currentLibrary = useRef(library);
    useEffect(() => {
        currentLibrary.current = library;
    }, [library]);
    const {
        setAlbumOpenedFromOverview,
        setAlbumFilter,
        setAlbumSearchQuery,
        albumOpenedFromOverview,
        albumSearchQuery,
    } = preferences;
    const showSummary = useCallback(
        (collectionSummaryID: number | undefined) => {
            setAlbumOpenedFromOverview(undefined);
            if (collectionSummaryID === PseudoCollectionID.trash)
                void remoteFilesPull();
            send({
                type: "showCollectionSummary",
                collectionSummaryID,
                library: currentLibrary.current,
            });
        },
        [remoteFilesPull, send, setAlbumOpenedFromOverview],
    );
    const showCollectionSummary = useCallback(
        (id: number | undefined, hidden?: boolean) =>
            showCollectionSummaryWithAuthentication(
                id,
                !!hidden &&
                    navigation.destination.albumMode !== "hidden-albums",
                lastAuthentication,
                authenticateUser,
                showSummary,
            ),
        [authenticateUser, navigation.destination.albumMode, showSummary],
    );
    const goHome = useCallback(
        () => showSummary(PseudoCollectionID.all),
        [showSummary],
    );
    const selectCollection = useCallback(
        (id: number) => {
            if (navigation.destination.section === "links")
                send({ type: "selectLink", collectionID: id });
            else showSummary(id);
        },
        [navigation.destination.section, send, showSummary],
    );
    const selectCollectionFromViewer = useCallback(
        (id: number) =>
            send({
                type: "showCollectionSummary",
                collectionSummaryID: id,
                library: currentLibrary.current,
            }),
        [send],
    );
    const showAlbumOverview = useCallback(
        (filter: AlbumFilter) => {
            setAlbumFilter(filter);
            send({ type: "showAlbumOverview", albumFilter: filter });
        },
        [send, setAlbumFilter],
    );
    const backToAlbums = useCallback(() => {
        const origin =
            albumOpenedFromOverview?.collectionID ===
            navigation.destination.collectionID
                ? albumOpenedFromOverview
                : undefined;
        setAlbumSearchQuery(origin?.searchQuery ?? "");
        showAlbumOverview(origin?.filter ?? "ente");
    }, [
        albumOpenedFromOverview,
        navigation.destination.collectionID,
        setAlbumSearchQuery,
        showAlbumOverview,
    ]);
    const openOverviewAlbum = useCallback(
        (collectionID: number) => {
            showSummary(collectionID);
            setAlbumOpenedFromOverview({
                collectionID,
                filter: navigation.destination.albumFilter!,
                searchQuery: albumSearchQuery,
            });
        },
        [
            albumSearchQuery,
            navigation.destination.albumFilter,
            setAlbumOpenedFromOverview,
            showSummary,
        ],
    );
    return useMemo(
        () => ({
            showCollectionSummary,
            goHome,
            selectCollection,
            selectCollectionFromViewer,
            showAlbumOverview,
            backToAlbums,
            openOverviewAlbum,
        }),
        [
            showCollectionSummary,
            goHome,
            selectCollection,
            selectCollectionFromViewer,
            showAlbumOverview,
            backToAlbums,
            openOverviewAlbum,
        ],
    );
};
