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
import {
    initialSpaceVideoEdit,
    isSpaceVideoFile,
    spaceVideoCover,
    spaceVideoInfo,
    startSpaceVideoExport,
    type SpacePostVideoEdit,
    type SpaceVideoExport,
} from "utils/post-video";
import { useSpaceRouter } from "utils/route-transitions";
import { spaceRoutes } from "utils/routes";

interface DraftPhoto {
    file: File;
    id: number;
    error?: string;
    photo?: SpaceViewerPhoto;
    originalPhoto?: SpaceViewerPhoto;
    edit?: SpacePostPhotoEdit;
    videoEdit?: SpacePostVideoEdit;
}

let nextDraftPhotoID = 0;
const draftPhotos = (files: File[]): DraftPhoto[] =>
    files.map((file) => ({ file, id: nextDraftPhotoID++ }));

const SpacePostComposer: React.FC<{
    files: File[];
    onClose: () => void;
    onPublish: (
        images: SpaceDraftPostImage[],
        caption: string,
    ) => Promise<void>;
    profile: SetupProfile;
}> = ({ files, onClose, onPublish, profile }) => {
    const router = useSpaceRouter();
    const displayName =
        profile.fullName.trim() || profile.username.trim() || "You";
    const [drafts, setDrafts] = React.useState(() => draftPhotos(files));
    const [activeIndex, setActiveIndex] = React.useState(0);
    const [isPublishing, setIsPublishing] = React.useState(false);
    const [isExiting, setIsExiting] = React.useState(false);
    const [editorSnapshot, setEditorSnapshot] = React.useState<{
        drafts: DraftPhoto[];
        activeIndex: number;
    }>();
    const inputRef = React.useRef<HTMLInputElement>(null);
    const previewURLsRef = React.useRef(new Set<string>());
    const publishedPreviewURLRef = React.useRef<string>(undefined);
    const preparingRef = React.useRef(new Map<number, AbortController>());
    const exportsRef = React.useRef(new Map<number, SpaceVideoExport>());
    const publishingRef = React.useRef(false);
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
            if (!isPublishing || isExiting) onClose();
        },
        stateKey: "space-post-composer",
    });

    React.useEffect(() => {
        mountedRef.current = true;
        const urls = previewURLsRef.current;
        const preparing = preparingRef.current;
        const exports = exportsRef.current;
        return () => {
            mountedRef.current = false;
            preparing.forEach((controller) => controller.abort());
            preparing.clear();
            if (!publishingRef.current) exports.forEach((job) => job.cancel());
            exports.clear();
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
        const controllers = new Map(
            pending.map((draft) => [draft.id, new AbortController()]),
        );
        controllers.forEach((controller, id) =>
            preparingRef.current.set(id, controller),
        );
        if (pending.some((draft) => isSpaceVideoFile(draft.file))) {
            void import("utils/video-encoding/web")
                .then(({ preloadVideoEncoderWeb }) => preloadVideoEncoderWeb())
                .catch((error: unknown) =>
                    log.warn("Failed to preload video encoder", error),
                );
        }
        void (async () => {
            for (const draft of pending) {
                if (!isActiveDraft(draft.id)) continue;
                const controller = controllers.get(draft.id)!;
                const { signal } = controller;
                try {
                    signal.throwIfAborted();
                    let photo: SpaceViewerPhoto;
                    let videoEdit: SpacePostVideoEdit | undefined;
                    if (isSpaceVideoFile(draft.file)) {
                        const info = await spaceVideoInfo(draft.file, signal);
                        videoEdit = initialSpaceVideoEdit(info.duration);
                        const cover = await spaceVideoCover(
                            draft.file,
                            videoEdit.coverTime,
                            signal,
                        );
                        const url = URL.createObjectURL(draft.file);
                        previewURLsRef.current.add(url);
                        photo = {
                            ...placeholder,
                            imageUrl: URL.createObjectURL(cover.file),
                            width: info.width,
                            height: info.height,
                            video: {
                                url,
                                durationMs: info.duration * 1000,
                                start: videoEdit.start,
                                end: videoEdit.end,
                                muted: videoEdit.muted,
                            },
                        };
                    } else if (canPreviewSpaceImageFile(draft.file)) {
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
                        if (photo.video?.url)
                            URL.revokeObjectURL(photo.video.url);
                        continue;
                    }
                    previewURLsRef.current.add(photo.imageUrl);
                    setDrafts((current) =>
                        current.map((item) =>
                            item.id == draft.id
                                ? {
                                      ...item,
                                      photo,
                                      originalPhoto: photo,
                                      videoEdit,
                                  }
                                : item,
                        ),
                    );
                } catch (error) {
                    if (signal.aborted) continue;
                    log.error("Failed to prepare post preview", error);
                    if (isActiveDraft(draft.id))
                        setDrafts((current) =>
                            current.map((item) =>
                                item.id == draft.id
                                    ? {
                                          ...item,
                                          error: isSpaceVideoFile(draft.file)
                                              ? "Couldn't process this video."
                                              : spacePostImageErrorMessage(
                                                    error,
                                                ),
                                      }
                                    : item,
                            ),
                        );
                } finally {
                    if (preparingRef.current.get(draft.id) == controller)
                        preparingRef.current.delete(draft.id);
                }
            }
        })();
    }, [displayName, drafts, placeholder, profile.avatarUrl]);

    React.useEffect(() => {
        if (
            publishingRef.current ||
            editorSnapshot ||
            drafts.some((draft) => !draft.photo && !draft.error)
        )
            return;
        for (const draft of drafts) {
            const edit = draft.videoEdit;
            if (!edit) continue;
            const previous = exportsRef.current.get(draft.id);
            if (
                previous?.edit.start == edit.start &&
                previous.edit.end == edit.end &&
                previous.edit.muted == edit.muted
            )
                continue;
            previous?.cancel();
            const job = startSpaceVideoExport(draft.file, edit);
            exportsRef.current.set(draft.id, job);
            void job.promise.catch((error: unknown) => {
                if (
                    !publishingRef.current &&
                    exportsRef.current.get(draft.id) == job
                )
                    exportsRef.current.delete(draft.id);
                if (!(
                    error instanceof DOMException && error.name == "AbortError"
                ))
                    log.warn("Failed to prepare draft video", error);
            });
        }
    }, [drafts, editorSnapshot]);

    const addPhotos = (files: File[]) => {
        setActiveIndex(drafts.length);
        setDrafts((current) => [...current, ...draftPhotos(files)]);
    };
    const releasePreview = (draft: DraftPhoto) => {
        preparingRef.current.get(draft.id)?.abort();
        exportsRef.current.get(draft.id)?.cancel();
        exportsRef.current.delete(draft.id);
        for (const url of new Set([
            draft.photo?.imageUrl,
            draft.originalPhoto?.imageUrl,
            draft.originalPhoto?.video?.url,
        ])) {
            if (url) {
                URL.revokeObjectURL(url);
                previewURLsRef.current.delete(url);
            }
        }
    };
    const removePhoto = () => {
        if (drafts.length == 1) {
            onClose();
            return;
        }
        const removed = drafts[activeIndex];
        if (!removed) return;
        releasePreview(removed);
        setDrafts((current) =>
            current.filter((draft) => draft.id != removed.id),
        );
        setActiveIndex(Math.max(0, Math.min(activeIndex, drafts.length - 2)));
    };
    const movePhoto = (from: number, to: number) => {
        setDrafts((current) => movePostPhoto(current, from, to));
        setActiveIndex(to);
    };
    const cancelEdits = () => {
        const snapshot = editorSnapshot!;
        for (const draft of drafts) {
            if (!snapshot.drafts.some(({ id }) => id == draft.id))
                releasePreview(draft);
        }
        setDrafts(
            drafts.filter((draft) =>
                snapshot.drafts.some(({ id }) => id == draft.id),
            ),
        );
        setActiveIndex(snapshot.activeIndex);
        setEditorSnapshot(undefined);
    };
    const applyEdits = (
        results: SpacePostPhotoEditResult[],
        index: number,
        photoIDs: number[],
    ) => {
        const nextDrafts = photoIDs.map((id) => {
            const draft = drafts.find((draft) => draft.id == id)!;
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
            const videoEdit = result.videoEdit ?? draft.videoEdit;
            if (photo.video && videoEdit)
                photo.video = {
                    ...photo.video,
                    start: videoEdit.start,
                    end: videoEdit.end,
                    muted: videoEdit.muted,
                };
            return { ...draft, edit: result.edit, videoEdit, photo };
        });
        for (const draft of drafts) {
            if (!photoIDs.includes(draft.id)) releasePreview(draft);
        }
        setDrafts(nextDrafts);
        setActiveIndex(index);
        setEditorSnapshot(undefined);
    };
    const photos = drafts.map((draft, index) => ({
        ...(draft.photo ?? placeholder),
        preparationError: draft.error,
        isVideo: isSpaceVideoFile(draft.file),
        postPhotoIndex: index,
        postPhotoCount: drafts.length,
    }));
    const isPreparing = drafts.some((draft) => !draft.photo && !draft.error);
    const preparationError = drafts.find((draft) => draft.error)?.error;
    const images = React.useMemo(
        () =>
            drafts.map((draft) => ({
                cropArea: draft.edit?.cropArea,
                file: draft.file,
                height: draft.photo?.height,
                previewUrl: draft.photo?.imageUrl ?? "",
                rotationDegrees: draft.edit?.rotationDegrees,
                width: draft.photo?.width,
                video: draft.videoEdit,
            })),
        [drafts],
    );
    const controls = drafts.length > 1 && (
        <SpacePostPhotoStrip
            activeIndex={activeIndex}
            disabled={isPublishing}
            onAdd={() => inputRef.current?.click()}
            onMove={movePhoto}
            onRemove={drafts.length > 1 ? removePhoto : undefined}
            onSelect={setActiveIndex}
            photos={drafts.map((draft) => ({
                id: draft.id,
                imageUrl: draft.photo?.imageUrl,
                isLoading: !draft.photo && !draft.error,
                hasError: Boolean(draft.error),
                isVideo: isSpaceVideoFile(draft.file),
                durationMs: draft.videoEdit
                    ? (draft.videoEdit.end - draft.videoEdit.start) * 1000
                    : undefined,
            }))}
        />
    );

    return (
        <>
            <SpacePostPhotoInput
                inputRef={inputRef}
                onSelect={addPhotos}
                remaining={maxSpacePostPhotos - drafts.length}
            />
            <SpaceViewerPostBackdrop exiting={isExiting} />
            <SpaceFileViewer
                draftPhotoControls={controls}
                isDraftPostPreviewPending={isPreparing || !drafts.length}
                onClose={() => {
                    if (!isPublishing || isExiting) onClose();
                }}
                onAddDraftPhoto={
                    drafts.length == 1
                        ? () => inputRef.current?.click()
                        : undefined
                }
                onEditDraftPhoto={() => {
                    if (isPublishing) return;
                    exportsRef.current.forEach((job) => job.cancel());
                    exportsRef.current.clear();
                    setEditorSnapshot({ drafts, activeIndex });
                }}
                onDraftPostExitStart={async () => {
                    setIsPublishing(true);
                    await clearBrowserBackState("back");
                    if (router.pathname != spaceRoutes.home)
                        await router.replace(spaceRoutes.home);
                    window.scrollTo({ top: 0, behavior: "instant" });
                }}
                onDraftPostExitAnimationStart={() => setIsExiting(true)}
                onPublishDraftPost={
                    preparationError || isPreparing || !drafts.length
                        ? undefined
                        : (caption) => {
                              publishingRef.current = true;
                              publishedPreviewURLRef.current =
                                  drafts[0]!.photo!.imageUrl;
                              return onPublish(
                                  images.map((image, index) => ({
                                      ...image,
                                      videoExport: exportsRef.current.get(
                                          drafts[index]!.id,
                                      ),
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
            {editorSnapshot && (
                <SpacePostPhotoEditor
                    initialIndex={activeIndex}
                    onAdd={addPhotos}
                    onClose={cancelEdits}
                    onDone={applyEdits}
                    photos={drafts.map((draft) => ({
                        id: draft.id,
                        imageURL: draft.originalPhoto?.imageUrl ?? "",
                        previewURL: draft.photo?.imageUrl ?? "",
                        width: draft.originalPhoto?.width ?? 0,
                        height: draft.originalPhoto?.height ?? 0,
                        isLoading: !draft.photo && !draft.error,
                        preparationError: draft.error,
                        isVideo: isSpaceVideoFile(draft.file),
                        edit: draft.edit,
                        video: draft.videoEdit
                            ? {
                                  file: draft.file,
                                  sourceURL: draft.originalPhoto!.video!.url!,
                                  duration:
                                      draft.originalPhoto!.video!.durationMs /
                                      1000,
                                  edit: draft.videoEdit,
                              }
                            : undefined,
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
    if (!pendingPostPhotoFiles || !profile) return null;
    return (
        <SpacePostComposer
            files={pendingPostPhotoFiles}
            onClose={() => setPendingPostPhotoFiles(null)}
            onPublish={async (images, caption) => {
                await publishPost(images, caption);
            }}
            profile={profile}
        />
    );
};
