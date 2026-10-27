import { useCallback, useState, type SetStateAction } from "react";
import type { CommentDraft } from "utils/comments";

const emptyDraft: CommentDraft = { text: "" };

export const useCommentDraft = (viewer?: string, postId?: number) => {
    const [drafts, setDrafts] = useState<Record<string, CommentDraft>>({});
    const key = `${viewer}:${postId}`;
    const setDraft = useCallback(
        (update: SetStateAction<CommentDraft>) =>
            setDrafts((current) => ({
                ...current,
                [key]:
                    typeof update == "function"
                        ? update(current[key] ?? emptyDraft)
                        : update,
            })),
        [key],
    );
    return [drafts[key] ?? emptyDraft, setDraft] as const;
};
