import { AuthenticateUser } from "@/components/AuthenticateUser";
import { DesktopWhatsNew } from "@/components/DesktopWhatsNew";
import { PhotosNavigationContext } from "@/components/gallery/PhotosNavigationContext";
import { PhotosNavigationShell } from "@/components/gallery/PhotosNavigationShell";
import { useGalleryAuthentication } from "@/components/gallery/hooks/use-gallery-authentication";
import { useGalleryLibrary } from "@/components/gallery/hooks/use-gallery-library";
import { useGalleryNavigation } from "@/components/gallery/hooks/use-gallery-navigation";
import { useGalleryOperations } from "@/components/gallery/hooks/use-gallery-operations";
import { sectionDefinition } from "@/components/gallery/sections";
import { FullScreenDropZone } from "ente-gallery/components/FullScreenDropZone";
import { useMemo } from "react";

const Page: React.FC = () => {
    const libraryOwner = useGalleryLibrary();
    const { state, isFirstLoad, searchIndexRevision } = libraryOwner;
    const { authenticateUser, authenticateUserDialogProps } =
        useGalleryAuthentication();
    const navigation = useGalleryNavigation(libraryOwner, authenticateUser);
    const { operations, dropzoneProps, ui } = useGalleryOperations(
        libraryOwner,
        navigation.state,
        authenticateUserDialogProps.open,
        navigation.showSettings,
    );
    const library = useMemo(
        () => ({ ...state, isFirstLoad, searchIndexRevision }),
        [state, isFirstLoad, searchIndexRevision],
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
                                pendingFileNavigation: undefined,
                                retainPerson: navigation.retainPerson,
                            }}
                            preferences={navigation.preferences}
                            presentation={presentation}
                        />
                    )}
                </PhotosNavigationShell>
                {ui}
                <DesktopWhatsNew />
                {navigation.peopleConsentDialog}
                <AuthenticateUser {...authenticateUserDialogProps} />
            </FullScreenDropZone>
        </PhotosNavigationContext.Provider>
    );
};
export default Page;
