import { SpaceMessagesPage } from "components/MessagesPage";
import React from "react";
import { useSpaceRouter } from "utils/route-transitions";
import { friendSpaceIdFromQuery } from "utils/routes";

const messageSpaceIdFromPath = () => {
    if (typeof window == "undefined") return "";
    const match = /^\/app\/messages\/([^/?#]+)/.exec(window.location.pathname);
    if (!match?.[1]) return "";

    try {
        return decodeURIComponent(match[1]);
    } catch {
        return "";
    }
};

const Page: React.FC = () => {
    const router = useSpaceRouter();
    const spaceId =
        friendSpaceIdFromQuery(router.query.spaceId) ||
        messageSpaceIdFromPath();

    return <SpaceMessagesPage selectedSpaceId={spaceId || undefined} />;
};

export default Page;
