// @vitest-environment happy-dom
import type { EnteFile } from "ente-media/file";
import { ImageEditorOverlay } from "ente-new/photos/components/ImageEditorOverlay";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("ente-base/context", () => ({
    useBaseContext: () => ({ showMiniDialog: vi.fn() }),
}));
vi.mock("ente-gallery/services/download", () => ({
    downloadManager: {
        renderableSourceURLs: () =>
            Promise.resolve({
                type: "image",
                imageURL: "blob:test-photo",
                mimeType: "image/jpeg",
            }),
    },
}));
vi.mock("ente-new/photos/services/photos-fdb", () => ({
    savedCollections: vi.fn(),
}));
vi.mock("i18next", () => ({ t: (key: string) => key }));

// Keep the editor's state, effects, and canvas renderer real; replace the visual
// controls with buttons so the test can trigger their public callbacks.
vi.mock("@mui/material", async () => {
    const { createElement } = await import("react");
    const Container = ({
        children,
        ref,
    }: React.PropsWithChildren<{ ref?: React.Ref<HTMLDivElement> }>) => (
        <div ref={ref}>{children}</div>
    );
    const Button = ({
        children,
        onClick,
    }: React.PropsWithChildren<{ onClick?: () => void }>) => (
        <button onClick={onClick}>{children}</button>
    );
    return {
        Backdrop: Container,
        Box: Container,
        Stack: Container,
        Button,
        IconButton: Button,
        CircularProgress: () => null,
        Tabs: ({
            children,
            onChange,
        }: React.PropsWithChildren<{
            onChange: (event: unknown, value: string) => void;
        }>) => <div onClick={() => onChange(null, "colors")}>{children}</div>,
        Tab: ({ label }: { label: string }) => <button>{label}</button>,
        styled:
            (component: Parameters<typeof createElement>[0]) =>
            () =>
            ({ children }: React.PropsWithChildren) =>
                createElement(component, null, children),
    };
});
vi.mock("ente-base/components/RowButton", () => {
    const Group = ({ children }: React.PropsWithChildren) => (
        <div>{children}</div>
    );
    return {
        RowButtonGroup: Group,
        RowButtonGroupTitle: Group,
        RowButtonDivider: () => null,
        RowButton: ({ label }: { label: string }) => <button>{label}</button>,
        RowSlider: ({
            label,
            value,
            step,
            onChange,
        }: {
            label: string;
            value: number;
            step: number;
            onChange: (value: number) => void;
        }) => <button onClick={() => onChange(value + step)}>{label}</button>,
        RowSwitch: ({
            label,
            onClick,
        }: {
            label: string;
            onClick: () => void;
        }) => <button onClick={onClick}>{label}</button>,
    };
});

const context = () => ({
    filter: "none",
    save: vi.fn(),
    restore: vi.fn(),
    clearRect: vi.fn(),
    drawImage: vi.fn(),
    putImageData: vi.fn(),
    getImageData: vi.fn(),
});

afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
});

test("ordinary adjustments draw only the preview and defer full-resolution rendering", async () => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.stubGlobal(
        "ResizeObserver",
        class {
            observe = vi.fn();
            disconnect = vi.fn();
        },
    );
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
        queueMicrotask(() => callback(0));
        return 1;
    });
    vi.stubGlobal(
        "Image",
        class {
            width = 8000;
            height = 6000;
            onload: (() => void) | null = null;
            set src(_value: string) {
                queueMicrotask(() => this.onload?.());
            }
        },
    );
    const contexts = new Map<HTMLCanvasElement, ReturnType<typeof context>>();
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation(
        function (this: HTMLCanvasElement) {
            let value = contexts.get(this);
            if (!value) {
                value = context();
                contexts.set(this, value);
            }
            return value as unknown as CanvasRenderingContext2D;
        },
    );
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue({
        x: 0,
        y: 0,
        left: 0,
        top: 0,
        right: 800,
        bottom: 600,
        width: 800,
        height: 600,
        toJSON: () => ({}),
    });
    const container = document.createElement("div");
    document.body.append(container);
    const root = createRoot(container);
    try {
        await act(async () => {
            root.render(
                <ImageEditorOverlay
                    open
                    onClose={vi.fn()}
                    file={{ id: 1 } as EnteFile}
                    onSaveEditedCopy={() => true}
                />,
            );
            await Promise.resolve();
        });
        const [preview, original] = container.querySelectorAll("canvas");
        expect(preview).toBeDefined();
        expect(original).toBeDefined();
        const previewContext = contexts.get(preview!)!;
        // Track the hidden canvas even though loading should never acquire it.
        const originalContext = context();
        contexts.set(original!, originalContext);
        expect([preview!.width, preview!.height]).toEqual([1600, 1200]);
        const click = async (label: string) => {
            const button = [...container.querySelectorAll("button")].find(
                (button) => button.textContent === label,
            );
            expect(button).toBeDefined();
            await act(async () => {
                button!.click();
                await Promise.resolve();
            });
        };
        await click("colors");
        for (const label of [
            "brightness",
            "contrast",
            "saturation",
            "blur",
            "invert_colors",
        ]) {
            previewContext.drawImage.mockClear();
            await click(label);
            expect(previewContext.drawImage).toHaveBeenCalled();
            expect(originalContext.drawImage).not.toHaveBeenCalled();
            expect(originalContext.putImageData).not.toHaveBeenCalled();
            expect([original!.width, original!.height]).toEqual([1, 1]);
        }
    } finally {
        await act(async () => {
            root.unmount();
            await Promise.resolve();
        });
        container.remove();
    }
});
