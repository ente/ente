import type { PasteThemeTokens } from "@/features/paste/theme/pasteThemeTokens";

export interface QRCodeStylingInstance {
    append(container: HTMLElement): void;
    update(options: Record<string, unknown>): void;
    download(
        options?: { name?: string; extension?: string } | string,
    ): Promise<void>;
    _qr?: { getModuleCount(): number };
}

type QRCodeStylingConstructor = new (
    options: Record<string, unknown>,
) => QRCodeStylingInstance;

interface QRCodeStylingModule {
    default: QRCodeStylingConstructor;
}

type QrErrorCorrectionLevel = "L" | "M" | "Q" | "H";

const QR_ERROR_CORRECTION_LEVEL: QrErrorCorrectionLevel = "M";
const QR_LOGO_ERROR_CORRECTION_LEVEL: QrErrorCorrectionLevel = "H";
const QUIET_ZONE_MODULES = 4;

const qrCenterLockDataUrl = (paperBg: string, lockColor: string) => {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="5" fill="${paperBg}"/><path fill="${lockColor}" d="M10 14v-2.5C10 8.5 12.5 6 16 6s6 2.5 6 5.5V14h1c1.1 0 2 .9 2 2v8c0 1.1-.9 2-2 2H9c-1.1 0-2-.9-2-2v-8c0-1.1.9-2 2-2h1Zm3 0h6v-2.5C19 10.1 17.9 9 16 9s-3 1.1-3 2.5V14Z"/></svg>`;

    return `data:image/svg+xml,${encodeURIComponent(svg)}`;
};

export const isQRCodeStylingModule = (
    value: unknown,
): value is QRCodeStylingModule => {
    if (typeof value !== "object" || value === null || !("default" in value)) {
        return false;
    }

    return typeof value.default === "function";
};

export const getQrModuleCount = (qrCode: QRCodeStylingInstance) => {
    const internalQr = qrCode._qr;

    return internalQr ? internalQr.getModuleCount() : undefined;
};

export const getQrRenderMetrics = (qrSize: number, moduleCount: number) => {
    const moduleSize = Math.max(
        1,
        Math.ceil(qrSize / (moduleCount + QUIET_ZONE_MODULES * 2)),
    );

    return {
        renderSize: (moduleCount + QUIET_ZONE_MODULES * 2) * moduleSize,
        margin: QUIET_ZONE_MODULES * moduleSize,
    };
};

export const getPasteQrCodeOptions = ({
    value,
    qrSize,
    qrPaperBg,
    tokens,
    showCenterLock,
}: {
    value: string;
    qrSize: number;
    qrPaperBg: string;
    tokens: PasteThemeTokens;
    showCenterLock: boolean;
}) => ({
    width: qrSize,
    height: qrSize,
    type: "svg",
    data: value,
    qrOptions: {
        errorCorrectionLevel: showCenterLock
            ? QR_LOGO_ERROR_CORRECTION_LEVEL
            : QR_ERROR_CORRECTION_LEVEL,
    },
    backgroundOptions: { color: qrPaperBg },
    dotsOptions: { color: tokens.qr.module, type: "rounded" },
    cornersSquareOptions: { color: tokens.qr.finder, type: "extra-rounded" },
    cornersDotOptions: { color: tokens.qr.finder, type: "dot" },
    ...(showCenterLock && {
        image: qrCenterLockDataUrl(qrPaperBg, tokens.qr.finder),
        imageOptions: { hideBackgroundDots: true, imageSize: 0.2, margin: 1 },
    }),
});

export const downloadPasteQrCode = async ({
    value,
    tokens,
    paperBg,
    showCenterLock,
}: {
    value: string;
    tokens: PasteThemeTokens;
    paperBg?: string;
    showCenterLock: boolean;
}) => {
    const qrSize = 512;
    const qrPaperBg = paperBg ?? tokens.qr.paperBg;
    const qrCodeStylingModule = (await import("qr-code-styling")) as unknown;

    if (!isQRCodeStylingModule(qrCodeStylingModule)) {
        throw new Error("Failed to load qr-code-styling");
    }

    const { default: QRCodeStyling } = qrCodeStylingModule;
    const qrOptions = getPasteQrCodeOptions({
        value,
        qrSize,
        qrPaperBg,
        tokens,
        showCenterLock,
    });
    const qrCode = new QRCodeStyling(qrOptions);
    const moduleCount = getQrModuleCount(qrCode);

    if (moduleCount !== undefined) {
        qrCode.update({
            ...qrOptions,
            ...getQrRenderMetrics(qrSize, moduleCount),
        });
    }

    await qrCode.download({ name: "ente-paste-qr", extension: "png" });
};
