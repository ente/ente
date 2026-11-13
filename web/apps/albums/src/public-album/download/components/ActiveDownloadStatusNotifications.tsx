import type { DownloadStatusNotificationsProps } from "ente-gallery/components/DownloadStatusNotifications";
import { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import dynamic from "next/dynamic";

const LazyDownloadStatusNotifications =
    dynamic<DownloadStatusNotificationsProps>(
        () =>
            import("ente-gallery/components/DownloadStatusNotifications").then(
                ({ DownloadStatusNotifications }) =>
                    DownloadStatusNotifications,
            ),
        { ssr: false },
    );

type ActiveDownloadStatusNotificationsProps = Omit<
    DownloadStatusNotificationsProps,
    "saveGroups" | "onRemoveSaveGroup"
>;

export const ActiveDownloadStatusNotifications: React.FC<
    ActiveDownloadStatusNotificationsProps
> = (props) => {
    const { saveGroups, onRemoveSaveGroup } = useSaveGroups();

    if (!saveGroups.length) {
        return null;
    }

    return (
        <LazyDownloadStatusNotifications
            saveGroups={saveGroups}
            onRemoveSaveGroup={onRemoveSaveGroup}
            {...props}
        />
    );
};
