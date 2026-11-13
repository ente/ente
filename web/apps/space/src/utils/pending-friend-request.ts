import {
    clearPendingSpaceInvite,
    clearPendingSpaceInviteFriend,
    clearPendingSpaceInviteIntent,
    saveSentSpaceInviteFriend,
    savedPendingSpaceInvite,
    savedPendingSpaceInviteFriend,
} from "services/invite";
import { requestFriendByUsername } from "services/space";

export const sendPendingSpaceFriendRequest = async () => {
    const pendingInvite = savedPendingSpaceInvite();
    if (!pendingInvite) return false;

    const pendingFriend = savedPendingSpaceInviteFriend() ?? {
        fullName: "",
        username: pendingInvite.spaceUsername,
    };
    const status = await requestFriendByUsername(pendingInvite);
    clearPendingSpaceInvite();
    clearPendingSpaceInviteFriend();
    clearPendingSpaceInviteIntent();
    if (status == "requested") saveSentSpaceInviteFriend(pendingFriend);
    return true;
};
