import type { PrintBinding } from "./printProducts";

const worker =
    process.env.NEXT_PUBLIC_PHOTOBOOK_UPLOAD_ORIGIN ??
    "https://photobook-orders.ente.com";
export interface UploadedBook {
    id: string;
    token: string;
}

export class UploadSessionExpiredError extends Error {}

export interface DeliveryDestination {
    countryCode: string;
    postalCode: string;
}

export async function checkDelivery(
    binding: PrintBinding,
    pages: number,
    destination: DeliveryDestination,
) {
    const response = await send(
        "/checkout",
        "",
        {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                cover: binding.toLowerCase(),
                pages,
                destination,
            }),
        },
        { acceptedStatus: 422 },
    );
    return response.ok;
}

const partSize = 16 * 1024 * 1024;
interface UploadPart {
    partNumber: number;
    etag: string;
}

async function send(
    path: string,
    token: string,
    init: RequestInit,
    {
        retry,
        acceptedStatus,
    }: { retry?: boolean; acceptedStatus?: number } = {},
): Promise<Response> {
    const headers = new Headers(init.headers);
    if (token) headers.set("X-Upload-Token", token);
    for (let attempt = 1; ; attempt++) {
        let response: Response | undefined;
        try {
            response = await fetch(worker + path, {
                ...init,
                credentials: "omit",
                redirect: "error",
                referrerPolicy: "no-referrer",
                headers,
            });
        } catch {
            if (!retry || attempt === 3)
                throw new Error("Could not reach checkout. Please try again.");
        }
        if (response && (response.ok || response.status === acceptedStatus))
            return response;
        if (
            response &&
            (!retry ||
                attempt === 3 ||
                (response.status < 500 && response.status !== 429))
        ) {
            const detail = response.headers
                .get("Content-Type")
                ?.startsWith("text/plain")
                ? await response.text()
                : "";
            if (token && response.status === 403)
                throw new UploadSessionExpiredError(
                    "Upload session expired. Click Checkout to try again.",
                );
            throw new Error(
                detail || `Checkout returned HTTP ${response.status}.`,
            );
        }
        await new Promise((resolve) => setTimeout(resolve, attempt * 1000));
    }
}

export async function uploadBook(
    pdf: Blob,
    book: { binding: PrintBinding; pages: number; title: string },
    onProgress: (percent: number) => void,
): Promise<UploadedBook> {
    const response = await send("/uploads", "", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            cover: book.binding.toLowerCase(),
            pages: book.pages,
            title: book.title,
            bytes: pdf.size,
        }),
    });
    const { id, uploadId, token } = (await response.json()) as {
        id: string;
        uploadId: string;
        token: string;
    };
    const path = `/uploads/${encodeURIComponent(id)}?uploadId=${encodeURIComponent(uploadId)}`;
    try {
        const parts: UploadPart[] = [];
        for (let offset = 0; offset < pdf.size; offset += partSize) {
            const end = Math.min(offset + partSize, pdf.size);
            const part = await send(
                `${path}&part=${parts.length + 1}`,
                token,
                { method: "PUT", body: pdf.slice(offset, end) },
                { retry: true },
            );
            parts.push((await part.json()) as UploadPart);
            onProgress(Math.min(99, Math.floor((100 * end) / pdf.size)));
        }
        const complete = await send(
            path,
            token,
            { method: "POST", body: JSON.stringify(parts) },
            { retry: true },
        );
        const stored = (await complete.json()) as { bytes: number };
        if (stored.bytes !== pdf.size)
            throw new Error(
                "The uploaded PDF is incomplete. Please try again.",
            );
        onProgress(100);
        return { id, token };
    } catch (error) {
        await send(path, token, { method: "DELETE" }).catch(() => undefined);
        throw error;
    }
}

export async function createCheckout(
    { id, token }: UploadedBook,
    destination: DeliveryDestination,
) {
    const response = await send(
        `/uploads/${encodeURIComponent(id)}/checkout`,
        token,
        {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(destination),
        },
    );
    const { checkout } = (await response.json()) as { checkout: string };
    return checkout;
}
