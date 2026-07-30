const pilotAccountEmails = new Set([
    "anand@ente.io",
    "anandbaburajan@gmail.com",
]);
const pilotPublicUsernames = new Set(["anand", "anandbaburajan"]);

const normalize = (value: string | undefined) =>
    value?.trim().toLowerCase() ?? "";

export const isSpaceWebPushPilotAccount = (email: string | undefined) =>
    pilotAccountEmails.has(normalize(email));

export const isSpaceWebPushPilotPublicPage = (username: string | undefined) =>
    pilotPublicUsernames.has(normalize(username));
