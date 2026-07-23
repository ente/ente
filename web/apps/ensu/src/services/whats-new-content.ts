export interface WhatsNewEntry {
    readonly title: string;
    readonly description: string;
}

export const whatsNewVersion = 1;

export const whatsNewEntries: readonly WhatsNewEntry[] = [
    {
        title: "Meet Gemma 4, your new default",
        description:
            "Ensu now ships with Gemma 4 out of the box, giving you sharper, more capable responses without changing a thing.",
    },
    {
        title: "Image queries, way faster",
        description:
            "Under-the-hood improvements make asking Ensu about a picture feel nearly instant.",
    },
    {
        title: "Faster, smoother model downloads",
        description:
            "Getting a new model onto your machine is now dramatically quicker and more reliable.",
    },
];
