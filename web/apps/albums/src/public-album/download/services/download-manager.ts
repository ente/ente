import {
    getPublicAlbumsCredentials,
    requirePublicAlbumsCredentials,
    setPublicAlbumsCredentials,
} from "@/public-album/data/auth/public-link-credentials";
import {
    playableVideoURL,
    renderableImageBlob,
} from "@/public-album/media/processing/convert";
import { fetchPublicCollectionFile } from "ente-base/file-download";
import {
    authenticatedPublicAlbumsRequestHeaders,
    retryEnsuringHTTPOk,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { customAPIOrigin } from "ente-base/origins";
import {
    createDownloadManager,
    type FileDownloadOpts,
    type RenderableSourceURLs,
} from "ente-gallery/services/download-core";
import type { EnteFile } from "ente-media/file";

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

    logout() {
        setPublicAlbumsCredentials(undefined);
        this.core.logout();
    }

    setPublicAlbumsCredentials(
        credentials: PublicAlbumsCredentials | undefined,
    ) {
        setPublicAlbumsCredentials(credentials);
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
        return publicAlbums_downloadThumbnail(
            file,
            requirePublicAlbumsCredentials(this.publicAlbumsCredentials),
        );
    }

    private async downloadFile(file: EnteFile) {
        return publicAlbums_downloadFile(
            file,
            requirePublicAlbumsCredentials(this.publicAlbumsCredentials),
        );
    }
}

export const downloadManager = new DownloadManager();

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
