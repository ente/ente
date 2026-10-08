import { spaceNavigationDestination } from "utils/navigation";
import { describe, expect, it } from "vitest";

describe("navigation destinations", () => {
    it.each([
        ["/app", "/app"],
        ["/app/notifications", "/app"],
        ["/app/settings/profile/name", "/app"],
        ["/app/post", "/app"],
        ["/app/posts/[spaceId]/[postId]", "/app"],
        ["/app/messages/[spaceId]", "/app/messages"],
        ["/app/friends", "/app/friends"],
        ["/profile-link", "/app/friends"],
        ["/app/profile/photo-edit", "/app/profile"],
        ["/login", undefined],
        ["/application", undefined],
    ])("keeps %s in its parent destination", (path, destination) => {
        expect(spaceNavigationDestination(path)).toBe(destination);
    });
});
