import { requestFriendByUsername } from "services/space";
import {
    clearPendingSpaceInvite,
    clearPendingSpaceInviteFriend,
    clearPendingSpaceInviteIntent,
    saveSentSpaceInviteFriend,
    savedPendingSpaceInvite,
    savedPendingSpaceInviteFriend,
} from "services/spaceInvite";

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
