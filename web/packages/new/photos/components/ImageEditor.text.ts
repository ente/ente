export interface EditorTextLayer {
    text: string;
    x: number;
    y: number;
    size: number;
    font: "sans-serif" | "serif" | "monospace";
    color: string;
    background: boolean;
    align: "left" | "center" | "right";
}

export const newTextLayer = (): EditorTextLayer => ({
    text: "",
    x: 0.5,
    y: 0.5,
    size: 8,
    font: "sans-serif",
    color: "#ffffff",
    background: true,
    align: "center",
});

// Coordinates and type size are relative to the image, so the same layout
// can be drawn on the preview or the full-resolution export.
export const drawEditorText = (
    canvas: HTMLCanvasElement,
    layers: EditorTextLayer[],
) => {
    const ctx = canvas.getContext("2d")!;
    ctx.save();
    try {
        for (const layer of layers) {
            if (!layer.text.trim()) continue;
            const size =
                (Math.min(canvas.width, canvas.height) * layer.size) / 100;
            ctx.font = `${size}px ${layer.font}`;
            ctx.textBaseline = "middle";
            ctx.textAlign = layer.align;
            const lines = layer.text.split("\n");
            const padding = size * 0.2;
            const maxWidth = canvas.width - 2 * padding;
            const width = Math.min(
                maxWidth,
                lines.reduce(
                    (max, line) => Math.max(max, ctx.measureText(line).width),
                    0,
                ),
            );
            const lineHeight = size * 1.2;
            const height = lines.length * lineHeight;
            const left = Math.max(
                padding,
                Math.min(
                    canvas.width - width - padding,
                    layer.x * canvas.width - width / 2,
                ),
            );
            const top = Math.max(
                padding,
                Math.min(
                    canvas.height - height - padding,
                    layer.y * canvas.height - height / 2,
                ),
            );
            if (layer.background) {
                ctx.fillStyle = "rgba(0, 0, 0, 0.75)";
                ctx.fillRect(
                    left - padding,
                    top - padding,
                    width + padding * 2,
                    height + padding * 2,
                );
            }
            ctx.fillStyle = layer.color;
            const x =
                left +
                (layer.align === "center"
                    ? width / 2
                    : layer.align === "right"
                      ? width
                      : 0);
            lines.forEach((line, i) =>
                ctx.fillText(line, x, top + (i + 0.5) * lineHeight, maxWidth),
            );
        }
    } finally {
        ctx.restore();
    }
};
