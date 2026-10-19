import { expect, test } from "vitest";
import {
    fileForUpload,
    renamedUploadFileName,
    uploadQueueItemKey,
} from "../src/components/create-item/file-upload-helpers";

test("renaming preserves extension and validates filesystem names", () => {
    expect(renamedUploadFileName("scan.PDF", " Passport.pdf ")).toBe(
        "Passport.PDF",
    );
    expect(renamedUploadFileName("scan.pdf", "a/b\\c\u0000")).toBe("abc.pdf");
    for (const value of ["", " ", ".", "..", "/\\"]) {
        expect(renamedUploadFileName("scan.pdf", value)).toBeUndefined();
    }
    expect(renamedUploadFileName("scan.pdf", "é".repeat(126))).toBeUndefined();
    expect(renamedUploadFileName("scan.pdf", "a".repeat(251))).toHaveLength(
        255,
    );
    expect(renamedUploadFileName("README", "Notes")).toBe("Notes");
    expect(renamedUploadFileName(".env", "config")).toBe("config");
});

test("upload uses chosen name without changing queue identity or file data", async () => {
    const file = new File(["document"], "scan.pdf", {
        type: "application/pdf",
        lastModified: 123,
    });
    const original = {
        file,
        relativePath: "folder/scan.pdf",
        suggestedCollectionNames: ["folder"],
    };
    const renamed = { ...original, uploadName: "Passport.pdf" };
    expect(uploadQueueItemKey(renamed)).toBe(uploadQueueItemKey(original));
    const uploaded = fileForUpload(renamed);
    expect(uploaded.name).toBe("Passport.pdf");
    expect(uploaded.type).toBe(file.type);
    expect(uploaded.lastModified).toBe(123);
    expect(await uploaded.text()).toBe("document");
    expect(file.name).toBe("scan.pdf");
    expect(fileForUpload(original)).toBe(file);
});
