import type { ChatMessage } from "./store";

export const ROOT_SELECTION_KEY = "__root__";
export const STREAMING_SELECTION_KEY = "__streaming__";

export type BranchSelections = Record<string, string>;

export interface BranchSwitcher {
    selectionKey: string;
    currentIndex: number;
    total: number;
    targets: string[];
}

export interface StreamingState {
    parentMessageUuid: string;
}

export interface PathBuildResult {
    path: ChatMessage[];
    switchers: Record<string, BranchSwitcher>;
    streamingSelectedParent?: string;
}

const DEDUPE_WINDOW_US = 2_000_000;

export const buildSelectedPath = (
    messages: ChatMessage[],
    selections: BranchSelections,
    streaming?: StreamingState,
): PathBuildResult => {
    const byId = new Map(
        messages.map((message) => [message.messageUuid, message]),
    );
    const children = new Map<string | null, ChatMessage[]>();

    for (const message of messages) {
        const parent = message.parentMessageUuid ?? null;
        const list = children.get(parent) ?? [];
        list.push(message);
        children.set(parent, list);
    }

    for (const list of children.values()) {
        list.sort((a, b) => a.createdAt - b.createdAt);
    }

    const roots = dedupeSiblingDuplicates(children.get(null) ?? []);
    if (roots.length === 0) {
        return { path: [], switchers: {} };
    }

    const switchers: Record<string, BranchSwitcher> = {};

    const rootTargets = roots.map((msg) => msg.messageUuid);
    const selectedRoot =
        selectTarget(rootTargets, selections[ROOT_SELECTION_KEY]) ??
        rootTargets[rootTargets.length - 1];
    const rootMessage = selectedRoot
        ? (byId.get(selectedRoot) ?? roots[roots.length - 1])
        : roots[roots.length - 1];

    if (roots.length > 1 && rootMessage) {
        const rootIndex = rootTargets.indexOf(rootMessage.messageUuid);
        switchers[rootMessage.messageUuid] = {
            selectionKey: ROOT_SELECTION_KEY,
            currentIndex: rootIndex === -1 ? rootTargets.length - 1 : rootIndex,
            total: rootTargets.length,
            targets: rootTargets,
        };
    }

    const path: ChatMessage[] = [];
    const visited = new Set<string>();
    let current: ChatMessage | undefined = rootMessage;
    let streamingSelectedParent: string | undefined;

    while (current && !visited.has(current.messageUuid)) {
        visited.add(current.messageUuid);
        path.push(current);

        const rawKids = children.get(current.messageUuid) ?? [];
        const kids = dedupeSiblingDuplicates(rawKids);

        if (streaming?.parentMessageUuid === current.messageUuid) {
            const targets = [
                ...kids.map((msg) => msg.messageUuid),
                STREAMING_SELECTION_KEY,
            ];
            const selection = selectTarget(
                targets,
                selections[current.messageUuid],
            );
            if (!selection) {
                break;
            }
            const idx = targets.indexOf(selection);
            const switcherKey =
                selection === STREAMING_SELECTION_KEY
                    ? STREAMING_SELECTION_KEY
                    : selection;
            switchers[switcherKey] = {
                selectionKey: current.messageUuid,
                currentIndex: idx === -1 ? targets.length - 1 : idx,
                total: targets.length,
                targets,
            };
            if (selection === STREAMING_SELECTION_KEY) {
                streamingSelectedParent = current.messageUuid;
                break;
            }
            current = byId.get(selection);
            continue;
        }

        if (kids.length === 0) break;

        if (kids.length === 1) {
            current = kids[0];
            continue;
        }

        const targets = kids.map((msg) => msg.messageUuid);
        const selection = selectTarget(
            targets,
            selections[current.messageUuid],
        );
        if (!selection) {
            break;
        }
        const idx = targets.indexOf(selection);
        switchers[selection] = {
            selectionKey: current.messageUuid,
            currentIndex: idx === -1 ? targets.length - 1 : idx,
            total: targets.length,
            targets,
        };

        current = byId.get(selection);
    }

    return { path, switchers, streamingSelectedParent };
};

const selectTarget = (targets: string[], selected?: string) => {
    if (targets.length === 0) return undefined;
    if (!selected) return targets[targets.length - 1];
    return targets.includes(selected) ? selected : targets[targets.length - 1];
};

const dedupeSiblingDuplicates = (messages: ChatMessage[]) => {
    if (messages.length <= 1) return messages;
    const output: ChatMessage[] = [];
    for (const message of messages) {
        const prev = output[output.length - 1];
        if (prev && isDuplicate(prev, message)) {
            continue;
        }
        output.push(message);
    }
    return output;
};

const isDuplicate = (a: ChatMessage, b: ChatMessage) => {
    if (a.sender !== b.sender) return false;
    if (a.text !== b.text) return false;

    const aAttachments = a.attachments ?? [];
    const bAttachments = b.attachments ?? [];
    if (aAttachments.length !== bAttachments.length) return false;

    const serialize = (attachments: ChatMessage["attachments"]) =>
        (attachments ?? [])
            .slice()
            .sort((left, right) => left.id.localeCompare(right.id))
            .map((attachment) => `${attachment.id}:${attachment.name}`)
            .join("|");

    if (serialize(aAttachments) !== serialize(bAttachments)) return false;

    return Math.abs(a.createdAt - b.createdAt) <= DEDUPE_WINDOW_US;
};
