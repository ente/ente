import type { MiniDialogAttributes } from "../MiniDialog";

interface MiniDialogState {
    open: boolean;
    attributes?: MiniDialogAttributes;
    id: number;
}

type MiniDialogAction =
    | { type: "show"; attributes: MiniDialogAttributes }
    | { type: "routeChange" }
    | { type: "close"; id: number };

export const miniDialogReducer = (
    current: MiniDialogState,
    action: MiniDialogAction,
): MiniDialogState => {
    if (action.type === "routeChange") {
        return current.open && current.attributes?.dismissOnRouteChange
            ? { open: false, id: current.id + 1 }
            : current;
    }
    if (action.type === "close") {
        // An older async action must not dismiss a replacement prompt.
        return current.id === action.id ? { ...current, open: false } : current;
    }
    if (current.open && current.attributes?.nonReplaceable) return current;
    return { open: true, attributes: action.attributes, id: current.id + 1 };
};
