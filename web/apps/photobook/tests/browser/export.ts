import "@fontsource-variable/inter";
import "@fontsource-variable/outfit";
import { makeBlankPage } from "../../src/lib/bookPages";
import { savePhotoBlob } from "../../src/lib/db";
import { downloadBlob, exportPngPagesZip } from "../../src/lib/export";
import { applyVariant } from "../../src/lib/layouts";
import { DEFAULT_PRINT_SELECTION } from "../../src/lib/printProducts";

document.querySelector("#export")!.addEventListener("click", async () => {
    const status = document.querySelector("#status")!;
    status.textContent = "Exporting";
    const canvas = document.createElement("canvas");
    canvas.width = 640;
    canvas.height = 480;
    const context = canvas.getContext("2d")!;
    context.fillStyle = "#146a89";
    context.fillRect(0, 0, 640, 480);
    context.fillStyle = "#ffab30";
    context.fillRect(80, 80, 200, 320);
    const blob = await new Promise<Blob>((resolve, reject) => {
        canvas.toBlob(
            (value) =>
                value
                    ? resolve(value)
                    : reject(new Error("Cannot create fixture image")),
            "image/png",
        );
    });
    await savePhotoBlob("fixture", blob);
    const pages = Array.from({ length: 24 }, (_, index) => ({
        ...makeBlankPage(),
        centerText: index === 23 ? "" : `Print check ${index + 1}`,
    }));
    pages[0]!.slots = applyVariant("1-full", ["fixture"]);
    pages[1]!.slots = applyVariant("1-moderate", ["fixture"]);
    pages[1]!.topCaption = "Caption check";
    const zip = await exportPngPagesZip(pages, DEFAULT_PRINT_SELECTION);
    downloadBlob(zip, "pages.zip");
    status.textContent = "Done";
});
