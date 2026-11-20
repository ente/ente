package io.ente.ensu.todo

import io.ente.ensu.bindings.DbException
import io.ente.ensu.bindings.RefusalReason
import io.ente.ensu.bindings.TodoItem
import io.ente.ensu.chat.ChatRepository
import io.ente.ensu.coroutines.runCatchingCancellable
import io.ente.ensu.logging.FileLogRepository
import io.ente.ensu.logging.LogLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class TodoState(
    val todos: List<TodoItem> = emptyList(),
    val loaded: Boolean = false,
    val error: String? = null,
)

internal fun RefusalReason.message(): String =
    when (this) {
        is RefusalReason.TodoChanged ->
            "This To Do changed or was deleted. Check the list; close and reopen the editor if it's open."
        is RefusalReason.TitleMissing -> "A To Do needs a title."
        is RefusalReason.TitleTooLong -> "A To Do title can have at most $max characters."
        is RefusalReason.UndoStale -> "These To Dos changed since, so this can't be undone."
        is RefusalReason.OfferStale ->
            "This offer is out of date because your To Dos changed since. Ask again to update them."
        is RefusalReason.EarlierReplyStands ->
            "An earlier reply to this message changed your To Dos. Undo it first."
        is RefusalReason.NothingOffered -> "This reply didn't offer any changes."
        is RefusalReason.NothingChanged -> "This reply didn't change any To Dos."
    }

internal fun Throwable.todoErrorDetail(): String? {
    val said =
        when (this) {
            is DbException.Refused -> reason.message()
            is DbException.Other -> detail
            else -> message
        }
    return said?.takeIf { it.isNotBlank() }
}

val TodoItem.isOpen: Boolean
    get() = completedAtMs == null

class TodoStore(
    private val chatRepository: ChatRepository,
    private val logRepository: FileLogRepository,
) {
    private val _state = MutableStateFlow(TodoState())
    val state: StateFlow<TodoState> = _state.asStateFlow()
    private var scope: CoroutineScope? = null

    private val changeLock = Mutex()

    fun bootstrap(scope: CoroutineScope) {
        this.scope = scope
    }

    fun reload() = perform("Failed to load To Dos") {}

    fun create(title: String, dueAtMs: Long?, onDone: (Boolean) -> Unit) =
        perform("Failed to add To Do", onDone = onDone) {
            chatRepository.createTodo(title.trim(), dueAtMs)
        }

    fun update(todo: TodoItem, title: String, dueAtMs: Long?, onDone: (Boolean) -> Unit) =
        perform("Failed to update To Do", onDone = onDone) {
            chatRepository.updateTodo(todo, title.trim(), dueAtMs)
        }

    fun setCompleted(todo: TodoItem, completed: Boolean) =
        perform("Failed to update To Do") {
            chatRepository.setTodoCompleted(shown(todo), completed)
        }

    fun delete(todo: TodoItem) =
        perform("Failed to delete To Do") { chatRepository.deleteTodo(shown(todo)) }

    private fun shown(todo: TodoItem): TodoItem =
        _state.value.todos.firstOrNull { it.id == todo.id } ?: todo

    fun dismissError() {
        _state.update { it.copy(error = null) }
    }

    private fun perform(
        failure: String,
        onDone: (Boolean) -> Unit = {},
        action: () -> Unit,
    ) {
        val scope = scope ?: return
        scope.launch { changeLock.withLock { performLocked(failure, onDone, action) } }
    }

    private suspend fun performLocked(
        failure: String,
        onDone: (Boolean) -> Unit,
        action: () -> Unit,
    ) {
        val result =
            withContext(Dispatchers.IO) {
                runCatchingCancellable {
                    action()
                    chatRepository.listTodos()
                }
            }
        result
            .onSuccess { todos ->
                _state.update { it.copy(todos = todos, loaded = true, error = null) }
                onDone(true)
            }
            .onFailure { error ->
                logRepository.log(
                    LogLevel.Warning,
                    failure,
                    details = error.message,
                    tag = "Todo",
                    throwable = error,
                )
                _state.update {
                    it.copy(
                        loaded = true,
                        error = error.todoErrorDetail() ?: failure,
                    )
                }
                val latest = runCatchingCancellable {
                    withContext(Dispatchers.IO) { chatRepository.listTodos() }
                }
                latest.onSuccess { todos -> _state.update { it.copy(todos = todos) } }
                onDone(false)
            }
    }
}
