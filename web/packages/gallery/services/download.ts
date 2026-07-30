import {
    authenticatedPublicAlbumsRequestHeaders,
    authenticatedRequestHeaders,
    publicRequestHeaders,
    retryEnsuringHTTPOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiURL, customAPIOrigin } from "ente-base/origins";
import {
    authenticatedPublicMemoryRequestHeaders,
    type PublicMemoryCredentials,
} from "ente-base/public-memory";
import { ensureAuthToken } from "ente-base/token";
import type { EnteFile } from "ente-media/file";
import { playableVideoURL, renderableImageBlob } from "./convert";
import {
    NetworkDownloadError,
    createDownloadManager,
    isNetworkDownloadError,
    type FileDownloadOpts,
    type RenderableSourceURLs,
} from "./download-core";
import { hlsPlaylistDataForFile, type HLSPlaylistDataForFile } from "./video";

export { NetworkDownloadError, isNetworkDownloadError };
export type { FileDownloadOpts, RenderableSourceURLs };

/**
 * A class that tracks the state of in-progress downloads and conversions,
 * including caching them for subsequent retrieval if appropriate.
 *
 * External code can use it via its singleton instance, {@link downloadManager}.
 * The class will initialize itself on first use, however {@link logout} should
 * be called on logout to reset its internal state.
 */
class DownloadManager {
    /**
     * Credentials that should be used to download files when we're in the
     * context of the public albums app.
     */
    publicAlbumsCredentials: PublicAlbumsCredentials | undefined;
    /**
     * Credentials that should be used to download files when we're in the
     * context of the public memory share app.
     */
    publicMemoryCredentials: PublicMemoryCredentials | undefined;

    private core = createDownloadManager({
        downloadThumbnail: (file) => this.downloadThumbnail(file),
        downloadFile: (file, opts) => this.downloadFile(file, opts),
        renderableImageBlob,
        playableVideoURL,
    });

    /**
     * Reset the internal state of the download manager.
     */
    logout() {
        this.publicAlbumsCredentials = undefined;
        this.publicMemoryCredentials = undefined;
        this.core.logout();
    }

    /**
     * Set the credentials that should be used for download files when we're
     * running in the context of the public albums app.
     */
    setPublicAlbumsCredentials(
        credentials: PublicAlbumsCredentials | undefined,
    ) {
        this.publicAlbumsCredentials = credentials;
    }

    /**
     * Set the credentials that should be used for download files when we're
     * running in the context of a public memory share.
     */
    setPublicMemoryCredentials(
        credentials: PublicMemoryCredentials | undefined,
    ) {
        this.publicMemoryCredentials = credentials;
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
     * Return HLS playlist data for a file when viewing a public memory share.
     *
     * @returns HLS playlist data if available, or undefined if HLS streaming
     * is not available for this file.
     */
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

    /**
     * Download the full contents of {@link file}, automatically choosing the
     * credentials for the logged in user, public albums, or public memory share
     * depending on the current app context we are in.
     */
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

/**
 * Singleton instance of {@link DownloadManager}.
 */
export const downloadManager = new DownloadManager();

/**
 * The various photos_* functions are used for the actual downloads when
 * we're running in the context of the the photos app.
 */
const photos_downloadThumbnail = async (file: EnteFile) => {
    const customOrigin = await customAPIOrigin();

    const getThumbnail = async () => {
        if (customOrigin) {
            // See: [Note: Passing credentials for self-hosted file fetches]
            const token = await ensureAuthToken();
            const params = new URLSearchParams({ token });
            return fetch(
                `${customOrigin}/files/preview/${file.id}?${params.toString()}`,
                { headers: publicRequestHeaders() },
            );
        } else {
            return fetch(`https://thumbnails.ente.com/?fileID=${file.id}`, {
                headers: await authenticatedRequestHeaders(),
            });
        }
    };

    const res = await retryEnsuringHTTPOk(getThumbnail);
    return new Uint8Array(await res.arrayBuffer());
};

/**
 * Download the full contents of the given {@link EnteFile}.
 */
const photos_downloadFile = async (
    file: EnteFile,
    opts?: FileDownloadOpts,
): Promise<Response> => {
    const { background } = opts ?? {};

    const customOrigin = await customAPIOrigin();

    // [Note: Passing credentials for self-hosted file fetches]
    //
    // Fetching files (or thumbnails) in the default self-hosted Ente
    // configuration involves a redirection:
    //
    // 1. The browser makes a HTTP GET to a museum with credentials. Museum
    //    inspects the credentials, in this case the auth token, and if they're
    //    valid, returns a HTTP 307 redirect to the pre-signed S3 URL that to
    //    the file in the configured S3 bucket.
    //
    // 2. The browser follows the redirect to get the actual file. The URL is
    //    pre-signed, i.e. already has all credentials needed to prove to the S3
    //    object storage that it should serve this response.
    //
    // For the first step normally we'd pass the auth the token via the
    // "X-Auth-Token" HTTP header. In this case though, that would be
    // problematic because the browser preserves the request headers when it
    // follows the HTTP 307 redirect, and the "X-Auth-Token" header also gets
    // sent to the redirected S3 request made in second step.
    //
    // To avoid this, we pass the token as a query parameter. Generally this is
    // not a good idea, but in this case (a) the URL is not a user visible one
    // and (b) even if it gets logged, it'll be in the self-hosters own service.
    //
    // Note that Ente's own servers don't have these concerns because we use a
    // slightly different flow involving a proxy instead of directly connecting
    // to the S3 storage.
    //
    // 1. The web browser makes a HTTP GET request to a proxy passing it the
    //    credentials in the "X-Auth-Token".
    //
    // 2. The proxy then does both the original steps: (a). Use the credentials
    //    to get the pre-signed URL, and (b) fetch that pre-signed URL and
    //    stream back the response.
    //
    // [Note: User initiated vs background downloads of files]
    //
    // The faster proxy approach is used for interactive requests to reduce the
    // latency for the user (e.g. when the user is waiting to see a full
    // resolution file). It can be faster than a direct connection as the proxy
    // is network-nearer to the user (See: [Note: Faster uploads via workers])
    //
    // For background processing (e.g., ML indexing, HLS generation), the direct
    // S3 connection (as what'd happen when self hosting) gets used.

    const getFile = async () => {
        if (customOrigin || background) {
            const token = await ensureAuthToken();
            const url = await apiURL(`/files/download/${file.id}`, { token });
            return fetch(url, { headers: publicRequestHeaders() });
        } else {
            return fetch(`https://files.ente.com/?fileID=${file.id}`, {
                headers: await authenticatedRequestHeaders(),
            });
        }
    };

    return retryEnsuringHTTPOk(getFile);
};

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

/**
 * The various publicMemory_* functions are used for the actual downloads when
 * we're running in the context of a public memory share.
 */
const publicMemory_downloadThumbnail = async (
    file: EnteFile,
    credentials: PublicMemoryCredentials,
) => {
    const customOrigin = await customAPIOrigin();

    const getThumbnail = async () => {
        if (customOrigin) {
            // See: [Note: Passing credentials for self-hosted file fetches]
            const { accessToken } = credentials;
            const params = new URLSearchParams({ accessToken });
            return fetch(
                `${customOrigin}/public-memory/files/preview/${file.id}?${params.toString()}`,
                { headers: publicRequestHeaders() },
            );
        } else {
            return fetch(
                await apiURL(`/public-memory/files/preview/${file.id}`),
                {
                    headers:
                        authenticatedPublicMemoryRequestHeaders(credentials),
                },
            );
        }
    };

    const res = await retryEnsuringHTTPOk(getThumbnail);
    return new Uint8Array(await res.arrayBuffer());
};

const publicMemory_downloadFile = async (
    file: EnteFile,
    credentials: PublicMemoryCredentials,
) => {
    const customOrigin = await customAPIOrigin();

    const getFile = async () => {
        if (customOrigin) {
            // See: [Note: Passing credentials for self-hosted file fetches]
            const { accessToken } = credentials;
            const params = new URLSearchParams({ accessToken });
            return fetch(
                `${customOrigin}/public-memory/files/download/${file.id}?${params.toString()}`,
            );
        } else {
            return fetch(
                await apiURL(`/public-memory/files/download/${file.id}`),
                {
                    headers:
                        authenticatedPublicMemoryRequestHeaders(credentials),
                },
            );
        }
    };

    return retryEnsuringHTTPOk(getFile);
};
