const pageTitles: Record<string, string> = {
    "/login": "Login",
    "/signup": "Create account",
    "/verify": "Verify email",
    "/two-factor/verify": "Two-factor verification",
    "/passkeys/verify": "Verify passkey",
    "/passkeys/finish": "Complete verification",
    "/create-profile": "Create profile",
    "/add-profile-photo": "Add profile photo",
    "/app": "Home",
    "/app/friends": "Friends",
    "/app/messages": "Messages",
    "/app/messages/[spaceId]": "Conversation",
    "/app/post": "Create post",
    "/app/posts/[spaceId]/[postId]": "Post",
    "/app/profile": "Your profile",
    "/app/profile/photo": "Profile photo",
    "/app/profile/cover": "Cover photo",
    "/app/profile/photo-edit": "Edit profile photo",
    "/app/profile/cover-edit": "Edit cover photo",
    "/app/settings": "Settings",
    "/app/settings/profile/name": "Change name",
};

export const spacePageTitle = (pathname: string) => {
    const title = pageTitles[pathname];
    return title ? `${title} · Ente Space` : "Ente Space";
};
