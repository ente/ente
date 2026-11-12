import { AuthenticateUser } from "@/components/AuthenticateUser";
import { CollectionSelector } from "@/components/CollectionSelector";
import { DesktopWhatsNew } from "@/components/DesktopWhatsNew";
import { PhotosToastStackPortal } from "@/components/PhotosToastStack";
import { QuickLinkCreatedNotification } from "@/components/QuickLinkCreatedNotification";
import { Upload } from "@/components/Upload";
import { PeopleConsentDialog } from "@/components/gallery";
import { useGalleryAuthentication } from "@/components/gallery/hooks/use-gallery-authentication";
import { useGalleryLibrary } from "@/components/gallery/hooks/use-gallery-library";
import { useGalleryOperations } from "@/components/gallery/hooks/use-gallery-operations";
import { GalleryDownloadNotifications } from "@/components/gallery/media/GalleryDownloadNotifications";
import { PhotosNavigationContext } from "@/components/gallery/navigation/PhotosNavigationContext";
import { PhotosNavigationShell } from "@/components/gallery/navigation/PhotosNavigationShell";
import { useGalleryNavigation } from "@/components/gallery/navigation/use-gallery-navigation";
import { sectionDefinition } from "@/components/gallery/sections/registry";
import { SingleInputDialog } from "ente-base/components/SingleInputDialog";
import { TranslucentLoadingOverlay } from "ente-base/components/loaders";
import { FullScreenDropZone } from "ente-gallery/components/FullScreenDropZone";
import { useMemo } from "react";

const Page: React.FC = () => {
    const libraryOwner = useGalleryLibrary();
    const { state, isFirstLoad, searchIndexRevision, remotePullRevision } =
        libraryOwner;
    const { authenticateUser, authenticateUserDialogProps } =
        useGalleryAuthentication();
    const navigation = useGalleryNavigation(libraryOwner, authenticateUser);
    const {
        operations,
        dropzoneProps,
        blockingLoad,
        collectionSelectorProps,
        albumNameInputProps,
        downloadNotificationsProps,
        uploadProps,
        quickLinkNotificationProps,
    } = useGalleryOperations(
        libraryOwner,
        navigation.state,
        authenticateUserDialogProps.open,
        navigation.showSettings,
    );
    const library = useMemo(
        () => ({
            ...state,
            isFirstLoad,
            searchIndexRevision,
            remotePullRevision,
        }),
        [state, isFirstLoad, searchIndexRevision, remotePullRevision],
    );
    const { View } = sectionDefinition(navigation.sectionID);
    if (!state.user) return <div />;
    return (
        <PhotosNavigationContext.Provider value={navigation.actions}>
            <FullScreenDropZone {...dropzoneProps}>
                <PhotosNavigationShell
                    ref={navigation.navigationRef}
                    isFirstLoad={isFirstLoad}
                    navigation={navigation.state}
                    collectionNameByID={state.collectionNameByID}
                    onAuthenticateUser={authenticateUser}
                    onUpload={operations.onUpload}
                >
                    {(presentation) => (
                        <View
                            library={library}
                            operations={operations}
                            navigation={{
                                ...navigation.state,
                                retainPeople: navigation.retainPeople,
                            }}
                            preferences={navigation.preferences}
                            presentation={presentation}
                        />
                    )}
                </PhotosNavigationShell>
                {blockingLoad && <TranslucentLoadingOverlay />}
                <CollectionSelector {...collectionSelectorProps} />
                <SingleInputDialog {...albumNameInputProps} />
                <PhotosToastStackPortal>
                    {uploadProps && <Upload {...uploadProps} />}
                    <GalleryDownloadNotifications
                        {...downloadNotificationsProps}
                    />
                    <QuickLinkCreatedNotification
                        {...quickLinkNotificationProps}
                    />
                </PhotosToastStackPortal>
                <DesktopWhatsNew />
                <PeopleConsentDialog {...navigation.peopleConsentDialogProps} />
                <AuthenticateUser {...authenticateUserDialogProps} />
            </FullScreenDropZone>
        </PhotosNavigationContext.Provider>
    );
};
export default Page;
