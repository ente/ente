import React, { type EffectCallback, type SetStateAction } from "react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { PostComments } from "../src/components/PostComments";
import type { SpaceComment } from "../src/services/space";
import type { CommentDraft } from "../src/utils/comments";

const mocks = vi.hoisted(() => ({
    hooks: [] as unknown[],
    index: 0,
    effects: [] as EffectCallback[],
    load: vi.fn(),
    react: vi.fn(),
    delete: vi.fn(),
    create: vi.fn(),
}));

vi.mock("react", async (importOriginal) => {
    const actual = await importOriginal<typeof import("react")>();
    const useState = <T,>(initial?: T | (() => T)) => {
        const index = mocks.index++;
        if (!(index in mocks.hooks))
            mocks.hooks[index] =
                typeof initial == "function" ? (initial as () => T)() : initial;
        return [
            mocks.hooks[index] as T,
            (value: SetStateAction<T>) => {
                mocks.hooks[index] =
                    typeof value == "function"
                        ? (value as (previous: T) => T)(mocks.hooks[index] as T)
                        : value;
            },
        ] as const;
    };
    return {
        ...actual,
        default: {
            ...actual,
            useState,
            useRef: <T,>(value: T) => useState({ current: value })[0],
            useCallback: <T,>(callback: T) => callback,
            useMemo: <T,>(callback: () => T) => callback(),
            useEffect: (effect: EffectCallback) => mocks.effects.push(effect),
            useLayoutEffect: vi.fn(),
        },
    };
});
vi.mock("@mui/material", () => ({
    Box: "box",
    CircularProgress: "progress",
    ClickAwayListener: "click-away",
    Dialog: "dialog",
    Grow: "grow",
    Popper: "popper",
    Slide: "slide",
    useMediaQuery: () => false,
}));
vi.mock("components/AvatarImage", () => ({ SpaceAvatarImage: "avatar" }));
vi.mock("components/BottomSheetTransition", () => ({
    SpaceBottomSheetTransition: "transition",
}));
vi.mock("components/CommentComposer", () => ({
    SpaceCommentComposer: "composer",
}));
vi.mock("components/MessageActionMenu", () => ({
    CopyIcon: "copy",
    DeleteIcon: "delete",
    ReplyIcon: "reply",
    MessageActionMenuItem: "menu-item",
    MessageActionMenuList: "menu",
}));
vi.mock("components/MessageReactionPicker", () => ({
    MessageQuickReactions: "quick-reactions",
    MessageReactionPicker: "picker",
}));
vi.mock("components/ReplyComposerPreview", () => ({
    ReplyComposerPreview: "preview",
}));
vi.mock("data/emojis", () => ({ emojiName: () => "emoji" }));
vi.mock("hooks/use-browser-back-close", () => ({
    useBrowserBackClose: vi.fn(),
}));
vi.mock("styles/colors", () => import("../src/styles/colors"));
vi.mock("utils/route-transitions", () => ({ useSpaceRouter: vi.fn() }));
vi.mock("services/space", () => ({
    loadCurrentComments: mocks.load,
    setCurrentCommentReaction: mocks.react,
    deleteCurrentComment: mocks.delete,
    createCurrentComment: mocks.create,
    loadCurrentFriendAvatarURL: vi.fn(),
    markCurrentNotificationItemsRead: vi.fn(),
    removeCurrentCommentReaction: vi.fn(),
}));

const comment: SpaceComment = {
    commentId: "comment",
    parentId: "",
    replyToId: "",
    text: "Hello",
    createdAt: "2026-10-21T00:00:00Z",
    deleted: false,
    canDelete: true,
    reactions: [],
    unreadNotificationIds: [],
};

type Element = React.ReactElement<Record<string, unknown>>;

let draft: CommentDraft;

const elements = (node: React.ReactNode): Element[] => {
    if (Array.isArray(node)) return node.flatMap(elements);
    if (!React.isValidElement<Record<string, unknown>>(node)) return [];
    const children = node.props.children;
    return [
        node,
        ...elements(
            typeof children == "function"
                ? (children as (props: object) => React.ReactNode)({
                      placement: "bottom-start",
                  })
                : (children as React.ReactNode),
        ),
    ];
};

const render = () => {
    mocks.index = 0;
    return elements(
        PostComments({
            container: () => null,
            viewer: "viewer",
            owner: "owner",
            postId: 42,
            draft,
            setDraft: (update) => {
                draft = typeof update == "function" ? update(draft) : update;
            },
            onClose: vi.fn(),
        }) as React.ReactNode,
    );
};

const composer = () => render().find((node) => node.type == "composer")!;
const alert = () => render().find((node) => node.props.role == "alert");

const mutate = (kind: "react" | "delete") => {
    const row = render().find((node) => node.props.comment === comment)!;
    if (kind == "react") {
        (row.props.onReact as (emoji: string) => void)("❤️");
    } else {
        (row.props.onOpenActions as (anchor: object, source: string) => void)(
            {},
            "contextmenu",
        );
        const button = render().find((node) => node.props.label == "Delete")!;
        (button.props.onClick as () => void)();
    }
};

beforeEach(async () => {
    vi.resetAllMocks();
    mocks.hooks = [];
    mocks.effects = [];
    draft = { text: "New comment" };
    mocks.load.mockResolvedValue([comment]);
    render();
    mocks.effects[0]!();
    await vi.waitFor(() => expect(composer().props.sendDisabled).toBe(false));
});

afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
});

test("a lost creation response keeps the submission ID through reopening and retry", async () => {
    mocks.create.mockRejectedValueOnce(new Error("Response lost"));
    await expect(
        (composer().props.onSend as (text: string) => Promise<void>)(
            draft.text,
        ),
    ).rejects.toThrow("Response lost");
    const submission = draft.pendingSubmission!;
    expect(submission.commentId).toEqual(expect.any(String));
    expect(draft.text).toBe("New comment");
    expect(draft.sending).toBe(false);
    mocks.hooks = [];
    mocks.create.mockResolvedValueOnce(undefined);
    await (composer().props.onSend as (text: string) => Promise<void>)(
        draft.text,
    );
    expect(mocks.create.mock.calls[1]).toEqual(mocks.create.mock.calls[0]);
    expect(draft.text).toBe("");
    expect(draft.pendingSubmission).toBeUndefined();
});

test.each(["text", "reply"])(
    "changing the %s after a failed send creates a new submission",
    async (change) => {
        mocks.create.mockRejectedValueOnce(new Error("Request failed"));
        await expect(
            (composer().props.onSend as (text: string) => Promise<void>)(
                draft.text,
            ),
        ).rejects.toThrow("Request failed");
        const firstID = draft.pendingSubmission!.commentId;
        if (change == "text") draft.text = "Changed comment";
        else draft.replyTarget = { status: "selected", commentId: "comment" };
        await (composer().props.onSend as (text: string) => Promise<void>)(
            draft.text,
        );
        expect(mocks.create.mock.calls[1]![3]).not.toBe(firstID);
        expect(mocks.create.mock.calls[1]![4]).toBe(
            change == "reply" ? "comment" : undefined,
        );
        expect(mocks.create.mock.calls[1]![5]).toBe(
            change == "text" ? "Changed comment" : "New comment",
        );
    },
);

test.each(["react", "delete"] as const)(
    "a failed %s keeps the composer usable when the discussion refresh succeeds",
    async (kind) => {
        mocks[kind].mockRejectedValueOnce(new Error("Request failed"));
        mutate(kind);
        await vi.waitFor(() => expect(alert()).toBeDefined());
        expect(mocks.load).toHaveBeenCalledTimes(2);
        expect(composer().props.disabled).toBeFalsy();
        await (composer().props.onSend as (text: string) => Promise<void>)(
            "Still able to comment",
        );
        expect(mocks.create).toHaveBeenCalledWith(
            "viewer",
            "owner",
            42,
            expect.any(String),
            undefined,
            "Still able to comment",
        );
        mocks[kind].mockResolvedValueOnce(undefined);
        mutate(kind);
        await vi.waitFor(() => expect(mocks.load).toHaveBeenCalledTimes(3));
        expect(alert()).toBeUndefined();
        expect(composer().props.disabled).toBeFalsy();
    },
);

test("a failed refresh still disables the unavailable discussion after a mutation fails", async () => {
    mocks.react.mockRejectedValueOnce(new Error("Request failed"));
    mocks.load.mockRejectedValueOnce(new Error("Access denied"));
    mutate("react");
    await vi.waitFor(() => expect(alert()).toBeDefined());
    expect(composer().props.disabled).toBe(true);
    expect(alert()!.props.children).toContain(
        "Discussion unavailable. Access may have changed or the post may have been deleted.",
    );
});

test.each(["selected", "unavailable"] as const)(
    "cancelling a %s reply preserves the draft",
    (status) => {
        draft.replyTarget =
            status == "selected"
                ? { status, commentId: comment.commentId }
                : { status };
        const preview = render().find((node) => node.type == "preview")!;

        (preview.props.onCancel as () => void)();

        expect(draft.replyTarget).toBeUndefined();
        expect(draft.text).toBe("New comment");
        expect(composer().props.disabled).toBeFalsy();
        expect(composer().props.placeholder).toBe("Add a comment…");
        expect(render().find((node) => node.type == "preview")).toBeUndefined();
    },
);

const commentGesture = (
    overrides: Record<string, unknown> = {},
    commentId = comment.commentId,
) => {
    vi.useFakeTimers();
    class Target {
        constructor(readonly kind: "body" | "button" | "reaction" = "body") {}
        closest(selector: string) {
            return (
                selector.includes("button")
                    ? this.kind != "body"
                    : this.kind == "reaction"
            )
                ? this
                : null;
        }
        hasAttribute() {
            return this.kind == "reaction";
        }
        getBoundingClientRect() {
            return { width: 390, right: 390 };
        }
        setPointerCapture = vi.fn();
    }
    vi.stubGlobal("Element", Target);
    vi.stubGlobal("window", {
        innerWidth: 390,
        setTimeout,
        clearTimeout,
        getSelection: () => null,
    });
    const parent = render();
    const focus = vi.fn();
    const inputRef = parent.find((node) => node.type == "composer")!.props
        .inputRef as React.RefObject<{ focus: typeof focus }>;
    inputRef.current = { focus };
    const element = parent.find(
        (node) =>
            (node.props.comment as SpaceComment | undefined)?.commentId ==
            commentId,
    )!;
    const Component = element.type as (
        props: Record<string, unknown>,
    ) => Element;
    const hookOffset = mocks.index;
    const row = () => {
        mocks.index = hookOffset;
        return Component({ ...element.props, ...overrides });
    };
    const target = new Target();
    const pointer = (
        type:
            | "onPointerDown"
            | "onPointerMove"
            | "onPointerUp"
            | "onPointerCancel",
        x: number,
        y = 0,
        options: Record<string, unknown> = {},
    ) => {
        const event = {
            pointerId: 1,
            pointerType: "touch",
            isPrimary: true,
            button: 0,
            clientX: x,
            clientY: y,
            target,
            currentTarget: target,
            cancelable: true,
            preventDefault: vi.fn(),
            stopPropagation: vi.fn(),
            ...options,
        };
        (row().props[type] as (event: unknown) => void)(event);
        return event;
    };
    const click = (target: Target) => {
        const event = {
            target,
            preventDefault: vi.fn(),
            stopPropagation: vi.fn(),
        };
        (row().props.onClickCapture as (event: unknown) => void)(event);
        return event;
    };
    return { focus, pointer, click, Target };
};

test("swiping a comment right selects it for reply and focuses the existing draft", () => {
    const { pointer, focus } = commentGesture();
    pointer("onPointerDown", 100);
    pointer("onPointerMove", 180);
    expect(draft.replyTarget).toBeUndefined();
    pointer("onPointerUp", 180);
    expect(draft.replyTarget).toEqual({
        status: "selected",
        commentId: "comment",
    });
    expect(draft.text).toBe("New comment");
    expect(focus).toHaveBeenCalledWith({ preventScroll: true });
    vi.runAllTimers();
    expect(render().find((node) => node.type == "popper")!.props.open).toBe(
        false,
    );
});

test("swiping a threaded reply selects that reply rather than the root comment", async () => {
    const reply: SpaceComment = {
        ...comment,
        commentId: "nested-reply",
        parentId: "comment",
        replyToId: "comment",
    };
    mocks.hooks = [];
    mocks.effects = [];
    mocks.load.mockResolvedValue([comment, reply]);
    render();
    mocks.effects[0]!();
    await vi.waitFor(() => expect(composer().props.sendDisabled).toBe(false));
    const { pointer } = commentGesture({}, reply.commentId);
    pointer("onPointerDown", 100);
    pointer("onPointerMove", 180);
    pointer("onPointerUp", 180);
    expect(draft.replyTarget).toEqual({
        status: "selected",
        commentId: "nested-reply",
    });
});

test.each([
    ["short", 130, 0],
    ["leftward", 20, 0],
    ["vertical", 110, 80],
    ["diagonal", 180, 100],
] as const)(
    "a %s drag does not reply or open the long-press menu",
    (_, x, y) => {
        const { pointer, focus } = commentGesture();
        pointer("onPointerDown", 100);
        pointer("onPointerMove", x, y);
        pointer("onPointerUp", x, y);
        vi.runAllTimers();
        expect(draft.replyTarget).toBeUndefined();
        expect(focus).not.toHaveBeenCalled();
        expect(render().find((node) => node.type == "popper")!.props.open).toBe(
            false,
        );
    },
);

test("a swipe near the right edge uses the available space", () => {
    const { pointer } = commentGesture();
    pointer("onPointerDown", 350);
    pointer("onPointerMove", 375);
    pointer("onPointerUp", 375);
    expect(draft.replyTarget).toEqual({
        status: "selected",
        commentId: "comment",
    });
});

test("cancelled swipes and unrelated pointer releases do not reply", () => {
    const { pointer } = commentGesture();
    pointer("onPointerDown", 100);
    pointer("onPointerMove", 180);
    pointer("onPointerUp", 180, 0, { pointerId: 2 });
    expect(draft.replyTarget).toBeUndefined();
    pointer("onPointerCancel", 180);
    pointer("onPointerUp", 180);
    expect(draft.replyTarget).toBeUndefined();
});

test.each(["mouse", "pen"])(
    "%s dragging does not trigger a touch reply",
    (pointerType) => {
        const { pointer } = commentGesture();
        pointer("onPointerDown", 100, 0, { pointerType });
        pointer("onPointerMove", 180, 0, { pointerType });
        pointer("onPointerUp", 180, 0, { pointerType });
        expect(draft.replyTarget).toBeUndefined();
    },
);

test.each(["button", "reaction"] as const)(
    "swiping from a %s replies without activating the original control",
    (kind) => {
        const { pointer, click, Target } = commentGesture();
        const target = new Target(kind);
        pointer("onPointerDown", 100, 0, { target });
        pointer("onPointerMove", 180, 0, { target });
        pointer("onPointerUp", 180, 0, { target });
        expect(draft.replyTarget).toEqual({
            status: "selected",
            commentId: "comment",
        });
        const event = click(target);
        expect(event.preventDefault).toHaveBeenCalled();
        expect(event.stopPropagation).toHaveBeenCalled();
    },
);

test.each(["button", "reaction"] as const)(
    "tapping a %s still activates the control without replying",
    (kind) => {
        const { pointer, click, Target } = commentGesture();
        const target = new Target(kind);
        const down = pointer("onPointerDown", 100, 0, { target });
        pointer("onPointerUp", 100, 0, { target });
        expect(down.currentTarget.setPointerCapture).not.toHaveBeenCalled();
        const event = click(target);
        expect(event.preventDefault).not.toHaveBeenCalled();
        expect(event.stopPropagation).not.toHaveBeenCalled();
        expect(draft.replyTarget).toBeUndefined();
    },
);

test("a short horizontal drag on a control does not activate it or reply", () => {
    const { pointer, click, Target } = commentGesture();
    const target = new Target("button");
    pointer("onPointerDown", 100, 0, { target });
    pointer("onPointerMove", 130, 0, { target });
    pointer("onPointerUp", 130, 0, { target });
    const event = click(target);
    expect(event.preventDefault).toHaveBeenCalled();
    expect(event.stopPropagation).toHaveBeenCalled();
    expect(draft.replyTarget).toBeUndefined();
});

test.each(["button", "reaction"] as const)(
    "a vertical drag starting on a %s scrolls without replying",
    (kind) => {
        const { pointer, Target } = commentGesture();
        const target = new Target(kind);
        pointer("onPointerDown", 100, 0, { target });
        const move = pointer("onPointerMove", 110, 80, { target });
        pointer("onPointerUp", 110, 80, { target });
        expect(move.preventDefault).not.toHaveBeenCalled();
        vi.runAllTimers();
        expect(draft.replyTarget).toBeUndefined();
    },
);

test.each([{ disabled: true }, { comment: { ...comment, deleted: true } }])(
    "inactive comments cannot be swiped to reply",
    (overrides) => {
        const { pointer } = commentGesture(overrides);
        pointer("onPointerDown", 100);
        pointer("onPointerMove", 180);
        pointer("onPointerUp", 180);
        expect(draft.replyTarget).toBeUndefined();
    },
);

test("long-pressing still opens comment actions without replying", () => {
    const { pointer } = commentGesture();
    pointer("onPointerDown", 100);
    vi.advanceTimersByTime(520);
    pointer("onPointerMove", 180);
    const release = pointer("onPointerUp", 180);
    expect(release.preventDefault).toHaveBeenCalled();
    expect(draft.replyTarget).toBeUndefined();
    expect(render().find((node) => node.type == "popper")!.props.open).toBe(
        true,
    );
});

test("releasing a reaction long press cannot activate the sheet, but a fresh tap can", () => {
    const { pointer, Target } = commentGesture();
    pointer("onPointerDown", 100, 0, { target: new Target("reaction") });
    vi.advanceTimersByTime(520);
    const slide = render().find((node) => node.type == "slide")!;
    expect(slide.props.in).toBe(true);
    const sheet = slide.props.children as Element;
    const event = {
        target: new Target("button"),
        detail: 1,
        preventDefault: vi.fn(),
        stopPropagation: vi.fn(),
    };
    const click = sheet.props.onClickCapture as (event: unknown) => void;
    click(event);
    expect(event.preventDefault).toHaveBeenCalled();
    expect(event.stopPropagation).toHaveBeenCalled();

    event.preventDefault.mockClear();
    event.stopPropagation.mockClear();
    (sheet.props.onPointerDownCapture as (event: unknown) => void)(event);
    click(event);
    expect(event.preventDefault).not.toHaveBeenCalled();
    expect(event.stopPropagation).not.toHaveBeenCalled();
});

test.each(["keyboard", "cancelled", "different control"])(
    "reactions sheet handles %s activation",
    (source) => {
        const { pointer, Target } = commentGesture();
        pointer("onPointerDown", 100, 0, { target: new Target("reaction") });
        vi.advanceTimersByTime(520);
        const sheet = render().find((node) => node.type == "slide")!.props
            .children as Element;
        const event = {
            target: new Target("button"),
            detail: source == "keyboard" ? 0 : 1,
            preventDefault: vi.fn(),
            stopPropagation: vi.fn(),
        };
        if (source != "keyboard") {
            (sheet.props.onPointerDownCapture as (event: unknown) => void)(
                event,
            );
            if (source == "cancelled")
                (sheet.props.onPointerCancel as () => void)();
            else event.target = new Target("button");
        }
        (sheet.props.onClickCapture as (event: unknown) => void)(event);
        expect(event.preventDefault).toHaveBeenCalledTimes(
            source == "keyboard" ? 0 : 1,
        );
        expect(event.stopPropagation).toHaveBeenCalledTimes(
            source == "keyboard" ? 0 : 1,
        );
    },
);

test("replying from the long-press menu focuses the input and preserves the draft", () => {
    const { pointer, focus } = commentGesture();
    pointer("onPointerDown", 100);
    vi.advanceTimersByTime(520);
    pointer("onPointerUp", 100);
    const reply = render().find((node) => node.props.label == "Reply")!;

    (reply.props.onClick as () => void)();

    expect(draft.replyTarget).toEqual({
        status: "selected",
        commentId: comment.commentId,
    });
    expect(draft.text).toBe("New comment");
    expect(focus).toHaveBeenCalledWith({ preventScroll: true });
    expect(render().find((node) => node.type == "popper")!.props.open).toBe(
        false,
    );
});
