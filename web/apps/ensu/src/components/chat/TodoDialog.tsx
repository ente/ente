import {
    createTodo,
    deleteTodo,
    formatDue,
    isOpen,
    listTodos,
    setTodoCompleted,
    updateTodo,
    watchTodos,
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
import React, { useEffect, useRef, useState } from "react";

interface TodoDialogProps {
    open: boolean;
    onClose: () => void;
    onError: (error: unknown) => void;
}

const toInputValue = (ms: number | null) => {
    if (ms === null) return "";
    const date = new Date(ms);
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const fromInputValue = (value: string) =>
    value ? new Date(value).getTime() : null;

export const TodoDialog: React.FC<TodoDialogProps> = ({
    open,
    onClose,
    onError,
}) => {
    const [todos, setTodos] = useState<Todo[]>([]);
    const [loaded, setLoaded] = useState(false);
    const [title, setTitle] = useState("");
    const [due, setDue] = useState("");
    const [editing, setEditing] = useState<{ id: string } | null>(null);

    const reload = useRef<(() => void) | undefined>(undefined);

    useEffect(() => {
        if (!open) {
            setEditing(null);
            return;
        }
        const watcher = watchTodos(
            listTodos,
            (latest) => {
                setTodos(latest);
                setLoaded(true);
            },
            onError,
        );
        reload.current = watcher.refresh;
        return () => {
            watcher.dispose();
            reload.current = undefined;
        };
    }, [open, onError]);

    const run = (action: Promise<unknown>) => {
        void action.then(
            () => reload.current?.(),
            (error: unknown) => {
                onError(error);
                reload.current?.();
            },
        );
    };

    const adding = useRef(false);
    const add = () => {
        if (!title.trim() || adding.current) return;
        adding.current = true;
        run(
            createTodo(title, fromInputValue(due))
                .then(() => {
                    setTitle("");
                    setDue("");
                })
                .finally(() => {
                    adding.current = false;
                }),
        );
    };

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
                            if (
                                event.key === "Enter" &&
                                !event.nativeEvent.isComposing
                            )
                                add();
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
                {loaded && todos.length === 0 && (
                    <Typography variant="small" sx={{ color: "text.muted" }}>
                        Nothing yet. Add one here, or ask in chat.
                    </Typography>
                )}
                {todos.map((todo) =>
                    editing?.id === todo.id ? (
                        <TodoEditor
                            key={todo.id}
                            todo={todo}
                            onCancel={() => setEditing(null)}
                            onSave={(newTitle, newDue) =>
                                run(
                                    updateTodo(todo, newTitle, newDue).then(
                                        () =>
                                            setEditing((current) =>
                                                current === editing
                                                    ? null
                                                    : current,
                                            ),
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
                                slotProps={{
                                    input: { "aria-label": todo.title },
                                }}
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
                                onClick={() => setEditing({ id: todo.id })}
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
                                aria-label={`Delete ${todo.title}`}
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
    const sameDue = due === toInputValue(todo.dueAtMs);
    const save = () => {
        if (title.trim() === todo.title && sameDue) onCancel();
        else onSave(title, sameDue ? todo.dueAtMs : fromInputValue(due));
    };
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
            <Button disabled={!title.trim()} onClick={save}>
                Save
            </Button>
            <Button onClick={onCancel}>Cancel</Button>
        </Stack>
    );
};
