import {
    getPublicAlbumsCredentials,
    requirePublicAlbumsCredentials,
    setPublicAlbumsCredentials,
} from "@/public-album/data/auth/public-link-credentials";
import {
    playableVideoURL,
    renderableImageBlob,
} from "@/public-album/media/processing/convert";
import {
    authenticatedPublicAlbumsRequestHeaders,
    publicRequestHeaders,
    retryEnsuringHTTPOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { customAPIOrigin } from "ente-base/origins";
import {
    NetworkDownloadError,
    createDownloadManager,
    isNetworkDownloadError,
    type FileDownloadOpts,
    type RenderableSourceURLs,
} from "ente-gallery/services/download-core";
import type { EnteFile } from "ente-media/file";

export { NetworkDownloadError, isNetworkDownloadError };
export type { FileDownloadOpts, RenderableSourceURLs };

/**
 * A class that tracks the state of in-progress downloads and conversions,
 * including caching them for subsequent retrieval if appropriate.
 *
 * External code can use it via its singleton instance, {@link downloadManager}.
 */
class DownloadManager {
    private core = createDownloadManager({
        downloadThumbnail: (file) => this.downloadThumbnail(file),
        downloadFile: (file) => this.downloadFile(file),
        renderableImageBlob,
        playableVideoURL,
    });

    get publicAlbumsCredentials() {
        return getPublicAlbumsCredentials();
    }

    /**
     * Reset the internal state of the download manager.
     */
    logout() {
        setPublicAlbumsCredentials(undefined);
        this.core.logout();
    }

    /**
     * Set the credentials that should be used for download files when we're
     * running in the context of the public albums app.
     */
    setPublicAlbumsCredentials(
        credentials: PublicAlbumsCredentials | undefined,
    ) {
        setPublicAlbumsCredentials(credentials);
    }

    /**
     * See: [Note: Tracking active file download progress in the UI]
     */
    fileDownloadProgressSubscribe(onChange: () => void) {
        return this.core.fileDownloadProgressSubscribe(onChange);
    }

    /**
     * See: [Note: Tracking active file download progress in the UI]
     */
    fileDownloadProgressSnapshot() {
        return this.core.fileDownloadProgressSnapshot();
    }

    /**
     * Resolves with an URL that points to the file's thumbnail.
     */
    renderableThumbnailURL(file: EnteFile, cachedOnly = false) {
        return this.core.renderableThumbnailURL(file, cachedOnly);
    }

    /**
     * Returns the thumbnail data for a file, downloading it if needed.
     */
    thumbnailData(file: EnteFile, cachedOnly = false) {
        return this.core.thumbnailData(file, cachedOnly);
    }

    /**
     * Return a URL (and associated metadata) that can be used to show the given
     * {@link file} within the app, converting its format (on the fly) if needed
     * (if possible).
     */
    renderableSourceURLs(file: EnteFile): Promise<RenderableSourceURLs> {
        return this.core.renderableSourceURLs(file);
    }

    /**
     * Return a blob to the file's contents, downloading it needed.
     */
    fileBlob(file: EnteFile, opts?: FileDownloadOpts) {
        return this.core.fileBlob(file, opts);
    }

    /**
     * Return an stream to the file's contents, downloading it needed.
     */
    fileStream(file: EnteFile, opts?: FileDownloadOpts) {
        return this.core.fileStream(file, opts);
    }

    private async downloadThumbnail(file: EnteFile) {
        return publicAlbums_downloadThumbnail(
            file,
            requirePublicAlbumsCredentials(this.publicAlbumsCredentials),
        );
    }

    /**
     * Download the full contents of {@link file} using the current public album
     * credentials.
     */
    private async downloadFile(file: EnteFile) {
        return publicAlbums_downloadFile(
            file,
            requirePublicAlbumsCredentials(this.publicAlbumsCredentials),
        );
    }
}

/**
 * Singleton instance of {@link DownloadManager}.
 */
export const downloadManager = new DownloadManager();

/**
 * The various publicAlbums_* functions are used for the actual downloads when
 * we're running in the context of the the public albums app.
 */
const publicAlbums_downloadThumbnail = async (
    file: EnteFile,
    credentials: PublicAlbumsCredentials,
) => {
    const customOrigin = await customAPIOrigin();

    const getThumbnail = async () => {
        if (customOrigin) {
            // See: [Note: Passing credentials for self-hosted file fetches]
            const { accessToken, accessTokenJWT } = credentials;
            const params = new URLSearchParams({
                accessToken,
                ...(accessTokenJWT && { accessTokenJWT }),
            });
            return fetch(
                `${customOrigin}/public-collection/files/preview/${file.id}?${params.toString()}`,
                { headers: publicRequestHeaders() },
            );
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
            // See: [Note: Passing credentials for self-hosted file fetches]
            const { accessToken, accessTokenJWT } = credentials;
            const params = new URLSearchParams({
                accessToken,
                ...(accessTokenJWT && { accessTokenJWT }),
            });
            return fetch(
                `${customOrigin}/public-collection/files/download/${file.id}?${params.toString()}`,
            );
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
