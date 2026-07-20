import { joinSpaceInvite } from "services/space";
import {
    clearPendingSpaceInvite,
    clearPendingSpaceInviteFriend,
    saveSentSpaceInviteFriend,
    savedPendingSpaceInvite,
    savedPendingSpaceInviteFriend,
} from "services/spaceInvite";

export const acceptPendingSpaceInvite = async () => {
    const pendingInvite = savedPendingSpaceInvite();
    if (!pendingInvite) return false;

    const pendingFriend = savedPendingSpaceInviteFriend() ?? {
        fullName: "",
        username: pendingInvite.spaceUsername,
    };
    const status = await joinSpaceInvite(pendingInvite);
    clearPendingSpaceInvite();
    clearPendingSpaceInviteFriend();
    if (status == "requested") saveSentSpaceInviteFriend(pendingFriend);
    return true;
};
