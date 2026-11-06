// At the Android editor's 2000 px capture threshold, the portrait emulator's
// drawable frame measures 2000 × 2936. Use this frame for composition and
// export so changing a desktop window's size doesn't change the saved photo.
export const mobileTextFrame = { width: 2000, height: 2936, logicalWidth: 412 };

export const textOutputSize = (width: number, height: number) => {
    const scale =
        Math.max(width, height) <= 2000
            ? 1
            : Math.min(
                  mobileTextFrame.width / width,
                  mobileTextFrame.height / height,
              );
    return {
        width: Math.max(1, Math.ceil(width * scale)),
        height: Math.max(1, Math.ceil(height * scale)),
    };
};

export interface EditorTextLayer {
    text: string;
    x: number;
    y: number;
    /** Size relative to the shorter edge, retained across preview and export. */
    size: number;
    font: "Inter" | "Outfit" | "Gochi Hand";
    bold: boolean;
    italic: boolean;
    color: string;
    backgroundColor: string;
    opacity: 0 | 0.5 | 1;
    align: "left" | "center" | "right";
}

export const newTextLayer = (): EditorTextLayer => ({
    text: "",
    x: 0.5,
    y: 0.5,
    size: 0,
    font: "Inter",
    bold: false,
    italic: false,
    color: "#ffffff",
    backgroundColor: "#000000",
    opacity: 1,
    align: "center",
});

export const textFont = (layer: EditorTextLayer, size: number) =>
    `${layer.italic ? "italic " : ""}${layer.bold ? 700 : layer.font === "Outfit" ? 500 : 400} ${size}px "${layer.font === "Gochi Hand" ? layer.font : layer.font + " Variable"}"`;

export const loadTextFonts = (layers: EditorTextLayer[]) =>
    Promise.all(
        layers
            .filter((layer) => layer.text.trim())
            .map((layer) =>
                document.fonts.load(textFont(layer, 24), layer.text),
            ),
    );

const wrapLines = (ctx: CanvasRenderingContext2D, text: string, max: number) =>
    text.split("\n").flatMap((paragraph) => {
        const lines: string[] = [];
        let line = "";
        for (const word of paragraph.split(/(\s+)/)) {
            if (line.trim() && ctx.measureText(line + word).width > max) {
                lines.push(line.trimEnd());
                line = "";
            }
            for (const char of word) {
                if (line && ctx.measureText(line + char).width > max) {
                    lines.push(line);
                    line = "";
                }
                line += char;
            }
        }
        lines.push(line.trimEnd());
        return lines;
    });

export const drawEditorText = (
    canvas: HTMLCanvasElement,
    layers: EditorTextLayer[],
) => {
    const ctx = canvas.getContext("2d")!;
    ctx.save();
    try {
        for (const layer of layers) {
            if (!layer.text.trim()) continue;
            const size = Math.min(canvas.width, canvas.height) * layer.size;
            ctx.font = textFont(layer, size);
            ctx.textBaseline = "middle";
            ctx.textAlign = layer.align;
            // Flutter pads a caption by 30% of its line height at either side
            // and 10% above and below the glyphs.
            const metrics = ctx.measureText("Mg");
            const lineHeight =
                metrics.fontBoundingBoxAscent +
                    metrics.fontBoundingBoxDescent || size * 1.2;
            const pad = lineHeight * 0.3;
            const verticalPad = lineHeight * 0.1;
            const lines = wrapLines(
                ctx,
                layer.text,
                Math.max(1, canvas.width - 2 * pad),
            );
            const widths = lines.map((line) => ctx.measureText(line).width);
            const width = widths.reduce((a, b) => Math.max(a, b), 0);
            const height = lines.length * lineHeight + 2 * verticalPad;
            const left = Math.max(
                pad,
                Math.min(
                    canvas.width - width - pad,
                    layer.x * canvas.width - width / 2,
                ),
            );
            const top = Math.max(
                0,
                Math.min(
                    canvas.height - height,
                    layer.y * canvas.height - height / 2,
                ),
            );
            const align =
                layer.align === "center"
                    ? 0.5
                    : layer.align === "right"
                      ? 1
                      : 0;
            const x = left + width * align;
            if (layer.opacity > 0) {
                ctx.fillStyle = layer.backgroundColor;
                ctx.globalAlpha = layer.opacity;
                ctx.beginPath();
                widths.forEach((w, i) =>
                    ctx.roundRect(
                        x - w * align - pad,
                        top + i * lineHeight,
                        w + 2 * pad,
                        lineHeight + 2 * verticalPad,
                        size * 0.25,
                    ),
                );
                ctx.fill();
                ctx.globalAlpha = 1;
            }
            ctx.fillStyle = layer.color;
            lines.forEach((line, i) =>
                ctx.fillText(
                    line,
                    x,
                    top + verticalPad + (i + 0.5) * lineHeight,
                ),
            );
        }
    } finally {
        ctx.restore();
    }
};
