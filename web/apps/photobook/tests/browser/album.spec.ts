import { expect, test } from "@playwright/test";
import {
    deriveKey,
    encryptBlob,
    encryptBox,
    encryptMetadataJSON,
    encryptStreamBytes,
    generateKey,
} from "ente-base/crypto/libsodium";
import JSZip from "jszip";
import { readSession } from "./session";

for (const { custom, livePhoto } of [
    { custom: false, livePhoto: false },
    { custom: true, livePhoto: false },
    { custom: false, livePhoto: true },
]) {
    test(`imports an encrypted password-protected album (${custom ? "self-hosted" : "hosted"}${livePhoto ? ", Live Photo" : ""})`, async ({
        page,
    }) => {
        const apiOrigin = custom
            ? "https://api.photobook.test"
            : "https://api.ente.com";
        const downloadOrigin = custom
            ? "https://files.photobook.test"
            : "https://public-albums.ente.com";
        const errors: string[] = [];
        page.on("pageerror", (error) => errors.push(error.message));
        await page.goto("/");
        if (custom)
            await page.evaluate(async (origin) => {
                const database = await new Promise<IDBDatabase>(
                    (resolve, reject) => {
                        const request = indexedDB.open("kv", 1);
                        request.onupgradeneeded = () => {
                            request.result.createObjectStore("kv");
                        };
                        request.onsuccess = () => resolve(request.result);
                        request.onerror = () =>
                            reject(new Error("Cannot configure test server"));
                    },
                );
                await new Promise<void>((resolve, reject) => {
                    const transaction = database.transaction("kv", "readwrite");
                    transaction.objectStore("kv").put(origin, "apiOrigin");
                    transaction.oncomplete = () => resolve();
                    transaction.onerror = () =>
                        reject(new Error("Cannot save test server"));
                });
                database.close();
            }, apiOrigin);
        const image = await page.evaluate(() => {
            const canvas = document.createElement("canvas");
            canvas.width = 64;
            canvas.height = 48;
            const context = canvas.getContext("2d")!;
            context.fillStyle = "#146a89";
            context.fillRect(0, 0, 64, 48);
            return canvas.toDataURL("image/png").split(",")[1]!;
        });
        const collectionKey = await generateKey();
        const fileKey = await generateKey();
        const box = await encryptBox(fileKey, collectionKey);
        const fileName = livePhoto ? "Live photo.heic" : "Private photo.png";
        const metadata = await encryptMetadataJSON(
            {
                title: fileName,
                fileType: livePhoto ? 2 : 0,
                creationTime: 1_700_000_000_000_000,
                modificationTime: 1_700_000_000_000_000,
            },
            fileKey,
        );
        const thumbnail = await encryptBlob(
            Buffer.from(image, "base64"),
            fileKey,
        );
        let originalBytes: Uint8Array = Buffer.from(image, "base64");
        if (livePhoto) {
            const zip = new JSZip();
            zip.file("image.png", originalBytes);
            zip.file("video.mov", Buffer.from("fixture video"));
            originalBytes = await zip.generateAsync({ type: "uint8array" });
        }
        const original = await encryptStreamBytes(originalBytes, fileKey);
        const remoteFile = {
            id: 42,
            collectionID: 1,
            ownerID: 1,
            encryptedKey: box.encryptedData,
            keyDecryptionNonce: box.nonce,
            metadata,
            thumbnail: { decryptionHeader: thumbnail.decryptionHeader },
            file: { decryptionHeader: original.decryptionHeader },
            updationTime: 1,
        };
        const salt = Buffer.alloc(16, 7).toString("base64");
        const password = "photobook test password";
        const hash = await deriveKey(password, salt, 2, 16 * 1024 * 1024);
        const publicURL = {
            url: "https://albums.ente.com/?t=fixture",
            deviceLimit: 1,
            validTill: 0,
            enableDownload: true,
            passwordEnabled: true,
            nonce: salt,
            opsLimit: 2,
            memLimit: 16 * 1024 * 1024,
        };
        let infoRequests = 0;
        let downloads = 0;
        let releaseDownload!: () => void;
        const downloadReady = new Promise<void>((resolve) => {
            releaseDownload = resolve;
        });
        await page.route(`${apiOrigin}/**`, async (route) => {
            const request = route.request();
            const headers = {
                "access-control-allow-origin": "*",
                "access-control-allow-headers": "*",
                "access-control-expose-headers": "X-Link-Device-Token",
            };
            if (request.method() === "OPTIONS") {
                await route.fulfill({ status: 204, headers });
                return;
            }
            const url = new URL(request.url());
            expect(request.headers()["x-client-package"]).toBe(
                "io.ente.photobook.web",
            );
            expect(request.url()).not.toContain(collectionKey);
            if (url.pathname === "/public-collection/info") {
                infoRequests++;
                if (
                    infoRequests > 1 &&
                    request.headers()["x-auth-link-device-token"] !==
                        "device-fixture"
                ) {
                    await route.fulfill({ status: 429, headers });
                    return;
                }
                await route.fulfill({
                    headers: {
                        ...headers,
                        ...(infoRequests === 1 && {
                            "X-Link-Device-Token": "device-fixture",
                        }),
                    },
                    json: {
                        collection: {
                            id: 1,
                            owner: { id: 1 },
                            encryptedKey: "unused",
                            type: "album",
                            name: "Fixture",
                            publicURLs: [publicURL],
                            updationTime: 1,
                        },
                        referralCode: "",
                    },
                });
            } else if (url.pathname === "/public-collection/verify-password") {
                expect(request.postDataJSON()).toEqual({ passHash: hash });
                await route.fulfill({
                    headers,
                    json: { jwtToken: "jwt-fixture" },
                });
            } else if (url.pathname === "/public-collection/diff") {
                expect(request.headers()["x-auth-access-token-jwt"]).toBe(
                    "jwt-fixture",
                );
                expect(request.headers()["x-auth-link-device-token"]).toBe(
                    "device-fixture",
                );
                await route.fulfill({
                    headers,
                    json: {
                        diff: [
                            {
                                ...remoteFile,
                                id: 43,
                                metadata: {
                                    ...metadata,
                                    encryptedData:
                                        Buffer.alloc(32).toString("base64"),
                                },
                            },
                            remoteFile,
                        ],
                        hasMore: false,
                    },
                });
            } else if (
                custom &&
                url.pathname.startsWith("/public-collection/files/")
            ) {
                const thumbnail = url.pathname.includes("/thumbnail/");
                await route.fulfill({
                    headers,
                    json: {
                        url: `${downloadOrigin}/${thumbnail ? "preview" : "download"}/?fileID=42`,
                    },
                });
            } else throw new Error(`Unexpected API request: ${url.pathname}`);
        });
        await page.route(`${downloadOrigin}/**`, async (route) => {
            const headers = {
                "access-control-allow-origin": "*",
                "access-control-allow-methods": "GET, OPTIONS",
                "access-control-allow-headers":
                    "X-Auth-Access-Token, X-Auth-Access-Token-JWT, X-Client-Package, X-Client-Version",
            };
            if (route.request().method() === "OPTIONS") {
                await route.fulfill({ status: 204, headers });
                return;
            }
            expect(
                route.request().headers()["x-auth-link-device-token"],
            ).toBeUndefined();
            if (!custom) {
                expect(route.request().headers()["x-auth-access-token"]).toBe(
                    "fixture",
                );
                expect(
                    route.request().headers()["x-auth-access-token-jwt"],
                ).toBe("jwt-fixture");
            } else {
                expect(
                    route.request().headers()["x-auth-access-token-jwt"],
                ).toBeUndefined();
            }
            const url = new URL(route.request().url());
            expect(url.searchParams.get("fileID")).toBe("42");
            const isThumbnail = url.pathname === "/preview/";
            if (!isThumbnail) {
                downloads++;
                await downloadReady;
            }
            await route.fulfill({
                headers,
                contentType: "application/octet-stream",
                body: isThumbnail
                    ? Buffer.from(thumbnail.encryptedData, "base64")
                    : Buffer.from(original.encryptedData),
            });
        });
        const key = Buffer.from(collectionKey, "base64").toString("hex");
        await page
            .getByPlaceholder("Paste an album link")
            .fill(`https://albums.ente.com/?t=fixture#${key}`);
        await page.getByRole("button", { name: "Import", exact: true }).click();
        await page.getByPlaceholder("Password", { exact: true }).fill(password);
        await page.getByRole("button", { name: "Unlock", exact: true }).click();
        await expect
            .poll(
                async () =>
                    (await readSession(page)).photos?.[0]?.originalStatus,
            )
            .toBe("pending");
        await expect.poll(() => downloads).toBe(1);
        await page.reload();
        await expect.poll(() => downloads).toBe(2);
        releaseDownload();
        await expect
            .poll(
                async () =>
                    (await readSession(page)).photos?.[0]?.originalStatus,
            )
            .toBe("ready");
        const photo = (await readSession(page)).photos![0]!;
        expect(photo.fileName).toBe(fileName);
        expect(photo.enteOriginal).toBeUndefined();
        const originalBase64 = await page.evaluate(async (id) => {
            const database = await new Promise<IDBDatabase>((resolve) => {
                const request = indexedDB.open("photobook");
                request.onsuccess = () => resolve(request.result);
            });
            try {
                const blob = await new Promise<Blob>((resolve) => {
                    const request = database
                        .transaction("photo_blobs")
                        .objectStore("photo_blobs")
                        .get(id);
                    request.onsuccess = () => resolve(request.result as Blob);
                });
                return btoa(
                    String.fromCharCode(
                        ...new Uint8Array(await blob.arrayBuffer()),
                    ),
                );
            } finally {
                database.close();
            }
        }, photo.id);
        expect(originalBase64).toBe(image);
        expect(downloads).toBe(2);
        await page.reload();
        await expect(page.locator("canvas").first()).toBeVisible();
        expect((await readSession(page)).photos![0]!.originalStatus).toBe(
            "ready",
        );
        await page.goto("/");
        await page
            .getByPlaceholder("Paste an album link")
            .fill(`https://albums.ente.com/?t=fixture#${key}`);
        await page.getByRole("button", { name: "Import", exact: true }).click();
        await expect(
            page.getByPlaceholder("Password", { exact: true }),
        ).toBeVisible();
        await page.getByPlaceholder("Password", { exact: true }).fill(password);
        await page.getByRole("button", { name: "Unlock", exact: true }).click();
        await expect.poll(() => downloads).toBe(3);
        await expect
            .poll(
                async () =>
                    (await readSession(page)).photos?.[0]?.originalStatus,
            )
            .toBe("ready");
        expect(infoRequests).toBe(2);
        expect(errors).toEqual([]);
    });
}
