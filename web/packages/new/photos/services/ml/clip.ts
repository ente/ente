import type { ElectronMLWorker } from "ente-base/types/ipc";
import { savedCLIPIndexes } from "./db";
import { dotProduct } from "./math";
import type { CLIPMatches } from "./worker-types";

export const clipIndexingVersion = 1;

// Remote indexes are shared across clients.
// Keep model and preprocessing compatible.
export interface CLIPIndex {
    embedding: number[];
}

export type RemoteCLIPIndex = CLIPIndex & {
    version: number;
    client: string;
    flags: number;
};

export type LocalCLIPIndex = CLIPIndex & { fileID: number };

export const _clipMatches = async (
    searchPhrase: string,
    electron: ElectronMLWorker,
): Promise<CLIPMatches | undefined> => {
    const textEmbedding =
        await electron.computeCLIPTextEmbeddingIfAvailable(searchPhrase);
    // Undefined means the text model is still downloading.
    if (!textEmbedding) return undefined;
    const items = (await cachedOrReadCLIPIndexes()).map(
        ({ fileID, embedding }) =>
            // Both embeddings are normalized, so this is cosine similarity.
            [fileID, dotProduct(embedding, textEmbedding)] as const,
    );
    // The heuristic threshold trades recall against query-dependent false
    // positives.
    return new Map(items.filter(([, score]) => score >= 0.175));
};

let _cachedCLIPIndexes:
    { fileID: number; embedding: Float32Array }[] | undefined;

// Reusing Float32Arrays avoids conversion inside every search.
const cachedOrReadCLIPIndexes = async () =>
    (_cachedCLIPIndexes ??= (await savedCLIPIndexes()).map(
        ({ fileID, embedding }) => ({
            fileID,
            embedding: new Float32Array(embedding),
        }),
    ));

export const clearCachedCLIPIndexes = () => (_cachedCLIPIndexes = undefined);
