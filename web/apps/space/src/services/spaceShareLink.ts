const openEvent = "ente-space-open-share-link";

export type SpaceShareLinkDialogMode = "invite" | "profile";

export const openSpaceShareLinkDialog = (
    mode: SpaceShareLinkDialogMode = "profile",
) => {
    window.dispatchEvent(
        new CustomEvent<SpaceShareLinkDialogMode>(openEvent, { detail: mode }),
    );
};

export const onOpenSpaceShareLinkDialog = (
    listener: (mode: SpaceShareLinkDialogMode) => void,
) => {
    const handleOpen = (event: Event) =>
        listener((event as CustomEvent<SpaceShareLinkDialogMode>).detail);

    window.addEventListener(openEvent, handleOpen);
    return () => window.removeEventListener(openEvent, handleOpen);
};
