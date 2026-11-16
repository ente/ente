import {
    createTodo,
    deleteTodo,
    formatDue,
    isOpen,
    listTodos,
    onTodosChanged,
    setTodoCompleted,
    updateTodo,
    type Todo,
} from "@/services/todos";
import { Delete01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import {
    Box,
    Button,
    Checkbox,
    Dialog,
    DialogContent,
    DialogTitle,
    IconButton,
    Stack,
    TextField,
    Typography,
} from "@mui/material";
import React, { useCallback, useEffect, useState } from "react";

interface TodoDialogProps {
    open: boolean;
    onClose: () => void;
    onError: (error: unknown) => void;
}

/** `datetime-local` input value for a time, in the local zone. */
const toInputValue = (ms: number | null) => {
    if (ms === null) return "";
    const date = new Date(ms);
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const fromInputValue = (value: string) =>
    value ? new Date(value).getTime() : null;

/**
 * The To Do list without the model: everything chat can do to a To Do can
 * also be done here by hand.
 */
export const TodoDialog: React.FC<TodoDialogProps> = ({
    open,
    onClose,
    onError,
}) => {
    const [todos, setTodos] = useState<Todo[]>([]);
    const [title, setTitle] = useState("");
    const [due, setDue] = useState("");
    const [editing, setEditing] = useState<string | null>(null);

    const reload = useCallback(() => {
        listTodos().then(setTodos).catch(onError);
    }, [onError]);

    useEffect(() => {
        if (!open) return;
        reload();
        const unlisten = onTodosChanged(reload);
        return () => {
            void unlisten.then((stop) => stop());
        };
    }, [open, reload]);

    const run = (action: Promise<unknown>) => {
        action.then(reload).catch(onError);
    };

    const add = () => {
        if (!title.trim()) return;
        run(
            createTodo(title, fromInputValue(due)).then(() => {
                setTitle("");
                setDue("");
            }),
        );
    };

    const open_ = todos
        .filter(isOpen)
        .sort(
            (a, b) =>
                (a.dueAtMs ?? Infinity) - (b.dueAtMs ?? Infinity) ||
                a.createdAtMs - b.createdAtMs,
        );
    const done = todos
        .filter((todo) => !isOpen(todo))
        .sort((a, b) => (b.completedAtMs ?? 0) - (a.completedAtMs ?? 0));

    return (
        <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
            <DialogTitle>To Do</DialogTitle>
            <DialogContent>
                <Stack direction="row" sx={{ gap: 1, mt: 1, mb: 2 }}>
                    <TextField
                        size="small"
                        label="New To Do"
                        value={title}
                        onChange={(event) => setTitle(event.target.value)}
                        onKeyDown={(event) => {
                            if (event.key === "Enter") add();
                        }}
                        sx={{ flex: 1 }}
                    />
                    <TextField
                        size="small"
                        type="datetime-local"
                        value={due}
                        onChange={(event) => setDue(event.target.value)}
                        slotProps={{ inputLabel: { shrink: true } }}
                        label="Due"
                    />
                    <Button onClick={add} disabled={!title.trim()}>
                        Add
                    </Button>
                </Stack>
                {todos.length === 0 && (
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        Nothing yet. Add one here, or ask in chat.
                    </Typography>
                )}
                {[...open_, ...done].map((todo) =>
                    editing === todo.id ? (
                        <TodoEditor
                            key={todo.id}
                            todo={todo}
                            onCancel={() => setEditing(null)}
                            onSave={(newTitle, newDue) =>
                                run(
                                    updateTodo(todo, newTitle, newDue).then(
                                        () => setEditing(null),
                                    ),
                                )
                            }
                        />
                    ) : (
                        <Stack
                            key={todo.id}
                            direction="row"
                            sx={{ alignItems: "center", gap: 1 }}
                        >
                            <Checkbox
                                checked={!isOpen(todo)}
                                onChange={(event) =>
                                    run(
                                        setTodoCompleted(
                                            todo,
                                            event.target.checked,
                                        ),
                                    )
                                }
                            />
                            <Box
                                sx={{ flex: 1, cursor: "pointer" }}
                                onClick={() => setEditing(todo.id)}
                            >
                                <Typography
                                    sx={{
                                        textDecoration: isOpen(todo)
                                            ? "none"
                                            : "line-through",
                                    }}
                                >
                                    {todo.title}
                                </Typography>
                                {todo.dueAtMs !== null && (
                                    <Typography
                                        variant="small"
                                        sx={{
                                            color:
                                                isOpen(todo) &&
                                                todo.dueAtMs < Date.now()
                                                    ? "critical.main"
                                                    : "text.muted",
                                        }}
                                    >
                                        {formatDue(todo.dueAtMs)}
                                    </Typography>
                                )}
                            </Box>
                            <IconButton
                                aria-label="Delete"
                                onClick={() => run(deleteTodo(todo))}
                            >
                                <HugeiconsIcon icon={Delete01Icon} size={18} />
                            </IconButton>
                        </Stack>
                    ),
                )}
            </DialogContent>
        </Dialog>
    );
};

interface TodoEditorProps {
    todo: Todo;
    onSave: (title: string, dueAtMs: number | null) => void;
    onCancel: () => void;
}

const TodoEditor: React.FC<TodoEditorProps> = ({ todo, onSave, onCancel }) => {
    const [title, setTitle] = useState(todo.title);
    const [due, setDue] = useState(toInputValue(todo.dueAtMs));
    return (
        <Stack direction="row" sx={{ gap: 1, my: 1, alignItems: "center" }}>
            <TextField
                size="small"
                value={title}
                autoFocus
                onChange={(event) => setTitle(event.target.value)}
                sx={{ flex: 1 }}
            />
            <TextField
                size="small"
                type="datetime-local"
                value={due}
                onChange={(event) => setDue(event.target.value)}
            />
            <Button
                disabled={!title.trim()}
                onClick={() => onSave(title, fromInputValue(due))}
            >
                Save
            </Button>
            <Button onClick={onCancel}>Cancel</Button>
        </Stack>
    );
};
