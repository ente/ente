import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export interface Todo {
    id: string;
    title: string;
    dueAtMs: number | null;
    completedAtMs: number | null;
    version: number;
}

export interface ToolTurnStatus {
    undo: "none" | "available" | "undone" | "partlyUndone" | "stale";
    confirm: "none" | "offered" | "stale";
    canRetry: boolean;
}

export const listTodos = () => invoke<Todo[]>("todo_list");

export const createTodo = (title: string, dueAtMs: number | null) =>
    invoke<Todo>("todo_create", { title, dueAtMs });

export const updateTodo = (todo: Todo, title: string, dueAtMs: number | null) =>
    invoke<Todo>("todo_update", {
        id: todo.id,
        version: todo.version,
        title,
        dueAtMs,
    });

export const setTodoCompleted = (todo: Todo, completed: boolean) =>
    invoke<Todo>("todo_set_completed", {
        id: todo.id,
        version: todo.version,
        completed,
    });

export const deleteTodo = async (todo: Todo) => {
    await invoke("todo_delete", { id: todo.id, version: todo.version });
};

export const confirmToolTurn = (replyId: string) =>
    invoke<ToolTurnStatus>("tool_turn_confirm", { replyId });

export const undoToolTurn = (replyId: string) =>
    invoke<ToolTurnStatus>("tool_turn_undo", { replyId });

export const loadTodoTurnStatuses = (sessionId: string) =>
    invoke<Record<string, ToolTurnStatus>>("tool_turn_statuses", { sessionId });

const onTodosChanged = (onChange: () => void): Promise<UnlistenFn> =>
    listen("todo-changed", onChange);

export const watchTodos = <T>(
    query: () => Promise<T>,
    onLoad: (value: T) => void,
    onError: (error: unknown) => void,
    subscribe = onTodosChanged,
) => {
    let disposed = false;
    let revision = 0;
    let stop: UnlistenFn | undefined;
    const refresh = () => {
        if (disposed) return;
        const requestRevision = ++revision;
        void query()
            .then((value) => {
                if (!disposed && requestRevision === revision) onLoad(value);
            })
            .catch((error: unknown) => {
                if (!disposed && requestRevision === revision) onError(error);
            });
    };
    refresh();
    void subscribe(refresh)
        .then((unlisten) => {
            stop = unlisten;
            if (disposed) stop();
            else refresh();
        })
        .catch((error: unknown) => {
            if (!disposed) onError(error);
        });
    return {
        refresh,
        dispose: () => {
            if (disposed) return;
            disposed = true;
            stop?.();
        },
    };
};

export const todoChanges = () => {
    let shown: Todo[] = [];
    let queue: Promise<void> = Promise.resolve();
    return {
        show(list: Todo[]) {
            shown = list;
        },
        change(
            todo: Todo,
            action: (latest: Todo) => Promise<Todo> | Promise<void>,
        ): Promise<void> {
            const next = queue.then(async () => {
                const latest =
                    shown.find((item) => item.id === todo.id) ?? todo;
                const updated = await action(latest);
                if (updated) {
                    shown = shown.map((item) =>
                        item.id === updated.id ? updated : item,
                    );
                }
            });
            queue = next.catch(() => undefined);
            return next;
        },
    };
};

export const isOpen = (todo: Todo) => todo.completedAtMs === null;

export const formatDue = (dueAtMs: number) => {
    const due = new Date(dueAtMs);
    return due.toLocaleString(undefined, {
        weekday: "short",
        day: "numeric",
        month: "short",
        year:
            due.getFullYear() === new Date().getFullYear()
                ? undefined
                : "numeric",
        hour: "numeric",
        minute: "2-digit",
    });
};

const refusalMessages: Record<string, string> = {
    "refused.todo_changed": "This To Do changed since. Try again.",
    "refused.title_missing": "A To Do needs a title.",
    "refused.title_too_long": "That title is too long for a To Do.",
    "refused.undo_stale":
        "These To Dos changed since, so this can't be undone.",
    "refused.offer_stale":
        "This offer is out of date because your To Dos changed since. Ask again to update them.",
    "refused.earlier_reply_stands":
        "An earlier reply to this message changed your To Dos. Undo it first.",
    "refused.nothing_offered": "This reply didn't offer any changes.",
    "refused.nothing_changed": "This reply didn't change any To Dos.",
};

export const refusalMessage = (name: string | undefined) =>
    name ? refusalMessages[name] : undefined;
