import {
    SpaceFileViewer,
    SpaceViewerPostBackdrop,
    type SpaceViewerPhoto,
} from "components/FileViewer";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import type { SpacePost } from "services/space";
import { useSpaceAppState } from "state/app-state";
import { createLoadedLocalPostPhoto } from "utils/local-post-photo";
import {
    canPreviewSpaceImageFile,
    spacePostImageErrorMessage,
    spacePostPreviewImageForFile,
    type SpaceDraftPostImage,
} from "utils/post-image";

interface PendingPostDraft {
    error?: string;
    isPreviewPending: boolean;
    photo: SpaceViewerPhoto;
}

interface SpacePostComposerProps {
    file: File;
    onClose: () => void;
    onPublish: (
        image: SpaceDraftPostImage,
        caption: string,
    ) => Promise<SpacePost>;
    profile: SetupProfile;
}

const SpacePostComposer: React.FC<SpacePostComposerProps> = ({
    file,
    onClose,
    onPublish,
    profile,
}) => {
    const publishedPreviewURLRef = React.useRef<string>(undefined);
    const displayName =
        profile.fullName.trim() || profile.username.trim() || "You";
    const [draft, setDraft] = React.useState<PendingPostDraft>(() => ({
        isPreviewPending: true,
        photo: {
            alt: `${displayName} post`,
            avatarUrl: profile.avatarUrl,
            imageUrl: "",
            name: displayName,
            timestampMs: Date.now(),
        },
    }));
    const [isDraftPostExitAnimating, setIsDraftPostExitAnimating] =
        React.useState(false);
    const [isDraftPostExiting, setIsDraftPostExiting] = React.useState(false);

    const { clearBrowserBackState } = useBrowserBackClose({
        open: true,
        onClose: () => {
            if (!isDraftPostExiting) onClose();
        },
        stateKey: "space-post-composer",
    });

    React.useEffect(() => {
        let cancelled = false;
        let previewURL: string | undefined;

        const preparePreview = async () => {
            if (canPreviewSpaceImageFile(file)) {
                return await createLoadedLocalPostPhoto({
                    avatarUrl: profile.avatarUrl,
                    file,
                    name: displayName,
                });
            }

            const preview = await spacePostPreviewImageForFile(file);
            return {
                objectUrl: preview.url,
                photo: {
                    alt: `${displayName} post`,
                    avatarUrl: profile.avatarUrl,
                    height: preview.height,
                    imageUrl: preview.url,
                    name: displayName,
                    timestampMs: Date.now(),
                    width: preview.width,
                },
            };
        };

        void preparePreview()
            .then((preview) => {
                previewURL = preview.objectUrl;
                if (cancelled) {
                    URL.revokeObjectURL(preview.objectUrl);
                    return;
                }
                setDraft({ isPreviewPending: false, photo: preview.photo });
            })
            .catch((error: unknown) => {
                log.error("Failed to prepare post preview", error);
                if (cancelled) return;
                setDraft((current) => ({
                    ...current,
                    error: spacePostImageErrorMessage(error),
                    isPreviewPending: false,
                }));
            });

        return () => {
            cancelled = true;
            if (previewURL && previewURL != publishedPreviewURLRef.current) {
                URL.revokeObjectURL(previewURL);
            }
        };
    }, [displayName, file, profile.avatarUrl]);

    return (
        <>
            <SpaceViewerPostBackdrop exiting={isDraftPostExitAnimating} />
            <SpaceFileViewer
                draftPostPreparationError={draft.error}
                isDraftPostPreviewPending={draft.isPreviewPending}
                onClose={onClose}
                onDraftPostExitAnimationStart={() =>
                    setIsDraftPostExitAnimating(true)
                }
                onDraftPostExitStart={() => setIsDraftPostExiting(true)}
                onDraftPostPublished={() => {
                    void clearBrowserBackState("back");
                }}
                onPublishDraftPost={
                    draft.isPreviewPending || draft.error
                        ? undefined
                        : (caption, edit) => {
                              publishedPreviewURLRef.current =
                                  draft.photo.imageUrl;
                              return onPublish(
                                  {
                                      cropArea: edit.cropArea,
                                      file,
                                      height: edit.height,
                                      previewUrl: draft.photo.imageUrl,
                                      rotationDegrees: edit.rotationDegrees,
                                      width: edit.width,
                                  },
                                  caption,
                              ).then(() => undefined);
                          }
                }
                photo={draft.photo}
                postActionMode="draft-post"
            />
        </>
    );
};

export const SpacePostComposerHost: React.FC = () => {
    const {
        pendingPostPhotoFile,
        profile,
        publishPost,
        setPendingPostPhotoFile,
    } = useSpaceAppState();

    if (!pendingPostPhotoFile || !profile) return null;

    return (
        <SpacePostComposer
            file={pendingPostPhotoFile}
            onClose={() => setPendingPostPhotoFile(null)}
            onPublish={publishPost}
            profile={profile}
        />
    );
};
