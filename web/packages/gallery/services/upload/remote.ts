import {
    authenticatedPublicAlbumsRequestHeaders,
    authenticatedRequestHeaders,
    ensureOk,
    publicRequestHeaders,
    type HTTPRequestRetrier,
    type PublicAlbumsCredentials,
} from "ente-base/http";
import { apiURL, uploaderOrigin } from "ente-base/origins";
import { RemoteEnteFile, type RemoteFileMetadata } from "ente-media/file";
import type { RemoteMagicMetadata } from "ente-media/magic-metadata";
import { nullToUndefined } from "ente-utils/transform";
import { z } from "zod";

const ObjectUploadURL = z.object({ objectKey: z.string(), url: z.string() });

export type ObjectUploadURL = z.infer<typeof ObjectUploadURL>;

const ObjectUploadURLResponse = z.object({ urls: ObjectUploadURL.array() });

export const fetchUploadURLs = async (countHint: number) => {
    const count = Math.min(50, countHint * 2);
    const res = await fetch(
        await apiURL("/files/upload-urls", { count, ts: Date.now() }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return ObjectUploadURLResponse.parse(await res.json()).urls;
};

export const fetchUploadURLWithMetadata = async ({
    contentLength,
    contentMd5,
}: {
    contentLength: number;
    contentMd5: string;
}) => {
    const headers = new Headers(await authenticatedRequestHeaders());
    headers.set("Content-Type", "application/json");
    const res = await fetch(
        await apiURL("/files/upload-url", { ts: Date.now() }),
        {
            method: "POST",
            headers,
            body: JSON.stringify({ contentLength, contentMD5: contentMd5 }),
        },
    );
    ensureOk(res);
    return ObjectUploadURL.parse(await res.json());
};

export const fetchPublicAlbumsUploadURLWithMetadata = async (
    {
        contentLength,
        contentMd5,
    }: { contentLength: number; contentMd5: string },
    credentials: PublicAlbumsCredentials,
) => {
    const headers = new Headers(
        authenticatedPublicAlbumsRequestHeaders(credentials),
    );
    headers.set("Content-Type", "application/json");
    const res = await fetch(
        await apiURL("/public-collection/upload-url", { ts: Date.now() }),
        {
            method: "POST",
            headers,
            body: JSON.stringify({ contentLength, contentMD5: contentMd5 }),
        },
    );
    ensureOk(res);
    return ObjectUploadURL.parse(await res.json());
};

export const fetchMultipartUploadURLsWithMetadata = async ({
    contentLength,
    partLength,
    partMd5s,
}: {
    contentLength: number;
    partLength: number;
    partMd5s?: string[];
}) => {
    const headers = new Headers(await authenticatedRequestHeaders());
    headers.set("Content-Type", "application/json");
    const res = await fetch(
        await apiURL("/files/multipart-upload-url", { ts: Date.now() }),
        {
            method: "POST",
            headers,
            body: JSON.stringify({ contentLength, partLength, partMd5s }),
        },
    );
    ensureOk(res);
    return MultipartUploadURLs.parse(await res.json());
};

export const fetchPublicAlbumsMultipartUploadURLsWithMetadata = async (
    {
        contentLength,
        partLength,
        partMd5s,
    }: { contentLength: number; partLength: number; partMd5s: string[] },
    credentials: PublicAlbumsCredentials,
) => {
    const headers = new Headers(
        authenticatedPublicAlbumsRequestHeaders(credentials),
    );
    headers.set("Content-Type", "application/json");
    const res = await fetch(
        await apiURL("/public-collection/multipart-upload-url", {
            ts: Date.now(),
        }),
        {
            method: "POST",
            headers,
            body: JSON.stringify({ contentLength, partLength, partMd5s }),
        },
    );
    ensureOk(res);
    return MultipartUploadURLs.parse(await res.json());
};

const MultipartUploadURLs = z.object({
    objectKey: z.string(),
    partURLs: z.string().array(),
    completeURL: z.string(),
});

type MultipartUploadURLs = z.infer<typeof MultipartUploadURLs>;

const MultipartUploadURLsResponse = z.object({ urls: MultipartUploadURLs });

export const fetchMultipartUploadURLs = async (uploadPartCount: number) => {
    const count = uploadPartCount;
    const res = await fetch(
        await apiURL("/files/multipart-upload-urls", { count, ts: Date.now() }),
        { headers: await authenticatedRequestHeaders() },
    );
    ensureOk(res);
    return MultipartUploadURLsResponse.parse(await res.json()).urls;
};

interface PutFileOptions {
    contentMd5?: string;
}

interface PutPartOptions {
    contentMd5?: string;
}

export const putFile = async (
    fileUploadURL: string,
    fileData: Uint8Array<ArrayBuffer>,
    retrier: HTTPRequestRetrier,
    options?: PutFileOptions,
) =>
    retrier(() =>
        fetch(fileUploadURL, {
            method: "PUT",
            headers: {
                ...publicRequestHeaders(),
                ...(options?.contentMd5 && {
                    "Content-MD5": options.contentMd5,
                }),
            },
            body: fileData,
        }),
    );

export const putFileViaWorker = async (
    fileUploadURL: string,
    fileData: Uint8Array<ArrayBuffer>,
    retrier: HTTPRequestRetrier,
    options?: PutFileOptions,
) =>
    retrier(async () =>
        fetch(`${await uploaderOrigin()}/file-upload`, {
            method: "PUT",
            headers: {
                ...publicRequestHeaders(),
                "UPLOAD-URL": fileUploadURL,
                ...(options?.contentMd5 && {
                    "CONTENT-MD5": options.contentMd5,
                }),
            },
            body: fileData,
        }),
    );

export const putFilePart = async (
    partUploadURL: string,
    partData: Uint8Array<ArrayBuffer>,
    retrier: HTTPRequestRetrier,
    options?: PutPartOptions,
) => {
    const res = await retrier(() =>
        fetch(partUploadURL, {
            method: "PUT",
            headers: {
                ...publicRequestHeaders(),
                ...(options?.contentMd5 && {
                    "Content-MD5": options.contentMd5,
                }),
            },
            body: partData,
        }),
    );
    return nullToUndefined(res.headers.get("etag"));
};

export const putFilePartViaWorker = async (
    partUploadURL: string,
    partData: Uint8Array<ArrayBuffer>,
    retrier: HTTPRequestRetrier,
    options?: PutPartOptions,
) => {
    const origin = await uploaderOrigin();
    const res = await retrier(() =>
        fetch(`${origin}/multipart-upload`, {
            method: "PUT",
            headers: {
                ...publicRequestHeaders(),
                "UPLOAD-URL": partUploadURL,
                ...(options?.contentMd5 && {
                    "CONTENT-MD5": options.contentMd5,
                }),
            },
            body: partData,
        }),
    );
    return z.object({ etag: z.string() }).parse(await res.json()).etag;
};

export interface MultipartCompletedPart {
    partNumber: number;
    eTag: string;
}

const createMultipartUploadRequestBody = (
    parts: MultipartCompletedPart[],
): string => {
    // S3 returns quoted ETags; interpolate them verbatim.
    const resultParts = parts.map(
        (part) =>
            `<Part><PartNumber>${part.partNumber}</PartNumber><ETag>${part.eTag}</ETag></Part>`,
    );
    return `<CompleteMultipartUpload>\n${resultParts.join("\n")}\n</CompleteMultipartUpload>`;
};

export const completeMultipartUpload = (
    completionURL: string,
    completedParts: MultipartCompletedPart[],
    retrier: HTTPRequestRetrier,
) =>
    retrier(() =>
        fetch(completionURL, {
            method: "POST",
            headers: { ...publicRequestHeaders(), "Content-Type": "text/xml" },
            body: createMultipartUploadRequestBody(completedParts),
        }),
    );

export const completeMultipartUploadViaWorker = async (
    completionURL: string,
    completedParts: MultipartCompletedPart[],
    retrier: HTTPRequestRetrier,
) =>
    retrier(async () =>
        fetch(`${await uploaderOrigin()}/multipart-complete`, {
            method: "POST",
            headers: {
                ...publicRequestHeaders(),
                "Content-Type": "text/xml",
                "UPLOAD-URL": completionURL,
            },
            body: createMultipartUploadRequestBody(completedParts),
        }),
    );

export interface PostEnteFileRequest {
    collectionID: number;
    encryptedKey: string;
    keyDecryptionNonce: string;
    file: UploadedFileObjectAttributes;
    thumbnail: UploadedFileObjectAttributes;
    metadata: RemoteFileMetadata;
    pubMagicMetadata?: RemoteMagicMetadata;
}

interface UploadedFileObjectAttributes {
    objectKey: string;
    decryptionHeader: string;
    size: number;
}

export const postEnteFile = async (
    postFileRequest: PostEnteFileRequest,
): Promise<RemoteEnteFile> => {
    const res = await fetch(await apiURL("/files"), {
        method: "POST",
        headers: await authenticatedRequestHeaders(),
        body: JSON.stringify(postFileRequest),
    });
    ensureOk(res);
    return RemoteEnteFile.parse(await res.json());
};

export const postPublicAlbumsEnteFile = async (
    postFileRequest: PostEnteFileRequest,

    credentials: PublicAlbumsCredentials,
): Promise<RemoteEnteFile> => {
    const res = await fetch(await apiURL("/public-collection/file"), {
        method: "POST",
        headers: authenticatedPublicAlbumsRequestHeaders(credentials),
        body: JSON.stringify(postFileRequest),
    });
    ensureOk(res);
    return RemoteEnteFile.parse(await res.json());
};
