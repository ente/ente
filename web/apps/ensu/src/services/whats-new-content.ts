export interface WhatsNewEntry {
    readonly title: string;
    readonly description: string;
}

export const whatsNewVersion = 2;

export const whatsNewEntries: readonly WhatsNewEntry[] = [
    {
        title: "Ensu Packs",
        description:
            "Add knowledge from wikipedia and wikibooks to get more accurate answers",
    },
    {
        title: "Chat with Your Notes",
        description:
            "Add your markdown notes folder, and chat with your notes. Ask questions or discuss the thoughts you put down",
    },
];
