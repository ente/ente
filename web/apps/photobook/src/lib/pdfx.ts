import magickWasmUrl from "@imagemagick/magick-wasm/magick.wasm";

type MagickWasm = typeof import("@imagemagick/magick-wasm");
type ColorProfileInstance = InstanceType<MagickWasm["ColorProfile"]>;

interface PdfXTools {
    magick: MagickWasm;
    srgbProfile: ColorProfileInstance;
    fograProfile: ColorProfileInstance;
    fograProfileBytes: Uint8Array;
}

const SRGB_PROFILE_PATH = "/pdfx/sRGB.icc";
const FOGRA39_PROFILE_PATH = "/pdfx/FOGRA39L_coated.icc";
const PDFX_JPEG_QUALITY = 98;
const MM_PER_INCH = 25.4;
const POINTS_PER_INCH = 72;

export interface PdfXPageSize {
    widthMm: number;
    heightMm: number;
    widthPx: number;
    heightPx: number;
}

let toolsPromise: Promise<PdfXTools> | null = null;

async function fetchBytes(path: string): Promise<Uint8Array> {
    const response = await fetch(path);
    if (!response.ok) {
        throw new Error(`Failed to load ${path}: ${response.status}`);
    }
    return new Uint8Array(await response.arrayBuffer());
}

async function initializePdfXTools(): Promise<PdfXTools> {
    const magick = await import("@imagemagick/magick-wasm");
    const [wasmBytes, srgbProfileBytes, fograProfileBytes] = await Promise.all([
        fetchBytes(magickWasmUrl),
        fetchBytes(SRGB_PROFILE_PATH),
        fetchBytes(FOGRA39_PROFILE_PATH),
    ]);

    await magick.initializeImageMagick(wasmBytes);

    return {
        magick,
        srgbProfile: new magick.ColorProfile(srgbProfileBytes),
        fograProfile: new magick.ColorProfile(fograProfileBytes),
        fograProfileBytes,
    };
}

async function getPdfXTools(): Promise<PdfXTools> {
    toolsPromise ??= initializePdfXTools();

    try {
        return await toolsPromise;
    } catch (error) {
        toolsPromise = null;
        throw error;
    }
}

function getJpegComponentCount(jpeg: Uint8Array): number | null {
    let i = 2;
    while (i < jpeg.length) {
        if (jpeg[i] !== 0xff) {
            i += 1;
            continue;
        }

        while (jpeg[i] === 0xff) i += 1;
        const marker = jpeg[i]!;
        i += 1;
        if (marker === 0xd9 || marker === 0xda) break;
        if (i + 1 >= jpeg.length) break;

        const length = (jpeg[i]! << 8) | jpeg[i + 1]!;
        if (
            marker >= 0xc0 &&
            marker <= 0xcf &&
            ![0xc4, 0xc8, 0xcc].includes(marker)
        ) {
            return jpeg[i + 7] ?? null;
        }
        i += length;
    }
    return null;
}

export async function renderCanvasToFogra39Jpeg(
    canvas: HTMLCanvasElement,
): Promise<Uint8Array> {
    const tools = await getPdfXTools();
    const result: { jpeg?: Uint8Array } = {};

    tools.magick.ImageMagick.readFromCanvas(canvas, (image) => {
        const transformed = image.transformColorSpace(
            tools.srgbProfile,
            tools.fograProfile,
        );
        if (!transformed) {
            throw new Error("Failed to transform page image to FOGRA39 CMYK.");
        }

        image.quality = PDFX_JPEG_QUALITY;
        image.settings.setDefine(
            tools.magick.MagickFormat.Jpeg,
            "sampling-factor",
            "1x1",
        );
        image.write(tools.magick.MagickFormat.Jpeg, (data) => {
            result.jpeg = new Uint8Array(data);
        });
    });

    const { jpeg } = result;
    if (!jpeg) {
        throw new Error("Failed to encode FOGRA39 CMYK JPEG.");
    }

    const componentCount = getJpegComponentCount(jpeg);
    if (componentCount !== 4) {
        throw new Error(
            `Expected FOGRA39 CMYK JPEG with 4 components, got ${
                componentCount ?? "unknown"
            }.`,
        );
    }

    return jpeg;
}

class PdfByteWriter {
    private chunks: Uint8Array[] = [];
    private encoder = new TextEncoder();

    position = 0;

    appendAscii(text: string) {
        this.appendBytes(this.encoder.encode(text));
    }

    appendBytes(bytes: Uint8Array) {
        this.chunks.push(bytes);
        this.position += bytes.length;
    }

    toUint8Array(): Uint8Array {
        const out = new Uint8Array(this.position);
        let offset = 0;
        for (const chunk of this.chunks) {
            out.set(chunk, offset);
            offset += chunk.length;
        }
        return out;
    }
}

function pdfString(value: string): string {
    return `(${value.replace(/([\\()])/g, "\\$1")})`;
}

function mmToPt(value: number): number {
    return (value / MM_PER_INCH) * POINTS_PER_INCH;
}

function pad2(value: number): string {
    return String(value).padStart(2, "0");
}

function pdfDate(date: Date): string {
    const offset = -date.getTimezoneOffset();
    const sign = offset >= 0 ? "+" : "-";
    const absOffset = Math.abs(offset);
    const hours = pad2(Math.floor(absOffset / 60));
    const minutes = pad2(absOffset % 60);

    return [
        "D:",
        date.getFullYear(),
        pad2(date.getMonth() + 1),
        pad2(date.getDate()),
        pad2(date.getHours()),
        pad2(date.getMinutes()),
        pad2(date.getSeconds()),
        sign,
        hours,
        "'",
        minutes,
        "'",
    ].join("");
}

function xmlDate(date: Date): string {
    return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function randomPdfId(): string {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
        "",
    );
}

function randomUuid(): string {
    if ("randomUUID" in crypto) return crypto.randomUUID();
    const id = randomPdfId();
    return [
        id.slice(0, 8),
        id.slice(8, 12),
        id.slice(12, 16),
        id.slice(16, 20),
        id.slice(20),
    ].join("-");
}

function buildXmpMetadata(now: Date): Uint8Array {
    const id = randomUuid();
    const date = xmlDate(now);
    const xmp = `<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Ente Photobook">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about="" xmlns:pdfxid="http://www.npes.org/pdfx/ns/id/">
      <pdfxid:GTS_PDFXVersion>PDF/X-4</pdfxid:GTS_PDFXVersion>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:pdf="http://ns.adobe.com/pdf/1.3/">
      <pdf:Producer>Ente Photobook</pdf:Producer>
      <pdf:Trapped>False</pdf:Trapped>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
      <xmp:CreatorTool>Ente Photobook</xmp:CreatorTool>
      <xmp:CreateDate>${date}</xmp:CreateDate>
      <xmp:ModifyDate>${date}</xmp:ModifyDate>
      <xmp:MetadataDate>${date}</xmp:MetadataDate>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/">
      <xmpMM:DocumentID>uuid:${id}</xmpMM:DocumentID>
      <xmpMM:InstanceID>uuid:${id}</xmpMM:InstanceID>
      <xmpMM:RenditionClass>default</xmpMM:RenditionClass>
      <xmpMM:VersionID>1</xmpMM:VersionID>
    </rdf:Description>
    <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:format>application/pdf</dc:format>
      <dc:title>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">Ente Photobook</rdf:li>
        </rdf:Alt>
      </dc:title>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>`;

    return new TextEncoder().encode(xmp);
}

function appendObject(
    writer: PdfByteWriter,
    offsets: number[],
    id: number,
    body: string,
) {
    offsets[id] = writer.position;
    writer.appendAscii(`${id} 0 obj\n${body}\nendobj\n`);
}

function appendStreamObject(
    writer: PdfByteWriter,
    offsets: number[],
    id: number,
    dict: string,
    stream: Uint8Array,
) {
    offsets[id] = writer.position;
    writer.appendAscii(
        `${id} 0 obj\n<< ${dict} /Length ${stream.length} >>\nstream\n`,
    );
    writer.appendBytes(stream);
    writer.appendAscii("\nendstream\nendobj\n");
}

interface PageObjectIds {
    pageId: number;
    imageId: number;
    contentId: number;
}

export async function createPdfX4(
    pageJpegs: Uint8Array[],
    pageSize: PdfXPageSize,
): Promise<Uint8Array> {
    if (pageJpegs.length === 0) {
        throw new Error("Cannot create a PDF/X-4 file without pages.");
    }

    const { fograProfileBytes } = await getPdfXTools();
    const pageWidthPt = mmToPt(pageSize.widthMm);
    const pageHeightPt = mmToPt(pageSize.heightMm);
    const now = new Date();
    const writer = new PdfByteWriter();
    const offsets: number[] = [0];
    const pageIds: PageObjectIds[] = pageJpegs.map((_, index) => ({
        pageId: 3 + index * 3,
        imageId: 4 + index * 3,
        contentId: 5 + index * 3,
    }));
    let nextId = 3 + pageJpegs.length * 3;

    const iccId = nextId++;
    const infoId = nextId++;
    const outputIntentId = nextId++;
    const metadataId = nextId++;
    const fileId = randomPdfId();

    writer.appendBytes(
        new Uint8Array([
            0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x36, 0x0a, 0x25, 0xe2,
            0xe3, 0xcf, 0xd3, 0x0a,
        ]),
    );

    appendObject(
        writer,
        offsets,
        1,
        `<< /Type /Catalog /Pages 2 0 R /OutputIntents [${outputIntentId} 0 R] /Metadata ${metadataId} 0 R /ViewerPreferences << /DisplayDocTitle true >> >>`,
    );
    appendObject(
        writer,
        offsets,
        2,
        `<< /Type /Pages /Kids [${pageIds
            .map((ids) => `${ids.pageId} 0 R`)
            .join(" ")}] /Count ${pageIds.length} >>`,
    );

    pageIds.forEach((ids, index) => {
        appendObject(
            writer,
            offsets,
            ids.pageId,
            `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidthPt.toFixed(5)} ${pageHeightPt.toFixed(5)}] /TrimBox [0 0 ${pageWidthPt.toFixed(5)} ${pageHeightPt.toFixed(5)}] /BleedBox [0 0 ${pageWidthPt.toFixed(5)} ${pageHeightPt.toFixed(5)}] /Resources << /ProcSet [/PDF /ImageC] /XObject << /Im0 ${ids.imageId} 0 R >> >> /Contents ${ids.contentId} 0 R >>`,
        );
        appendStreamObject(
            writer,
            offsets,
            ids.imageId,
            `/Type /XObject /Subtype /Image /Width ${pageSize.widthPx} /Height ${pageSize.heightPx} /ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /DCTDecode /Decode [1 0 1 0 1 0 1 0] /Interpolate false`,
            pageJpegs[index]!,
        );
        appendStreamObject(
            writer,
            offsets,
            ids.contentId,
            "",
            new TextEncoder().encode(
                `q\n${pageWidthPt.toFixed(5)} 0 0 ${pageHeightPt.toFixed(5)} 0 0 cm\n/Im0 Do\nQ\n`,
            ),
        );
    });

    appendStreamObject(
        writer,
        offsets,
        iccId,
        "/N 4 /Alternate /DeviceCMYK",
        fograProfileBytes,
    );
    appendObject(
        writer,
        offsets,
        infoId,
        `<< /Title ${pdfString("Ente Photobook")} /Creator ${pdfString(
            "Ente Photobook",
        )} /Producer ${pdfString("Ente Photobook")} /CreationDate ${pdfString(
            pdfDate(now),
        )} /ModDate ${pdfString(pdfDate(now))} /Trapped /False /GTS_PDFXVersion ${pdfString(
            "PDF/X-4",
        )} >>`,
    );
    appendObject(
        writer,
        offsets,
        outputIntentId,
        `<< /Type /OutputIntent /S /GTS_PDFX /OutputConditionIdentifier ${pdfString(
            "FOGRA39",
        )} /OutputCondition ${pdfString("FOGRA39L Coated")} /RegistryName ${pdfString(
            "http://www.color.org",
        )} /Info ${pdfString(
            "FOGRA39L Coated, CMYK output intent",
        )} /DestOutputProfile ${iccId} 0 R >>`,
    );
    appendStreamObject(
        writer,
        offsets,
        metadataId,
        "/Type /Metadata /Subtype /XML",
        buildXmpMetadata(now),
    );

    const xrefOffset = writer.position;
    writer.appendAscii(`xref\n0 ${nextId}\n`);
    writer.appendAscii("0000000000 65535 f \n");
    for (let id = 1; id < nextId; id += 1) {
        writer.appendAscii(
            `${String(offsets[id]).padStart(10, "0")} 00000 n \n`,
        );
    }
    writer.appendAscii(
        `trailer\n<< /Size ${nextId} /Root 1 0 R /Info ${infoId} 0 R /ID [<${fileId}> <${fileId}>] >>\nstartxref\n${xrefOffset}\n%%EOF\n`,
    );

    return writer.toUint8Array();
}
