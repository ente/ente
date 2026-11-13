import { isNamedError } from "ente-base/error";
export const isFriendRequestCanceledError = (error: unknown) =>
    isNamedError(error, "friend_request_unavailable");

export const friendRequestErrorMessage = (error: unknown, username: string) => {
    if (isNamedError(error, "profile_not_found")) {
        return `No Space profile found for @${username}.`;
    }
    if (isNamedError(error, "self_friendship")) {
        return "You can't add yourself as a friend.";
    }
    if (isNamedError(error, "friend_request_limit_reached")) {
        return `@${username} can't receive more friend requests right now.`;
    }
    if (isNamedError(error, "sent_friend_request_limit_reached")) {
        return "You have too many pending friend requests. Cancel a sent request or wait for someone to respond.";
    }
    return "Couldn't send the friend request. Please try again.";
};
