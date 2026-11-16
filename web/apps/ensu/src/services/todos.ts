import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import {
    fromNativeMessage,
    type ChatMessage,
    type NativeMessage,
} from "./chat/store";
import type { LlmToolCall } from "./llm/types";

export interface Todo {
    id: string;
    title: string;
    dueAtMs: number | null;
    completedAtMs: number | null;
    createdAtMs: number;
    updatedAtMs: number;
    /** Sent back with every change so stale edits are refused. */
    version: number;
}

export interface TodoTurn {
    reply: ChatMessage;
    changed: boolean;
    /** The reply offers changes the user can make with {@link confirmTodoTurn}. */
    pending: boolean;
}

export interface TodoTurnStatus {
    changed: boolean;
    undone: boolean;
    pending: boolean;
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

/**
 * Applies the tool calls a reply produced for the user message `sourceId`
 * and returns the saved receipt, which replaces the prepared answer.
 * `callProbability` is the model's confidence in the calls: below a
 * threshold, saves and completions are offered for confirmation instead.
 */
export const applyTodoCalls = async (
    sourceId: string,
    calls: LlmToolCall[],
    callProbability: number | null,
    preparationToken?: string,
): Promise<TodoTurn> => {
    const turn = await invoke<{
        reply: NativeMessage;
        changed: boolean;
        pending: boolean;
    }>("todo_apply_calls", {
        input: {
            sourceId,
            calls,
            nowMs: Date.now(),
            callProbability,
            preparationToken,
        },
    });
    return {
        reply: fromNativeMessage(turn.reply),
        changed: turn.changed,
        pending: turn.pending,
    };
};

/** Makes the changes a reply offered. */
export const confirmTodoTurn = async (replyId: string) => {
    await invoke("todo_confirm", { replyId });
};

export const undoTodoTurn = async (replyId: string) => {
    await invoke("todo_undo", { replyId });
};

export const todoTurnStatus = (replyId: string) =>
    invoke<TodoTurnStatus | null>("todo_turn_status", { replyId });

/** Statuses for the replies that changed To Dos; others are left out. */
export const loadTodoTurnStatuses = (replyIds: string[]) =>
    invoke<Record<string, TodoTurnStatus>>("todo_turn_statuses", { replyIds });

/** Calls `onChange` whenever the list changes, from chat or from the panel. */
export const onTodosChanged = (onChange: () => void): Promise<UnlistenFn> =>
    listen("todo-changed", onChange);

export const isOpen = (todo: Todo) => todo.completedAtMs === null;

export const formatDue = (dueAtMs: number) =>
    new Date(dueAtMs).toLocaleString(undefined, {
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "numeric",
        minute: "2-digit",
    });
