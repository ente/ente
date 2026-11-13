import { authenticatedRequestHeaders, ensureOk } from "ente-base/http";
import { apiURL } from "ente-base/origins";
import { pullUserDetails } from "ente-new/photos/services/user-details";

const mutateFamily = async (
    path: string,
    method: "POST" | "DELETE",
    body?: object,
) => {
    ensureOk(
        await fetch(await apiURL(path), {
            method,
            headers: {
                ...(await authenticatedRequestHeaders()),
                ...(body && { "Content-Type": "application/json" }),
            },
            ...(body && { body: JSON.stringify(body) }),
        }),
    );
    return pullUserDetails();
};

export const createFamily = () => mutateFamily("/family/create", "POST");

export const inviteFamilyMember = (email: string) =>
    mutateFamily("/family/add-member", "POST", { email });

export const removeFamilyMember = (id: string) =>
    mutateFamily(`/family/remove-member/${id}`, "DELETE");

export const revokeFamilyInvite = (id: string) =>
    mutateFamily(`/family/revoke-invite/${id}`, "DELETE");

export const modifyFamilyMemberStorage = (
    id: string,
    storageLimit: number | null,
) => mutateFamily("/family/modify-storage", "POST", { id, storageLimit });
