declare module "qr-code-styling" {
    type QRCodeStylingOptions = Record<string, unknown>;

    export default class QRCodeStyling {
        constructor(options?: QRCodeStylingOptions);
        append(container: HTMLElement): void;
        update(options?: QRCodeStylingOptions): void;
        download(
            options?: { name?: string; extension?: string } | string,
        ): Promise<void>;
    }
}
