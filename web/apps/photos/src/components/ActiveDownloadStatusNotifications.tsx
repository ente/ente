import { DownloadStatusNotifications } from "ente-gallery/components/DownloadStatusNotifications";
import { useSaveGroups } from "ente-gallery/components/utils/save-groups";
import type { ComponentProps } from "react";

type ActiveDownloadStatusNotificationsProps = Omit<
    ComponentProps<typeof DownloadStatusNotifications>,
    "saveGroups" | "onRemoveSaveGroup"
>;

export const ActiveDownloadStatusNotifications: React.FC<
    ActiveDownloadStatusNotificationsProps
> = (props) => {
    const { saveGroups, onRemoveSaveGroup } = useSaveGroups();

    return (
        <DownloadStatusNotifications
            saveGroups={saveGroups}
            onRemoveSaveGroup={onRemoveSaveGroup}
            {...props}
        />
    );
};
