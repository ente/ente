const openEvent = "ente-space-open-share-link";

export type SpaceShareLinkDialogMode = "invite" | "profile";

export const openSpaceShareLinkDialog = (
    profileLink: string,
    mode: SpaceShareLinkDialogMode = "profile",
) => {
    window.dispatchEvent(
        new CustomEvent(openEvent, { detail: { mode, profileLink } }),
    );
};

export const onOpenSpaceShareLinkDialog = (
    listener: (mode: SpaceShareLinkDialogMode, profileLink: string) => void,
) => {
    const handleOpen = (event: Event) => {
        const { mode, profileLink } = (
            event as CustomEvent<{
                mode: SpaceShareLinkDialogMode;
                profileLink: string;
            }>
        ).detail;
        listener(mode, profileLink);
    };

    window.addEventListener(openEvent, handleOpen);
    return () => window.removeEventListener(openEvent, handleOpen);
};
