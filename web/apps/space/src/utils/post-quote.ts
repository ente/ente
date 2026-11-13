import { isNamedError } from "ente-base/error";
import { SpaceMediaRateLimitError } from "services/media-load";

export const postQuotePhotoIndex = (
    photos: { objectKey: string }[],
    objectKey?: string,
) =>
    objectKey === undefined
        ? photos.length
            ? 0
            : -1
        : photos.findIndex((photo) => photo.objectKey == objectKey);

export const postQuoteKey = (post: {
    spaceId: string;
    postId: number;
    objectKey?: string;
}) => JSON.stringify([post.spaceId, post.postId, post.objectKey ?? null]);

export const postQuoteErrorState = (error: unknown) =>
    isNamedError(error, "content_unavailable") ||
    isNamedError(error, "permission_denied")
        ? { isUnavailable: true }
        : error instanceof SpaceMediaRateLimitError
          ? { hasLoadError: true, retryAt: error.retryAt }
          : { hasLoadError: true };
