export interface CommentCountRequest {
    viewer?: string;
    id: number;
}

const counts = new Map<string, { count: number; requestId: number }>();
const listeners = new Set<() => void>();
let nextRequestId = 0;
let clearedAt = 0;

export const beginCommentCountRequest = (
    viewer?: string,
): CommentCountRequest => ({ viewer, id: ++nextRequestId });

export const cachedCommentCount = (viewer?: string, postId?: number) =>
    counts.get(`${viewer}:${postId}`)?.count;

export const subscribeToCommentCounts = (listener: () => void) => {
    listeners.add(listener);
    return () => {
        listeners.delete(listener);
    };
};

export const rememberCommentCount = (
    request: CommentCountRequest,
    postId: number,
    count: number,
) => {
    if (!request.viewer || request.id < clearedAt) return count;
    const key = `${request.viewer}:${postId}`;
    const current = counts.get(key);
    if (current && current.requestId > request.id) return current.count;
    counts.set(key, { count, requestId: request.id });
    if (current?.count != count) listeners.forEach((listener) => listener());
    return count;
};

export const clearCommentCounts = () => {
    clearedAt = ++nextRequestId;
    counts.clear();
    listeners.forEach((listener) => listener());
};
