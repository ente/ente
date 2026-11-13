import qrDecodeModuleSource from "qr-raw/decode.js?raw";
import qrIndexModuleSource from "qr-raw/index.js?raw";

const stripSourceMapComment = (source: string) =>
    source.replace(/^\/\/# sourceMappingURL=.*$/gmu, "").trim();

const toStandaloneIndexSource = (source: string) =>
    stripSourceMapComment(source)
        .replace(/^export class Bitmap/mu, "class Bitmap")
        .replace(/^export const ECMode = /mu, "const ECMode = ")
        .replace(/^export const Encoding = /mu, "const Encoding = ")
        .replace(/^export function utf8ToBytes\(/mu, "function utf8ToBytes(")
        .replace(/^export function encodeQR\(/mu, "function encodeQR(")
        .replace(/^export default encodeQR;\n?/mu, "")
        .replace(/^export const utils = /mu, "const utils = ")
        .replace(/^export const _tests = /mu, "const qrIndexTests = ");

const toStandaloneDecodeSource = (source: string) =>
    [
        "const decodeQR = (() => {",
        stripSourceMapComment(source)
            .replace(
                /^import \{ Bitmap, utils \} from "\.\/index\.js";\n?/mu,
                "",
            )
            .replace(/^export function decodeQR\(/mu, "function decodeQR(")
            .replace(/^export default decodeQR;\n?/mu, "")
            .replace(
                /^export const _TESTS = /mu,
                "const qrDecodeFocusedTests = ",
            )
            .replace(/^export const _tests = /mu, "const qrDecodeTests = "),
        "return decodeQR;",
        "})();",
    ].join("\n");

export const OFFLINE_QR_DECODER_SOURCE = [
    "(() => {",
    toStandaloneIndexSource(qrIndexModuleSource),
    toStandaloneDecodeSource(qrDecodeModuleSource),
    "globalThis.__twoOf3DecodeQR = decodeQR;",
    "})();",
].join("\n\n");
