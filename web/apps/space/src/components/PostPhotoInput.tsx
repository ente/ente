import { Alert02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    SpaceActionToast,
    spaceToastAutoDismissDurationMs,
} from "components/ActionToast";
import React from "react";
import { spacePostImageInputAccept } from "utils/post-image";
import { maxSpacePostPhotos } from "utils/post-photos";

export const SpacePostPhotoInput: React.FC<{
    inputRef: React.Ref<HTMLInputElement>;
    onSelect: (files: File[]) => void;
    remaining?: number;
}> = ({ inputRef, onSelect, remaining = maxSpacePostPhotos }) => {
    const [error, setError] = React.useState<string>();
    return (
        <>
            <input
                ref={inputRef}
                type="file"
                accept={`${spacePostImageInputAccept},video/mp4,video/quicktime,video/webm,.mp4,.mov,.m4v,.webm`}
                multiple
                style={{ display: "none" }}
                onChange={(event) => {
                    const files = Array.from(event.target.files ?? []);
                    event.target.value = "";
                    if (!files.length) return;
                    if (files.length > remaining) {
                        setError(
                            remaining == maxSpacePostPhotos
                                ? "Only 10 photos and videos per post."
                                : `You can only add ${remaining} more ${remaining == 1 ? "item" : "items"}.`,
                        );
                        return;
                    }
                    setError(undefined);
                    onSelect(files);
                }}
            />
            {error && (
                <SpaceActionToast
                    autoDismissAfterMs={spaceToastAutoDismissDurationMs}
                    closeLabel="Dismiss post limit message"
                    icon={
                        <HugeiconsIcon
                            icon={Alert02Icon}
                            size={20}
                            color="#FFB020"
                        />
                    }
                    message={
                        <span
                            style={{
                                display: "block",
                                padding: "8px 0",
                                whiteSpace: "normal",
                            }}
                        >
                            {error}
                        </span>
                    }
                    onClose={() => setError(undefined)}
                    zIndex={1600}
                />
            )}
        </>
    );
};
