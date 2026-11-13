const legacyKitShareMetadataPrefix = "ente-legacy-kit-share-v1:";
const legacyKitBundleMetadataPrefix = "ente-legacy-kit-shares-v1:";
const maxVisiblePDFShareCodeChars = 512;

export const findLegacyKitJSONObject = (value: string) => {
    const start = value.indexOf('{"pv"');
    if (start < 0) return undefined;

    let depth = 0;
    let inString = false;
    let escaped = false;

    for (let index = start; index < value.length; index++) {
        const char = value[index];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (char === "\\") {
            escaped = true;
            continue;
        }
        if (char === '"') {
            inString = !inString;
            continue;
        }
        if (inString) continue;
        if (char === "{") {
            depth += 1;
        } else if (char === "}") {
            depth -= 1;
            if (depth === 0) return value.slice(start, index + 1);
        }
    }

    return undefined;
};

const markerPayload = (value: string, marker: string) => {
    const markerStart = value.indexOf(marker);
    if (markerStart < 0) return undefined;

    const payloadStart = markerStart + marker.length;
    return /^[A-Za-z0-9_-]+/.exec(value.slice(payloadStart))?.[0];
};

const decodeBase64URLUTF8 = (value: string) => {
    const base64 = value
        .replaceAll("-", "+")
        .replaceAll("_", "/")
        .padEnd(Math.ceil(value.length / 4) * 4, "=");
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index++) {
        bytes[index] = binary.charCodeAt(index);
    }
    return new TextDecoder().decode(bytes);
};

export const legacyKitCodeFromPDFMetadata = (bytes: Uint8Array) => {
    const pdfText = new TextDecoder("latin1").decode(bytes);
    const sharePayload = markerPayload(pdfText, legacyKitShareMetadataPrefix);
    if (sharePayload) return decodeBase64URLUTF8(sharePayload);

    const bundlePayload = markerPayload(pdfText, legacyKitBundleMetadataPrefix);
    if (!bundlePayload) return undefined;

    const payloads: unknown = JSON.parse(decodeBase64URLUTF8(bundlePayload));
    if (!Array.isArray(payloads)) {
        throw new Error("Legacy Kit PDF metadata is invalid.");
    }
    if (payloads.length === 1 && typeof payloads[0] === "string") {
        return payloads[0];
    }
    throw new Error("Choose individual Legacy Kit sheet PDFs.");
};

export const legacyKitCodeFromVisiblePDFText = (text: string) => {
    const encodedJSONPrefix = "eyJwdiI";
    const isEncodedChunk = (value: string) => /^[A-Za-z0-9_-]+$/.test(value);
    const decodeCandidate = (encoded: string) => {
        try {
            const code = decodeBase64URLUTF8(encoded);
            return findLegacyKitJSONObject(code) === code ? code : undefined;
        } catch {
            return undefined;
        }
    };

    let encoded = "";
    for (const line of text.split(/\r?\n/)) {
        const chunk = line.trim();
        if (encoded) {
            if (
                isEncodedChunk(chunk) &&
                encoded.length + chunk.length <= maxVisiblePDFShareCodeChars
            ) {
                encoded += chunk;
                const code = decodeCandidate(encoded);
                if (code) return code;
                continue;
            }
            encoded = "";
        }

        const start = chunk.indexOf(encodedJSONPrefix);
        if (start < 0) continue;

        const candidate = chunk.slice(start);
        if (
            candidate.length <= maxVisiblePDFShareCodeChars &&
            isEncodedChunk(candidate)
        ) {
            encoded = candidate;
            const code = decodeCandidate(encoded);
            if (code) return code;
        }
    }

    return undefined;
};
