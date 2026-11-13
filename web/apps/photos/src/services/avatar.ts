// Collect-link uploads are owned by the user, so their marker stays neutral.
export const avatarBackgroundColorPublicCollectedFile = "#000000";

export const avatarTextColor = "#fff";

const avatarBackgroundColors = [
    "#76549A",
    "#DF7861",
    "#94B49F",
    "#87A2FB",
    "#C689C6",
    "#937DC2",
    "#325288",
    "#85B4E0",
    "#C1A3A3",
    "#E1A059",
    "#426165",
    "#6B77B2",
    "#957FEF",
    "#DD9DE2",
    "#82AB8B",
    "#9BBBE8",
    "#8FBEBE",
    "#8AC3A1",
    "#A8B0F2",
    "#B0C695",
    "#E99AAD",
    "#D18484",
    "#78B5A7",
];

export const avatarBackgroundColor = (ownerID: number) =>
    avatarBackgroundColors[ownerID % avatarBackgroundColors.length]!;
