import type { SpaceMessage } from "services/space";

export const localMessageIdPrefix = "space-local-message-";

export const reconcileMessageThread = (
    loadedMessages: SpaceMessage[],
    currentMessages: SpaceMessage[],
    confirmedDuringLoad?: ReadonlySet<string>,
): SpaceMessage[] => {
    const messages = [...loadedMessages];
    const messageIds = new Set(messages.map((message) => message.id));
    for (const message of currentMessages) {
        if (
            (!message.id.startsWith(localMessageIdPrefix) &&
                !confirmedDuringLoad?.has(message.id)) ||
            messageIds.has(message.id)
        )
            continue;
        const index = messages.findIndex(
            (candidate) => candidate.createdAtMs > message.createdAtMs,
        );
        messages.splice(index < 0 ? messages.length : index, 0, message);
        messageIds.add(message.id);
    }
    return messages;
};
