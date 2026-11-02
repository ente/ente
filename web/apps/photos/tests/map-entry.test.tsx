import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { useMapEntry } from "../src/components/gallery/sections/places/use-map-entry";

const settings = vi.hoisted(() => ({
    enabled: false,
    update: vi.fn(),
    error: vi.fn(),
}));
vi.mock("ente-base/context", () => ({
    useBaseContext: () => ({ onGenericError: settings.error }),
}));
vi.mock("ente-new/photos/components/utils/use-snapshot", () => ({
    useSettingsSnapshot: () => ({ mapEnabled: settings.enabled }),
}));
vi.mock("ente-new/photos/services/settings", () => ({
    updateMapEnabled: settings.update,
}));
beforeEach(() => {
    vi.clearAllMocks();
    settings.enabled = false;
    settings.update.mockResolvedValue(undefined);
});

const entry = () => {
    const open = vi.fn();
    let activate: ReturnType<typeof useMapEntry>;
    const Harness = () => {
        activate = useMapEntry(open);
        return null;
    };
    renderToStaticMarkup(<Harness />);
    return { open, activate: activate! };
};

test("waits for map enablement before opening", async () => {
    let finish: () => void;
    settings.update.mockReturnValue(
        new Promise<void>((resolve) => {
            finish = resolve;
        }),
    );
    const controller = entry();
    controller.activate();
    expect(settings.update).toHaveBeenCalledWith(true);
    expect(controller.open).not.toHaveBeenCalled();
    finish!();
    await Promise.resolve();
    expect(controller.open).toHaveBeenCalledOnce();
});

test("keeps the destination unchanged when map enablement fails", async () => {
    const error = new Error("enable failed");
    settings.update.mockRejectedValue(error);
    const controller = entry();
    controller.activate();
    await Promise.resolve();
    expect(controller.open).not.toHaveBeenCalled();
    expect(settings.error).toHaveBeenCalledWith(error);
});

test("opens an enabled map without writing settings again", () => {
    settings.enabled = true;
    const controller = entry();
    controller.activate();
    expect(settings.update).not.toHaveBeenCalled();
    expect(controller.open).toHaveBeenCalledOnce();
});
