import {
    SpaceFileViewer,
    SpaceViewerPostBackdrop,
    type SpaceViewerPhoto,
} from "components/FileViewer";
import {
    SpacePostPhotoEditor,
    type SpacePostPhotoEditResult,
} from "components/PostPhotoEditor";
import { SpacePostPhotoInput } from "components/PostPhotoInput";
import { SpacePostPhotoStrip } from "components/PostPhotoStrip";
import log from "ente-base/log";
import { useBrowserBackClose } from "hooks/use-browser-back-close";
import React from "react";
import type { SetupProfile } from "screens/SetupProfileScreen";
import { useSpaceAppState } from "state/app-state";
import { createLoadedLocalPostPhoto } from "utils/local-post-photo";
import {
    canPreviewSpaceImageFile,
    spacePostImageErrorMessage,
    spacePostPreviewImageForFile,
    type SpaceDraftPostImage,
    type SpacePostPhotoEdit,
} from "utils/post-image";
import { maxSpacePostPhotos, movePostPhoto } from "utils/post-photos";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

interface DraftPhoto {
    file: File;
    id: number;
    error?: string;
    photo?: SpaceViewerPhoto;
    originalPhoto?: SpaceViewerPhoto;
    edit?: SpacePostPhotoEdit;
}

let nextDraftPhotoID = 0;
const draftPhotos = (files: File[]): DraftPhoto[] =>
    files.map((file) => ({ file, id: nextDraftPhotoID++ }));

export const SpacePostComposer: React.FC<{
    files: File[];
    onClose: () => void;
    onPublish: (
        images: SpaceDraftPostImage[],
        caption: string,
    ) => Promise<void>;
    onPublished?: () => void;
    profile: SetupProfile;
}> = ({ files, onClose, onPublish, onPublished, profile }) => {
    const displayName =
        profile.fullName.trim() || profile.username.trim() || "You";
    const [drafts, setDrafts] = React.useState(() => draftPhotos(files));
    const [activeIndex, setActiveIndex] = React.useState(0);
    const [isPublishing, setIsPublishing] = React.useState(false);
    const [isExiting, setIsExiting] = React.useState(false);
    const [isEditing, setIsEditing] = React.useState(false);
    const inputRef = React.useRef<HTMLInputElement | null>(null);
    const previewURLsRef = React.useRef(new Set<string>());
    const publishedPreviewURLRef = React.useRef<string>(undefined);
    const preparingRef = React.useRef(new Set<number>());
    const draftsRef = React.useRef(drafts);
    draftsRef.current = drafts;
    const mountedRef = React.useRef(false);
    const placeholder = React.useMemo<SpaceViewerPhoto>(
        () => ({
            avatarUrl: profile.avatarUrl,
            imageUrl: "",
            postPhotoCount: 0,
            name: displayName,
            timestampMs: Date.now(),
        }),
        [displayName, profile.avatarUrl],
    );

    const { clearBrowserBackState } = useBrowserBackClose({
        open: true,
        onClose: () => {
            if (!isPublishing) onClose();
        },
        stateKey: "space-post-composer",
    });

    React.useEffect(() => {
        mountedRef.current = true;
        const urls = previewURLsRef.current;
        return () => {
            mountedRef.current = false;
            urls.forEach((url) => {
                if (url != publishedPreviewURLRef.current)
                    URL.revokeObjectURL(url);
            });
            urls.clear();
        };
    }, []);

    React.useEffect(() => {
        const isActiveDraft = (id: number) =>
            mountedRef.current &&
            draftsRef.current.some((item) => item.id == id);
        const pending = drafts.filter(
            (draft) =>
                !draft.photo &&
                !draft.error &&
                !preparingRef.current.has(draft.id),
        );
        pending.forEach((draft) => preparingRef.current.add(draft.id));
        void (async () => {
            for (const draft of pending) {
                if (!isActiveDraft(draft.id)) continue;
                try {
                    let photo: SpaceViewerPhoto;
                    if (canPreviewSpaceImageFile(draft.file)) {
                        photo = (
                            await createLoadedLocalPostPhoto({
                                avatarUrl: profile.avatarUrl,
                                file: draft.file,
                                name: displayName,
                            })
                        ).photo;
                    } else {
                        const preview = await spacePostPreviewImageForFile(
                            draft.file,
                        );
                        photo = {
                            ...placeholder,
                            imageUrl: preview.url,
                            height: preview.height,
                            width: preview.width,
                        };
                    }
                    if (!isActiveDraft(draft.id)) {
                        URL.revokeObjectURL(photo.imageUrl);
                        continue;
                    }
                    previewURLsRef.current.add(photo.imageUrl);
                    setDrafts((current) =>
                        current.map((item) =>
                            item.id == draft.id
                                ? { ...item, photo, originalPhoto: photo }
                                : item,
                        ),
                    );
                } catch (error) {
                    log.error("Failed to prepare post preview", error);
                    if (isActiveDraft(draft.id))
                        setDrafts((current) =>
                            current.map((item) =>
                                item.id == draft.id
                                    ? {
                                          ...item,
                                          error: spacePostImageErrorMessage(
                                              error,
                                          ),
                                      }
                                    : item,
                            ),
                        );
                } finally {
                    preparingRef.current.delete(draft.id);
                }
            }
        })();
    }, [displayName, drafts, placeholder, profile.avatarUrl]);

    const addPhotos = (files: File[]) => {
        setActiveIndex(drafts.length);
        setDrafts((current) => [...current, ...draftPhotos(files)]);
    };
    const removePhoto = () => {
        if (drafts.length == 1) {
            onClose();
            return;
        }
        const removed = drafts[activeIndex];
        if (!removed) return;
        for (const url of new Set([
            removed.photo?.imageUrl,
            removed.originalPhoto?.imageUrl,
        ])) {
            if (url) {
                URL.revokeObjectURL(url);
                previewURLsRef.current.delete(url);
            }
        }
        setDrafts((current) =>
            current.filter((draft) => draft.id != removed.id),
        );
        setActiveIndex(Math.max(0, Math.min(activeIndex, drafts.length - 2)));
    };
    const movePhoto = (from: number, to: number) => {
        setDrafts((current) => movePostPhoto(current, from, to));
        setActiveIndex(to);
    };
    const applyEdits = (results: SpacePostPhotoEditResult[], index: number) => {
        const nextDrafts = drafts.map((draft) => {
            const result = results.find((result) => result.id == draft.id);
            if (!result) return draft;
            if (draft.photo!.imageUrl != draft.originalPhoto!.imageUrl) {
                URL.revokeObjectURL(draft.photo!.imageUrl);
                previewURLsRef.current.delete(draft.photo!.imageUrl);
            }
            const photo = result.preview
                ? {
                      ...draft.originalPhoto!,
                      imageUrl: result.preview.url,
                      width: result.preview.width,
                      height: result.preview.height,
                  }
                : draft.originalPhoto!;
            previewURLsRef.current.add(photo.imageUrl);
            return { ...draft, edit: result.edit, photo };
        });
        setDrafts(nextDrafts);
        setActiveIndex(index);
        setIsEditing(false);
    };
    const photos = drafts.map((draft, index) => ({
        ...(draft.photo ?? placeholder),
        postPhotoIndex: index,
        postPhotoCount: drafts.length,
    }));
    const isPreparing = drafts.some((draft) => !draft.photo && !draft.error);
    const preparationError = drafts.find((draft) => draft.error)?.error;
    const controls =
        files.length > 1 ? (
            <>
                <SpacePostPhotoInput
                    inputRef={inputRef}
                    onSelect={addPhotos}
                    remaining={maxSpacePostPhotos - drafts.length}
                />
                <SpacePostPhotoStrip
                    activeIndex={activeIndex}
                    disabled={isPublishing}
                    onAdd={() => inputRef.current?.click()}
                    onMove={movePhoto}
                    onRemove={removePhoto}
                    onSelect={setActiveIndex}
                    photos={drafts.map((draft) => ({
                        id: draft.id,
                        imageUrl: draft.photo?.imageUrl,
                    }))}
                />
            </>
        ) : undefined;

    return (
        <>
            <SpaceViewerPostBackdrop exiting={isExiting} />
            <SpaceFileViewer
                draftPhotoControls={controls}
                draftPostPreparationError={preparationError}
                isDraftPostPreviewPending={isPreparing || !drafts.length}
                onClose={onClose}
                onEditDraftPhoto={() => setIsEditing(true)}
                onDraftPostExitStart={() => setIsPublishing(true)}
                onDraftPostExitAnimationStart={() => setIsExiting(true)}
                onDraftPostPublished={() => {
                    void clearBrowserBackState("back").then(onPublished);
                }}
                onPublishDraftPost={
                    preparationError || isPreparing || !drafts.length
                        ? undefined
                        : (caption) => {
                              publishedPreviewURLRef.current =
                                  drafts[0]!.photo!.imageUrl;
                              return onPublish(
                                  drafts.map((draft) => ({
                                      cropArea: draft.edit?.cropArea,
                                      file: draft.file,
                                      height: draft.photo!.height,
                                      previewUrl: draft.photo!.imageUrl,
                                      rotationDegrees:
                                          draft.edit?.rotationDegrees,
                                      width: draft.photo!.width,
                                  })),
                                  caption,
                              );
                          }
                }
                photo={photos[0] ?? placeholder}
                photos={photos.length ? photos : [placeholder]}
                photoIndex={activeIndex}
                onPhotoIndexChange={setActiveIndex}
                postActionMode="draft-post"
            />
            {isEditing && (
                <SpacePostPhotoEditor
                    initialIndex={activeIndex}
                    onClose={() => setIsEditing(false)}
                    onDone={applyEdits}
                    photos={drafts.map((draft) => ({
                        id: draft.id,
                        imageURL: draft.originalPhoto!.imageUrl,
                        previewURL: draft.photo!.imageUrl,
                        width: draft.originalPhoto!.width!,
                        height: draft.originalPhoto!.height!,
                        edit: draft.edit,
                    }))}
                />
            )}
        </>
    );
};

export const SpacePostComposerHost: React.FC = () => {
    const {
        pendingPostPhotoFiles,
        profile,
        publishPost,
        setPendingPostPhotoFiles,
    } = useSpaceAppState();
    const router = useSpaceRouter();
    if (!pendingPostPhotoFiles || !profile) return null;
    return (
        <SpacePostComposer
            files={pendingPostPhotoFiles}
            onClose={() => setPendingPostPhotoFiles(null)}
            onPublish={async (images, caption) => {
                await publishPost(images, caption);
            }}
            onPublished={() => {
                if (router.pathname != spaceRoutes.home)
                    void router.push(spaceRoutes.home);
                else window.scrollTo({ top: 0, behavior: "smooth" });
            }}
            profile={profile}
        />
    );
};
