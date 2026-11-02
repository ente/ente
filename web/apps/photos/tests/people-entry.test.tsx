import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, expect, test, vi } from "vitest";
import { usePeopleEntry } from "../src/components/gallery/sections/people/use-people-entry";

const consent = vi.hoisted(() => ({
    enabled: false,
    show: vi.fn(),
    close: vi.fn(),
}));
vi.mock("ente-base/components/utils/modal", () => ({
    useModalVisibility: () => ({
        show: consent.show,
        props: { open: false, onClose: consent.close },
    }),
}));
vi.mock("ente-new/photos/components/utils/use-snapshot", () => ({
    useMLStatusSnapshot: () => undefined,
}));
vi.mock("ente-new/photos/services/ml", () => ({
    isMLEnabled: () => consent.enabled,
}));

beforeEach(() => {
    consent.enabled = false;
    vi.clearAllMocks();
});

const entry = () => {
    const navigate = vi.fn();
    let result: ReturnType<typeof usePeopleEntry>;
    const Harness = () => {
        result = usePeopleEntry({
            isCurrentDestination: false,
            onUnavailable: vi.fn(),
            onNavigate: navigate,
        });
        return null;
    };
    renderToStaticMarkup(<Harness />);
    return { ...result!, navigate };
};

test("defers navigation and search reset until consent succeeds", () => {
    const controller = entry();
    const reset = vi.fn();
    expect(controller.showPeople(reset)).toBe(false);
    expect(consent.show).toHaveBeenCalledOnce();
    expect(reset).not.toHaveBeenCalled();
    expect(controller.navigate).not.toHaveBeenCalled();
    consent.enabled = true;
    controller.dialogProps.onEnabled();
    expect(reset).toHaveBeenCalledOnce();
    expect(controller.navigate).toHaveBeenCalledOnce();
});

test("cancelling consent discards the pending search reset", () => {
    const controller = entry();
    const reset = vi.fn();
    controller.showPeople(reset);
    controller.dialogProps.onClose();
    expect(consent.close).toHaveBeenCalledOnce();
    expect(controller.navigate).not.toHaveBeenCalled();
    consent.enabled = true;
    expect(controller.showPeople()).toBe(true);
    expect(reset).not.toHaveBeenCalled();
    expect(controller.navigate).toHaveBeenCalledOnce();
});

test("enabled People navigation preserves reset-before-navigation order", () => {
    consent.enabled = true;
    const controller = entry();
    const reset = vi.fn();
    expect(controller.showPeople(reset)).toBe(true);
    expect(consent.show).not.toHaveBeenCalled();
    expect(reset.mock.invocationCallOrder[0]).toBeLessThan(
        controller.navigate.mock.invocationCallOrder[0]!,
    );
});
