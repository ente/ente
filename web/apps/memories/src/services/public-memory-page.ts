import { isHTTPErrorWithStatus } from "ente-base/http";
import log from "ente-base/log";
import type { EnteFile } from "ente-media/file";
import { alignLaneFilesWithMetadata } from "../utils/lane";
import {
    extractAccessTokenFromURL,
    extractMemoryShareKeyFromURL,
} from "../utils/public-memory-url";
import {
    decryptMemoryShareMetadata,
    getPublicMemoryFiles,
    getPublicMemoryInfo,
    type PublicMemoryShareFrame,
    type PublicMemoryShareMetadata,
} from "./public-memory";

export type PublicMemoryViewerVariant = "share" | "lane";

interface LoadedPublicMemoryPageData {
    accessToken: string;
    files: EnteFile[];
    laneFrames?: (PublicMemoryShareFrame | undefined)[];
    memoryMetadata?: PublicMemoryShareMetadata;
    memoryName: string;
    viewerVariant: PublicMemoryViewerVariant;
}

export type LoadPublicMemoryPageResult =
    | { kind: "redirect"; redirectURL: string }
    | { kind: "error"; errorMessage: string }
    | { kind: "loaded"; data: LoadedPublicMemoryPageData };

export const loadPublicMemoryPage = async (
    currentURL: URL,
): Promise<LoadPublicMemoryPageResult> => {
    try {
        const accessToken = extractAccessTokenFromURL(currentURL);

        if (!accessToken) {
            return { kind: "redirect", redirectURL: "https://ente.com" };
        }

        const shareKey = await extractMemoryShareKeyFromURL(currentURL);
        if (!shareKey) {
            return {
                kind: "error",
                errorMessage: "Invalid memory link. Missing secret.",
            };
        }

        const info = await getPublicMemoryInfo(accessToken);

        let memoryMetadata: PublicMemoryShareMetadata | undefined;
        if (info.metadataCipher && info.metadataNonce) {
            memoryMetadata = await decryptMemoryShareMetadata(
                info.metadataCipher,
                info.metadataNonce,
                shareKey,
            );
        }

        const viewerVariant: PublicMemoryViewerVariant =
            info.type === "lane" || memoryMetadata?.kind === "lane"
                ? "lane"
                : "share";

        const publicFiles = await getPublicMemoryFiles(accessToken, shareKey);
        const isLaneShare = viewerVariant === "lane";

        if (isLaneShare && memoryMetadata?.frames.length) {
            const aligned = alignLaneFilesWithMetadata(
                publicFiles,
                memoryMetadata.frames,
            );
            return {
                kind: "loaded",
                data: {
                    accessToken,
                    files: aligned.files,
                    laneFrames: aligned.frames,
                    memoryMetadata,
                    memoryName: memoryMetadata.name,
                    viewerVariant,
                },
            };
        }

        return {
            kind: "loaded",
            data: {
                accessToken,
                files: publicFiles.map(({ file }) => file),
                laneFrames: undefined,
                memoryMetadata,
                memoryName: memoryMetadata?.name ?? "",
                viewerVariant,
            },
        };
    } catch (e) {
        if (isHTTPErrorWithStatus(e, 401) || isHTTPErrorWithStatus(e, 410)) {
            return {
                kind: "error",
                errorMessage:
                    "This memory link has expired or is no longer available.",
            };
        }
        if (isHTTPErrorWithStatus(e, 429)) {
            return {
                kind: "error",
                errorMessage: "Too many requests. Please try again later.",
            };
        }

        log.error("Failed to load public memory share", e);
        return {
            kind: "error",
            errorMessage: "Something went wrong. Please try again later.",
        };
    }
};
