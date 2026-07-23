import { maxSecretBytesForEncodedShareLength, parseShare } from "./shamir";

interface ShareCardAsset {
    qrModules: { finder: boolean; x: number; y: number }[];
    qrSize: number;
    shareIndex: number;
    shareText: string;
    title: string;
}

const CARD_WIDTH = 1400;
const CARD_HEIGHT = 1840;
const CARD_RADIUS = 64;
const QR_SIZE = 860;
const APP_LINK = "2of3.ente.com";
const PRINTED_SHARE_CHARS_PER_LINE = 80;
const PRINTED_SHARE_LINE_COUNT = 4;
export const MAX_PRINTED_SHARE_LENGTH =
    PRINTED_SHARE_CHARS_PER_LINE * PRINTED_SHARE_LINE_COUNT;
export const MAX_SECRET_BYTES_FOR_PRINTED_CARD =
    maxSecretBytesForEncodedShareLength(MAX_PRINTED_SHARE_LENGTH);
const graphemeSegmenter =
    typeof Intl !== "undefined" && "Segmenter" in Intl
        ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
        : null;

const splitGraphemes = (value: string) =>
    graphemeSegmenter
        ? Array.from(graphemeSegmenter.segment(value), ({ segment }) => segment)
        : Array.from(value);

const overflowBoundary = (
    context: CanvasRenderingContext2D,
    text: string,
    maxWidth: number,
) => {
    let measured = "";
    let offset = 0;

    for (const grapheme of splitGraphemes(text)) {
        if (context.measureText(measured + grapheme).width > maxWidth) {
            return offset;
        }
        measured += grapheme;
        offset += grapheme.length;
    }

    return -1;
};

const wrapCanvasTextToWidth = (
    context: CanvasRenderingContext2D,
    text: string,
    maxWidth: number,
    maxLines: number,
) => {
    const normalized = text.trim().replace(/\s+/gu, " ");
    if (!normalized) return [""];

    const lines: string[] = [];
    let remaining = normalized;

    while (remaining && lines.length < maxLines) {
        if (context.measureText(remaining).width <= maxWidth) {
            lines.push(remaining);
            remaining = "";
            break;
        }

        const overflowIndex = overflowBoundary(context, remaining, maxWidth);

        if (overflowIndex <= 0) return null;

        const whitespaceIndex = remaining.lastIndexOf(" ", overflowIndex - 1);
        const splitIndex =
            whitespaceIndex > 0 ? whitespaceIndex : overflowIndex;
        const line = remaining.slice(0, splitIndex).trimEnd();
        if (!line) return null;

        lines.push(line);
        remaining = remaining
            .slice(whitespaceIndex > 0 ? splitIndex + 1 : splitIndex)
            .trimStart();
    }

    return remaining ? null : lines;
};

const fitTitleLayout = (
    context: CanvasRenderingContext2D,
    title: string,
    maxWidth: number,
    maxLines: number,
) => {
    for (let fontSize = 54; fontSize >= 34; fontSize -= 2) {
        context.font = `700 ${fontSize}px "Space Grotesk", sans-serif`;
        const lines = wrapCanvasTextToWidth(context, title, maxWidth, maxLines);
        if (!lines) continue;

        return { fontSize, lineHeight: Math.round(fontSize * 1.14), lines };
    }

    context.font = '700 34px "Space Grotesk", sans-serif';
    return {
        fontSize: 34,
        lineHeight: 39,
        lines: wrapCanvasTextToWidth(context, title, maxWidth, maxLines) ?? [
            title,
        ],
    };
};

const balanceCanvasText = (
    value: string,
    maxLineLength: number,
    maxLines: number,
) => {
    const lineCount = Math.min(
        maxLines,
        Math.ceil(value.length / maxLineLength),
    );
    if (lineCount <= 1) return [value];

    const chunks: string[] = [];
    const baseLength = Math.floor(value.length / lineCount);
    let remainder = value.length % lineCount;
    let offset = 0;

    for (let index = 0; index < lineCount; index++) {
        const chunkLength = baseLength + (remainder > 0 ? 1 : 0);
        chunks.push(value.slice(offset, offset + chunkLength));
        offset += chunkLength;
        if (remainder > 0) remainder -= 1;
    }

    return chunks;
};

const fitCodeFont = (
    context: CanvasRenderingContext2D,
    lines: string[],
    maxWidth: number,
    maxHeight: number,
) => {
    for (let fontSize = 24; fontSize >= 18; fontSize -= 1) {
        context.font = `500 ${fontSize}px Menlo, Monaco, "Courier New", monospace`;
        const widestLine = Math.max(
            ...lines.map((line) => context.measureText(line).width),
        );
        const lineHeight = fontSize + 4;
        if (widestLine <= maxWidth && lineHeight * lines.length <= maxHeight) {
            return { fontSize, lineHeight };
        }
    }

    return { fontSize: 18, lineHeight: 22 };
};

const drawQr = (
    context: CanvasRenderingContext2D,
    modules: ShareCardAsset["qrModules"],
    qrSize: number,
    left: number,
    top: number,
    size: number,
) => {
    const moduleSize = Math.max(1, Math.floor(size / qrSize));
    const drawnSize = moduleSize * qrSize;
    const offsetX = Math.floor((size - drawnSize) / 2);
    const offsetY = Math.floor((size - drawnSize) / 2);
    const startX = left + offsetX;
    const startY = top + offsetY;

    context.fillStyle = "#ffffff";
    context.fillRect(left, top, size, size);

    for (const module of modules) {
        context.fillStyle = "#111111";
        context.fillRect(
            startX + module.x * moduleSize,
            startY + module.y * moduleSize,
            moduleSize,
            moduleSize,
        );
    }
};

const ensureShareCardFonts = async () => {
    if (typeof document === "undefined" || !("fonts" in document)) return;

    await Promise.allSettled([
        document.fonts.load('700 54px "Space Grotesk"'),
        document.fonts.load('700 34px "Space Grotesk"'),
        document.fonts.load('700 36px "Space Grotesk"'),
        document.fonts.load('500 32px "Space Grotesk"'),
        document.fonts.load('700 22px "Space Grotesk"'),
        document.fonts.load('500 22px "Space Grotesk"'),
    ]);
};

export const renderShareCard = async ({
    qrModules,
    qrSize,
    shareIndex,
    shareText,
    title,
}: ShareCardAsset) => {
    await ensureShareCardFonts();

    const fingerprint = parseShare(shareText).id.slice(0, 8).toUpperCase();
    const shareLines = balanceCanvasText(
        shareText,
        PRINTED_SHARE_CHARS_PER_LINE,
        PRINTED_SHARE_LINE_COUNT,
    );
    const canvas = document.createElement("canvas");
    canvas.width = CARD_WIDTH;
    canvas.height = CARD_HEIGHT;

    const context = canvas.getContext("2d");
    if (!context) throw new Error("Could not render canvas.");

    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, CARD_WIDTH, CARD_HEIGHT);

    context.fillStyle = "#ffffff";
    context.beginPath();
    context.roundRect(48, 48, CARD_WIDTH - 96, CARD_HEIGHT - 96, CARD_RADIUS);
    context.fill();
    context.lineWidth = 3;
    context.strokeStyle = "#111111";
    context.stroke();

    context.fillStyle = "rgb(252, 239, 93)";
    context.beginPath();
    context.roundRect(84, 84, CARD_WIDTH - 168, 132, 32);
    context.fill();

    context.fillStyle = "#111111";
    context.font = '700 36px "Space Grotesk", sans-serif';
    context.fillText(`Card ${shareIndex}`, 124, 166);

    context.fillStyle = "rgba(17,17,17,0.62)";
    context.font = '500 32px "Space Grotesk", sans-serif';
    const appLinkWidth = context.measureText(APP_LINK).width;
    context.fillText(APP_LINK, CARD_WIDTH - 124 - appLinkWidth, 166);

    context.fillStyle = "#111111";
    const titleLayout = fitTitleLayout(context, title, 940, 2);
    context.font = `700 ${titleLayout.fontSize}px "Space Grotesk", sans-serif`;
    titleLayout.lines.forEach((line, index) => {
        context.fillText(line, 120, 304 + index * titleLayout.lineHeight);
    });

    context.fillStyle = "#ffffff";
    context.beginPath();
    context.roundRect(120, 392, 1160, 1088, 48);
    context.fill();
    context.lineWidth = 2.5;
    context.strokeStyle = "rgba(17,17,17,0.22)";
    context.stroke();

    drawQr(context, qrModules, qrSize, 270, 506, QR_SIZE);

    context.fillStyle = "rgba(17,17,17,0.68)";
    context.font = '700 22px "Space Grotesk", sans-serif';
    context.fillText("Code", 120, 1536);

    context.fillStyle = "rgba(17,17,17,0.45)";
    context.font = '500 22px "Space Grotesk", sans-serif';
    const fingerprintLabel = `ID ${fingerprint}`;
    const fingerprintWidth = context.measureText(fingerprintLabel).width;
    context.fillText(
        fingerprintLabel,
        CARD_WIDTH - 120 - fingerprintWidth,
        1536,
    );

    context.fillStyle = "rgba(17,17,17,0.04)";
    context.beginPath();
    context.roundRect(120, 1560, 1160, 148, 28);
    context.fill();
    context.lineWidth = 2;
    context.strokeStyle = "rgba(17,17,17,0.18)";
    context.stroke();

    const codeLeft = 148;
    const codeTop = 1603;
    const codeMaxWidth = 1104;
    const codeMaxHeight = 104;
    const codeFont = fitCodeFont(
        context,
        shareLines,
        codeMaxWidth,
        codeMaxHeight,
    );
    context.fillStyle = "#111111";
    context.font = `500 ${codeFont.fontSize}px Menlo, Monaco, "Courier New", monospace`;
    shareLines.forEach((line, index) => {
        context.fillText(line, codeLeft, codeTop + index * codeFont.lineHeight);
    });

    return canvas;
};

export const canvasToBlob = async (canvas: HTMLCanvasElement) =>
    new Promise<Blob>((resolve, reject) => {
        canvas.toBlob((blob) => {
            if (!blob) {
                reject(new Error("Could not encode PNG."));
                return;
            }
            resolve(blob);
        }, "image/png");
    });

const blobToDataUrl = (blob: Blob) =>
    new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () =>
            reject(new Error("Could not prepare this card for printing."));
        reader.onload = () => {
            if (typeof reader.result !== "string") {
                reject(new Error("Could not prepare this card for printing."));
                return;
            }
            resolve(reader.result);
        };
        reader.readAsDataURL(blob);
    });

const setPrintDocumentState = (
    doc: Document,
    title: string,
    bodyHtml: string,
    bodyClass = "",
) => {
    doc.title = title;
    doc.documentElement.innerHTML = `
        <head>
            <title>${title}</title>
            <style>
                html,body{margin:0;padding:0;background:#fff;min-height:100%}
                body{display:grid;place-items:center;min-height:100vh;font-family:ui-sans-serif,system-ui,sans-serif;color:#111}
                body.loading{background:#f7f7f2}
                .status{padding:24px 28px;border:1.5px solid rgba(17,17,17,0.16);border-radius:20px;font-size:16px;font-weight:600}
                img{display:block;max-width:100vw;max-height:100vh}
                @page{margin:0}
                @media print{
                    html,body{height:auto!important}
                    body{display:block}
                    img{width:100%;height:auto}
                }
            </style>
        </head>
        <body class="${bodyClass}">${bodyHtml}</body>
    `;
};

export const preparePrintWindow = (title: string) => {
    const popup = window.open("", "_blank");
    if (!popup) {
        throw new Error("Allow pop-ups to print this card.");
    }

    setPrintDocumentState(
        popup.document,
        title,
        '<div class="status">Preparing card for print...</div>',
        "loading",
    );
    return popup;
};

const escapeScriptTagContent = (value: string) =>
    value.replace(/<\/script/giu, "<\\/script");

export const createOfflineRecoveryHtml = async () => {
    const { OFFLINE_QR_DECODER_SOURCE } = await import("./offlineQrSource");

    return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>2of3 Offline Recovery</title>
  <meta
    name="description"
    content="This offline recovery page restores your secret from any 2 matching 2of3 cards."
  />
  <style>
    :root {
      color-scheme: light;
      --bg: #ffffff;
      --shell: #ffffff;
      --paper: #ffffff;
      --field-soft: rgba(252, 239, 93, 0.1);
      --ink: #111111;
      --muted: rgba(17,17,17,0.72);
      --yellow: rgb(252, 239, 93);
      --line: rgba(17, 17, 17, 0.18);
      --line-strong: rgba(17, 17, 17, 0.22);
    }
    [hidden] { display: none !important; }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
    }
    main {
      width: min(1120px, calc(100vw - 32px));
      margin: 0 auto;
      padding: 20px 0 40px;
    }
    .topbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      padding: 0 4px 18px;
    }
    .brand {
      font-weight: 700;
      letter-spacing: -0.07em;
      font-size: clamp(1.7rem, 4vw, 2rem);
    }
    .byline {
      color: var(--muted);
      font-size: 0.95rem;
      display: flex;
      align-items: center;
      gap: 0.35rem;
    }
    .byline a {
      color: var(--ink);
      font-weight: 700;
      text-decoration: none;
    }
    .byline a:hover {
      text-decoration: underline;
    }
    .shell {
      background: var(--shell);
      border: 2px solid var(--ink);
      border-radius: 28px;
      overflow: hidden;
      box-shadow: 0 16px 34px rgba(17,17,17,0.04);
    }
    .panel {
      padding: 24px;
    }
    h1 {
      font-size: clamp(2rem, 5vw, 2.7rem);
      line-height: 0.92;
      letter-spacing: -0.06em;
      margin: 0 0 12px;
    }
    p {
      color: var(--muted);
      line-height: 1.6;
      margin: 0;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      margin-bottom: 18px;
      padding: 7px 14px;
      border-radius: 999px;
      background: var(--paper);
      border: 1.5px solid var(--line-strong);
      font-weight: 700;
      font-size: 0.82rem;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 16px;
      margin-top: 24px;
    }
    .slot {
      padding: 16px;
      border: 1.5px solid var(--line-strong);
      border-radius: 24px;
      background: var(--paper);
      transition: border-color 140ms ease, background-color 140ms ease, transform 140ms ease;
    }
    .slot.dragover {
      border-color: var(--ink);
      background: var(--field-soft);
      transform: translateY(-1px);
    }
    .slot-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
    }
    .slot-chip {
      width: fit-content;
      padding: 6px 12px;
      border-radius: 999px;
      border: 1.5px solid var(--line-strong);
      font-size: 0.84rem;
      font-weight: 700;
    }
    .slot-copy {
      min-height: 2.8em;
      margin-top: 12px;
      font-size: 0.88rem;
    }
    textarea {
      width: 100%;
      border-radius: 18px;
      border: 1.5px solid var(--line-strong);
      background: var(--paper);
      padding: 14px 16px;
      font: inherit;
      color: var(--ink);
    }
    textarea {
      min-height: 180px;
      resize: vertical;
      margin-top: 8px;
    }
    textarea:focus {
      outline: none;
      border-color: var(--ink);
    }
    .upload,
    .action,
    .copy {
      appearance: none;
      border: 1.5px solid var(--line-strong);
      border-radius: 999px;
      padding: 10px 14px;
      background: var(--paper);
      color: var(--ink);
      font: inherit;
      font-weight: 700;
      cursor: pointer;
      text-decoration: none;
    }
    .upload:hover,
    .copy:hover {
      border-color: var(--ink);
    }
    .upload input {
      display: none;
    }
    .actions {
      margin-top: 16px;
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
    }
    .action {
      padding: 14px 20px;
      border-color: var(--ink);
      background: var(--yellow);
      color: #111111;
    }
    .action[disabled] {
      background: transparent;
      color: var(--muted);
      border-color: var(--line-strong);
      cursor: default;
    }
    .helper {
      color: var(--muted);
      font-size: 0.9rem;
    }
    .result {
      white-space: pre-wrap;
      background: var(--paper);
      border: 1.5px solid var(--line-strong);
      padding: 14px 16px;
      border-radius: 18px;
      min-height: 132px;
    }
    .error {
      color: var(--ink);
      background: var(--yellow);
      border: 2px solid var(--ink);
      border-radius: 18px;
      padding: 12px 14px;
      margin-top: 12px;
    }
    .result-card {
      margin-top: 12px;
      padding: 16px;
      border: 1.5px solid var(--ink);
      border-radius: 24px;
      background: var(--field-soft);
    }
    .result-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 12px;
    }
    .result-title {
      font-weight: 700;
      font-size: 1rem;
    }
    @media (max-width: 720px) {
      .topbar {
        padding-bottom: 14px;
      }
      .panel {
        padding: 20px;
      }
    }
  </style>
</head>
<body>
  <main>
    <div class="topbar">
      <div class="brand">2of3</div>
      <div class="byline">by <a href="https://ente.com" target="_blank" rel="noopener">Ente</a></div>
    </div>
    <div class="shell">
      <div class="panel">
        <div class="eyebrow">Recover</div>
        <h1>Use any 2 cards to recover</h1>
        <p>This file works offline. Upload two card images, or paste their codes.</p>
        <div class="grid">
          <div class="slot" id="slot-a">
            <div class="slot-head">
              <div class="slot-chip">Card A</div>
              <label class="upload">Upload image<input id="file-a" type="file" accept="image/*,text/plain" /></label>
            </div>
            <p class="slot-copy" id="meta-a">Drop a saved card image here, or paste a copied code.</p>
            <textarea id="input-a" placeholder="Paste code A"></textarea>
          </div>
          <div class="slot" id="slot-b">
            <div class="slot-head">
              <div class="slot-chip">Card B</div>
              <label class="upload">Upload image<input id="file-b" type="file" accept="image/*,text/plain" /></label>
            </div>
            <p class="slot-copy" id="meta-b">Drop a saved card image here, or paste a copied code.</p>
            <textarea id="input-b" placeholder="Paste code B"></textarea>
          </div>
        </div>
        <div id="error" class="error" hidden></div>
        <div class="actions">
          <button id="recover" class="action">Recover secret</button>
        </div>
        <div id="result-card" class="result-card" hidden>
          <div class="result-head">
            <div class="result-title">Recovered secret</div>
            <button id="copy-result" class="copy" type="button">Copy</button>
          </div>
          <div id="result" class="result"></div>
        </div>
      </div>
    </div>
  </main>
  <script>${escapeScriptTagContent(OFFLINE_QR_DECODER_SOURCE)}</script>
  <script>
    const GF_POLY = 0x11b;
    const VERSION = 1;
    const HEADER_LENGTH = 14;
    const gfMul = (left, right) => {
      let result = 0;
      let a = left;
      let b = right;
      while (b > 0) {
        if (b & 1) result ^= a;
        a <<= 1;
        if (a & 0x100) a ^= GF_POLY;
        b >>= 1;
      }
      return result;
    };
    const gfPow = (value, exponent) => {
      let result = 1;
      for (let count = 0; count < exponent; count++) {
        result = gfMul(result, value);
      }
      return result;
    };
    const gfInv = (value) => {
      if (value === 0) throw new Error("Division by zero");
      return gfPow(value, 254);
    };
    const gfDiv = (left, right) => {
      if (left === 0) return 0;
      return gfMul(left, gfInv(right));
    };
    const checksumBytes = (bytes) => {
      let hash = 0x811c9dc5;
      for (const byte of bytes) {
        hash ^= byte;
        hash = Math.imul(hash, 0x01000193) >>> 0;
      }
      return new Uint8Array([(hash >>> 24) & 255, (hash >>> 16) & 255, (hash >>> 8) & 255, hash & 255]);
    };
    const base64UrlEncode = (bytes) => {
      let binary = "";
      for (const byte of bytes) binary += String.fromCharCode(byte);
      return btoa(binary).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/u, "");
    };
    const base64UrlDecode = (value) => {
      const padded = value.replace(/-/g, "+").replace(/_/g, "/");
      const normalized = padded + "=".repeat((4 - (padded.length % 4 || 4)) % 4);
      const binary = atob(normalized);
      return Uint8Array.from(binary, (char) => char.charCodeAt(0));
    };
    const parseShare = (input) => {
      const encoded = input.replace(/\\s+/gu, "");
      if (!encoded.startsWith("2of3-")) throw new Error("That code does not look like a 2of3 share.");
      const payload = base64UrlDecode(encoded.slice(5));
      if (payload.length <= HEADER_LENGTH) throw new Error("That share looks incomplete.");
      const version = payload[0];
      const index = payload[1];
      const length = ((payload[2] || 0) << 8) | (payload[3] || 0);
      if (version !== VERSION) throw new Error("This share was created by a newer format.");
      if (![1,2,3].includes(index)) throw new Error("This share number is invalid.");
      if (payload.length !== HEADER_LENGTH + length) throw new Error("This share was cut off.");
      return {
        checksum: payload.slice(10, 14),
        data: payload.slice(14),
        id: base64UrlEncode(payload.slice(4, 10)),
        index,
        length,
      };
    };
    const combineShares = (firstInput, secondInput) => {
      const first = parseShare(firstInput);
      const second = parseShare(secondInput);
      if (first.id !== second.id || first.length !== second.length) throw new Error("These two cards are from different sets. Match the ID on both cards.");
      if (first.index === second.index) throw new Error("Use two different cards from the same set.");
      const output = new Uint8Array(first.length);
      const denominator = first.index ^ second.index;
      for (let index = 0; index < first.length; index++) {
        const left = gfMul(first.data[index], gfDiv(second.index, denominator));
        const right = gfMul(second.data[index], gfDiv(first.index, denominator));
        output[index] = left ^ right;
      }
      const expectedChecksum = checksumBytes(output);
      for (let i = 0; i < expectedChecksum.length; i++) {
        if (expectedChecksum[i] !== first.checksum[i] || expectedChecksum[i] !== second.checksum[i]) {
          throw new Error("These shares did not reconstruct a valid secret.");
        }
      }
      try {
        return new TextDecoder("utf-8", { fatal: true }).decode(output);
      } catch {
        throw new Error("These shares did not reconstruct readable text.");
      }
    };
    const loadImageFromFile = (file) =>
      new Promise((resolve, reject) => {
        const objectUrl = URL.createObjectURL(file);
        const image = new Image();
        image.onload = () => {
          resolve({
            dispose: () => URL.revokeObjectURL(objectUrl),
            height: image.naturalHeight,
            source: image,
            width: image.naturalWidth,
          });
        };
        image.onerror = () => {
          URL.revokeObjectURL(objectUrl);
          reject(new Error("Could not read that image."));
        };
        image.src = objectUrl;
      });
    const loadDrawableFromFile = async (file) => {
      if (typeof createImageBitmap === "function") {
        try {
          const bitmap = await createImageBitmap(file);
          return {
            dispose: () => bitmap.close(),
            height: bitmap.height,
            source: bitmap,
            width: bitmap.width,
          };
        } catch {}
      }
      return loadImageFromFile(file);
    };
    const imageDataFromFile = async (file) => {
      const drawable = await loadDrawableFromFile(file);
      const canvas = document.createElement("canvas");
      canvas.width = drawable.width;
      canvas.height = drawable.height;
      const context = canvas.getContext("2d");
      if (!context) {
        drawable.dispose();
        throw new Error("Could not read that image.");
      }
      try {
        context.drawImage(drawable.source, 0, 0, canvas.width, canvas.height);
        return context.getImageData(0, 0, canvas.width, canvas.height);
      } finally {
        drawable.dispose();
      }
    };
    const cropImage = (image, leftRatio, topRatio, widthRatio, heightRatio) => {
      const left = Math.max(0, Math.floor(image.width * leftRatio));
      const top = Math.max(0, Math.floor(image.height * topRatio));
      const width = Math.min(
        image.width - left,
        Math.floor(image.width * widthRatio),
      );
      const height = Math.min(
        image.height - top,
        Math.floor(image.height * heightRatio),
      );
      if (width < 64 || height < 64) return null;
      const data = new Uint8ClampedArray(width * height * 4);
      for (let row = 0; row < height; row++) {
        const sourceOffset = ((top + row) * image.width + left) * 4;
        const targetOffset = row * width * 4;
        data.set(
          image.data.slice(sourceOffset, sourceOffset + width * 4),
          targetOffset,
        );
      }
      return { data, height, width };
    };
    const decodeQrImage = (image) => {
      const decodeQR = globalThis.__twoOf3DecodeQR;
      if (typeof decodeQR !== "function") {
        throw new Error("Offline QR decoder could not load.");
      }
      const attempts = [
        { image, options: { cropToSquare: false } },
        { image },
      ];
      const cardLikeCrops = [
        [0.086, 0.213, 0.829, 0.591],
        [0.135, 0.238, 0.73, 0.49],
        [0.16, 0.255, 0.68, 0.52],
      ];
      for (const crop of cardLikeCrops) {
        const cropped = cropImage(image, ...crop);
        if (!cropped) continue;
        attempts.push(
          { image: cropped, options: { cropToSquare: false } },
          { image: cropped },
        );
      }
      let lastError = null;
      for (const attempt of attempts) {
        try {
          return decodeQR(attempt.image, attempt.options).trim();
        } catch (error) {
          lastError = error;
        }
      }
      throw lastError || new Error("Could not read that QR code.");
    };
    const describeSlotValue = (value, fileName = "") => {
      if (!value.trim()) return "Drop a saved card image here, or paste a copied code.";
      try {
        const parsed = parseShare(value);
        const fingerprint = parsed.id.slice(0, 8).toUpperCase();
        return (fileName ? fileName + " · " : "") + "Card " + parsed.index + " from ID " + fingerprint;
      } catch {
        return fileName || "Drop a saved card image here, or paste a copied code.";
      }
    };
    const fileToText = async (file) => {
      const canBeText =
        file.type.startsWith("text/") ||
        !file.type ||
        /\\.txt$/iu.test(file.name);
      if (canBeText) {
        const text = (await file.text()).trim();
        if (text) {
          try {
            parseShare(text);
            return text;
          } catch {
            if (file.type.startsWith("text/") || /\\.txt$/iu.test(file.name)) {
              throw new Error("That text file does not look like a 2of3 share.");
            }
          }
        } else if (file.type.startsWith("text/") || /\\.txt$/iu.test(file.name)) {
          throw new Error("That text file does not look like a 2of3 share.");
        }
      }
      const value = decodeQrImage(await imageDataFromFile(file));
      parseShare(value);
      return value;
    };
    const bindSlot = (slotId, fileId, textareaId, metaId) => {
      const slot = document.getElementById(slotId);
      const fileInput = document.getElementById(fileId);
      const textarea = document.getElementById(textareaId);
      const meta = document.getElementById(metaId);
      const errorNode = document.getElementById("error");
      const applyFile = async (file) => {
        if (!file) return;
        try {
          const value = (await fileToText(file)).trim();
          textarea.value = value;
          meta.textContent = describeSlotValue(value, file.name);
          errorNode.hidden = true;
          errorNode.textContent = "";
        } catch (error) {
          textarea.value = "";
          meta.textContent = describeSlotValue("");
          errorNode.hidden = false;
          errorNode.textContent = error.message || String(error);
        }
      };
      fileInput.addEventListener("change", async (event) => {
        const file = event.target.files && event.target.files[0];
        try {
          await applyFile(file);
        } finally {
          event.target.value = "";
        }
      });
      textarea.addEventListener("input", (event) => {
        meta.textContent = describeSlotValue(event.target.value.trim());
      });
      slot.addEventListener("dragenter", (event) => {
        event.preventDefault();
        slot.classList.add("dragover");
      });
      slot.addEventListener("dragover", (event) => {
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
        slot.classList.add("dragover");
      });
      slot.addEventListener("dragleave", () => {
        slot.classList.remove("dragover");
      });
      slot.addEventListener("drop", async (event) => {
        event.preventDefault();
        slot.classList.remove("dragover");
        const file = event.dataTransfer.files && event.dataTransfer.files[0];
        await applyFile(file);
      });
    };
    bindSlot("slot-a", "file-a", "input-a", "meta-a");
    bindSlot("slot-b", "file-b", "input-b", "meta-b");
    document.getElementById("recover").addEventListener("click", () => {
      const errorNode = document.getElementById("error");
      const resultNode = document.getElementById("result");
      const resultCard = document.getElementById("result-card");
      errorNode.hidden = true;
      errorNode.textContent = "";
      resultCard.hidden = true;
      const firstInput = document.getElementById("input-a").value.trim();
      const secondInput = document.getElementById("input-b").value.trim();
      if (!firstInput || !secondInput) {
        errorNode.hidden = false;
        errorNode.textContent = "Upload or paste two cards first.";
        return;
      }
      try {
        const secret = combineShares(firstInput, secondInput);
        resultNode.textContent = secret;
        resultCard.hidden = false;
      } catch (error) {
        errorNode.hidden = false;
        errorNode.textContent = error.message || String(error);
      }
    });
    document.getElementById("copy-result").addEventListener("click", async () => {
      const button = document.getElementById("copy-result");
      const resultNode = document.getElementById("result");
      const errorNode = document.getElementById("error");
      if (!resultNode.textContent.trim()) return;
      try {
        if (!navigator.clipboard || typeof navigator.clipboard.writeText !== "function") {
          throw new Error("Could not copy here. Select the recovered secret and copy it manually.");
        }
        await navigator.clipboard.writeText(resultNode.textContent);
        button.textContent = "Copied";
        window.setTimeout(() => {
          button.textContent = "Copy";
        }, 1600);
      } catch (error) {
        errorNode.hidden = false;
        errorNode.textContent =
          error && error.message
            ? error.message
            : "Could not copy here. Select the recovered secret and copy it manually.";
      }
    });
  </script>
</body>
</html>`;
};

export const offlineRecoveryFile = async () =>
    new File([await createOfflineRecoveryHtml()], "2of3-recovery.html", {
        type: "text/html;charset=utf-8",
    });

export const shareFiles = async (files: File[]) => {
    const api = navigator as Navigator & {
        canShare?: (data?: ShareData) => boolean;
        share?: (data?: ShareData) => Promise<void>;
    };

    if (
        typeof api.share !== "function" ||
        typeof api.canShare !== "function" ||
        !api.canShare({ files })
    ) {
        throw new Error("Sharing files is not supported here.");
    }

    await api.share({
        files,
        title: "2of3 cards",
        text: "Keep these cards separate. Any 2 can recover the secret.",
    });
};

export const printBlob = (
    blob: Blob,
    title: string,
    popup = preparePrintWindow(title),
) =>
    new Promise<void>((resolve, reject) => {
        let settled = false;
        let cleanupTimer = 0;

        const cleanup = () => {
            if (cleanupTimer) {
                window.clearTimeout(cleanupTimer);
            }
        };

        const settle = (callback: () => void) => {
            if (settled) return;
            settled = true;
            cleanup();
            callback();
        };

        const run = async () => {
            const dataUrl = await blobToDataUrl(blob);
            const doc = popup.document;
            setPrintDocumentState(
                doc,
                title,
                `<img src="${dataUrl}" alt="${title.replace(/"/g, "&quot;")}" />`,
            );

            const imageNode = doc.querySelector("img");
            if (imageNode?.tagName !== "IMG") {
                throw new Error("Could not print this card.");
            }
            const image = imageNode;

            await new Promise<void>((resolveImage, rejectImage) => {
                if (image.complete && image.naturalWidth > 0) {
                    resolveImage();
                    return;
                }
                image.onload = () => resolveImage();
                image.onerror = () =>
                    rejectImage(new Error("Could not print this card."));
            });

            if ("decode" in image) {
                try {
                    await image.decode();
                } catch {
                    // Continue; the image is already loaded enough to print.
                }
            }

            await new Promise<void>((done) => {
                popup.requestAnimationFrame(() => {
                    popup.requestAnimationFrame(() => done());
                });
            });

            const afterPrint = () => {
                popup.close();
                settle(resolve);
            };
            popup.addEventListener("afterprint", afterPrint, { once: true });
            cleanupTimer = window.setTimeout(() => settle(resolve), 4000);
            popup.focus();
            popup.print();
        };

        void run().catch((error: unknown) => {
            popup.close();
            settle(() =>
                reject(
                    error instanceof Error
                        ? error
                        : new Error("Could not print this card."),
                ),
            );
        });
    });

export const downloadBlob = (blob: Blob, filename: string) => {
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
};

export const sanitizeFilename = (value: string) =>
    value
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .slice(0, 48) || "2of3";
