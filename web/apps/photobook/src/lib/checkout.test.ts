import { afterEach, expect, test, vi } from "vitest";
import { uploadBook } from "./checkout";

const book = { binding: "Layflat", pages: 24, title: "A weekend" } as const;
const upload = { id: "book-1", uploadId: "upload-1", token: "book-token" };

afterEach(() => vi.unstubAllGlobals());

test("uploads the exported bytes in order and retries only the failed part", async () => {
    const first = new Uint8Array(16 * 1024 * 1024).fill(42);
    const pdf = new Blob([first, "last page"]);
    const partNumbers: number[] = [];
    const uploaded: Blob[] = [];
    const progress: number[] = [];
    const fetch = vi.fn(async (input: string, init: RequestInit) => {
        const url = new URL(input);
        expect(new Headers(init.headers).get("X-Upload-Token")).toBe(
            url.pathname === "/uploads" ? null : upload.token,
        );
        if (url.pathname === "/uploads") {
            expect(await new Response(init.body).json()).toEqual({
                cover: "layflat",
                pages: book.pages,
                title: book.title,
                bytes: pdf.size,
            });
            return Response.json(upload);
        }
        expect(url.pathname).toBe("/uploads/book-1");
        expect(url.searchParams.get("uploadId")).toBe(upload.uploadId);
        if (init.method === "PUT") {
            const number = Number(url.searchParams.get("part"));
            partNumbers.push(number);
            if (partNumbers.length === 2)
                return new Response(null, { status: 503 });
            uploaded.push(init.body as Blob);
            return Response.json({ partNumber: number, etag: String(number) });
        }
        expect(init.method).toBe("POST");
        expect(await new Response(init.body).json()).toEqual([
            { partNumber: 1, etag: "1" },
            { partNumber: 2, etag: "2" },
        ]);
        return Response.json({ bytes: pdf.size });
    });
    vi.stubGlobal("fetch", fetch);
    expect(await uploadBook(pdf, book, (p) => progress.push(p))).toEqual({
        id: upload.id,
        token: upload.token,
    });
    expect(partNumbers).toEqual([1, 2, 2]);
    expect(
        Buffer.from(await new Blob(uploaded).arrayBuffer()).equals(
            Buffer.from(await pdf.arrayBuffer()),
        ),
    ).toBe(true);
    expect(progress.at(-1)).toBe(100);
});

test("rejects a completed upload with the wrong byte count", async () => {
    const fetch = vi
        .fn<typeof globalThis.fetch>()
        .mockResolvedValueOnce(Response.json(upload))
        .mockResolvedValueOnce(Response.json({ partNumber: 1, etag: "a" }))
        .mockResolvedValueOnce(Response.json({ bytes: 0 }))
        .mockResolvedValueOnce(new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetch);
    await expect(
        uploadBook(new Blob(["%PDF-book"]), book, vi.fn()),
    ).rejects.toThrow("incomplete");
    expect(fetch.mock.calls[3]?.[1]?.method).toBe("DELETE");
});
