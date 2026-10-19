export interface WhatsNewEntry {
    readonly title: string;
    readonly description: string;
}

export const whatsNewVersion = 3;

export const whatsNewEntries: readonly WhatsNewEntry[] = [
    {
        title: "Keep the conversation going",
        description:
            "Ensu now keeps better track of the details that matter in longer chats, so you can ask follow-up questions with less need to repeat yourself.",
    },
];
