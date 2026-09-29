import {
    fetchFile,
    fetchPublicCollectionFile,
    fetchPublicMemoryFile,
} from "ente-base/file-download";
import {
    authenticatedPublicAlbumsRequestHeaders,
    authenticatedRequestHeaders,
    retryEnsuringHTTPOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { customAPIOrigin } from "ente-base/origins";
import type { PublicMemoryCredentials } from "ente-base/public-memory";
import type { EnteFile } from "ente-media/file";
import { playableVideoURL, renderableImageBlob } from "./convert";
import {
    createDownloadManager,
    isNetworkDownloadError,
    type FileDownloadOpts,
    type RenderableSourceURLs,
} from "./download-core";
import { hlsPlaylistDataForFile, type HLSPlaylistDataForFile } from "./video";

export { isNetworkDownloadError };
export type { RenderableSourceURLs };

class DownloadManager {
    publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
    publicMemoryCredentials: PublicMemoryCredentials | undefined;

    private core = createDownloadManager({
        downloadThumbnail: (file) => this.downloadThumbnail(file),
        downloadFile: (file, opts) => this.downloadFile(file, opts),
        renderableImageBlob,
        playableVideoURL,
    });

    logout() {
        this.publicAlbumsCredentials = undefined;
        this.publicMemoryCredentials = undefined;
        this.core.logout();
    }

    setPublicAlbumsCredentials(
        credentials: PublicAlbumsCredentials | undefined,
    ) {
        this.publicAlbumsCredentials = credentials;
    }

    setPublicMemoryCredentials(
        credentials: PublicMemoryCredentials | undefined,
    ) {
        this.publicMemoryCredentials = credentials;
    }

    fileDownloadProgressSubscribe(onChange: () => void) {
        return this.core.fileDownloadProgressSubscribe(onChange);
    }

    fileDownloadProgressSnapshot() {
        return this.core.fileDownloadProgressSnapshot();
    }

    renderableThumbnailURL(file: EnteFile, cachedOnly = false) {
        return this.core.renderableThumbnailURL(file, cachedOnly);
    }

    thumbnailData(file: EnteFile, cachedOnly = false) {
        return this.core.thumbnailData(file, cachedOnly);
    }

    hlsPlaylistDataForPublicMemory = async (
        file: EnteFile,
    ): Promise<HLSPlaylistDataForFile> => {
        if (!this.publicMemoryCredentials) return undefined;
        return hlsPlaylistDataForFile(
            file,
            undefined,
            this.publicMemoryCredentials,
        );
    };

    renderableSourceURLs(file: EnteFile): Promise<RenderableSourceURLs> {
        return this.core.renderableSourceURLs(file);
    }

    fileBlob(file: EnteFile, opts?: FileDownloadOpts) {
        return this.core.fileBlob(file, opts);
    }

    fileStream(file: EnteFile, opts?: FileDownloadOpts) {
        return this.core.fileStream(file, opts);
    }

    private async downloadThumbnail(file: EnteFile) {
        if (this.publicMemoryCredentials) {
            return publicMemory_downloadThumbnail(
                file,
                this.publicMemoryCredentials,
            );
        } else if (this.publicAlbumsCredentials) {
            return publicAlbums_downloadThumbnail(
                file,
                this.publicAlbumsCredentials,
            );
        } else {
            return photos_downloadThumbnail(file);
        }
    }

    private async downloadFile(file: EnteFile, opts?: FileDownloadOpts) {
        if (this.publicAlbumsCredentials) {
            return publicAlbums_downloadFile(
                file,
                this.publicAlbumsCredentials,
            );
        } else if (this.publicMemoryCredentials) {
            return publicMemory_downloadFile(
                file,
                this.publicMemoryCredentials,
            );
        } else {
            return photos_downloadFile(file, opts);
        }
    }
}

export const downloadManager = new DownloadManager();

const photos_downloadThumbnail = async (file: EnteFile) => {
    const customOrigin = await customAPIOrigin();

    const getThumbnail = async () => {
        if (customOrigin) {
            return fetchFile(file.id, "thumbnail");
        } else {
            return fetch(`https://thumbnails.ente.com/?fileID=${file.id}`, {
                headers: await authenticatedRequestHeaders(),
            });
        }
    };

    const res = await retryEnsuringHTTPOk(getThumbnail);
    return new Uint8Array(await res.arrayBuffer());
};

const photos_downloadFile = async (
    file: EnteFile,
    opts?: FileDownloadOpts,
): Promise<Response> => {
    const { background } = opts ?? {};

    const customOrigin = await customAPIOrigin();

    // Custom origins and background jobs fetch directly.
    // Interactive Ente downloads use the lower-latency proxy.
    const getFile = async () => {
        if (customOrigin || background) {
            return fetchFile(file.id, "file");
        } else {
            return fetch(`https://files.ente.com/?fileID=${file.id}`, {
                headers: await authenticatedRequestHeaders(),
            });
        }
    };

    return retryEnsuringHTTPOk(getFile);
};

const publicAlbums_downloadThumbnail = async (
    file: EnteFile,
    credentials: PublicAlbumsCredentials,
) => {
    const customOrigin = await customAPIOrigin();

    const getThumbnail = () => {
        if (customOrigin) {
            return fetchPublicCollectionFile(file.id, "thumbnail", credentials);
        } else {
            return fetch(
                `https://public-albums.ente.com/preview/?fileID=${file.id}`,
                {
                    headers:
                        authenticatedPublicAlbumsRequestHeaders(credentials),
                },
            );
        }
    };

    const res = await retryEnsuringHTTPOk(getThumbnail);
    return new Uint8Array(await res.arrayBuffer());
};

const publicAlbums_downloadFile = async (
    file: EnteFile,
    credentials: PublicAlbumsCredentials,
) => {
    const customOrigin = await customAPIOrigin();

    const getFile = () => {
        if (customOrigin) {
            return fetchPublicCollectionFile(file.id, "file", credentials);
        } else {
            return fetch(
                `https://public-albums.ente.com/download/?fileID=${file.id}`,
                {
                    headers:
                        authenticatedPublicAlbumsRequestHeaders(credentials),
                },
            );
        }
    };

    return retryEnsuringHTTPOk(getFile);
};

const publicMemory_downloadThumbnail = async (
    file: EnteFile,
    credentials: PublicMemoryCredentials,
) => {
    const getThumbnail = () =>
        fetchPublicMemoryFile(file.id, "thumbnail", credentials);

    const res = await retryEnsuringHTTPOk(getThumbnail);
    return new Uint8Array(await res.arrayBuffer());
};

const publicMemory_downloadFile = async (
    file: EnteFile,
    credentials: PublicMemoryCredentials,
) => {
    const getFile = () => fetchPublicMemoryFile(file.id, "file", credentials);

    return retryEnsuringHTTPOk(getFile);
};
