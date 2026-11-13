export const prettyFormatCode = (code: string) =>
    code.replace(/(.{3})/g, "$1 ").trim();
