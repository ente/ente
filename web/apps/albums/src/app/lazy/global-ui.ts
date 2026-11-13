import dynamic from "next/dynamic";

export const LazyNotification = dynamic(
    () =>
        import("ente-base/components/Notification").then(
            ({ Notification }) => Notification,
        ),
    { ssr: false },
);

export const LazyAttributedMiniDialog = dynamic(
    () =>
        import("ente-base/components/MiniDialog").then(
            ({ AttributedMiniDialog }) => AttributedMiniDialog,
        ),
    { ssr: false },
);
