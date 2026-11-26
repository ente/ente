import Foundation

extension TodoItem: Identifiable {}

extension TodoItem {
    var isDone: Bool { completedAtMs != nil }
    var dueDate: Date? { dueAtMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
}

extension RefusalReason {
    var message: String {
        switch self {
        case .todoChanged:
            "This To Do changed or was deleted. Check the list; close and reopen the editor if it’s open."
        case .titleMissing: "A To Do needs a title."
        case let .titleTooLong(max): "A To Do title can have at most \(max) characters."
        case .undoStale: "These To Dos changed since, so this can’t be undone."
        case .offerStale:
            "This offer is out of date because your To Dos changed since. Ask again to update them."
        case .earlierReplyStands:
            "An earlier reply to this message changed your To Dos. Undo it first."
        case .nothingOffered: "This reply didn’t offer any changes."
        case .nothingChanged: "This reply didn’t change any To Dos."
        }
    }
}

func todoErrorMessage(_ error: Error) -> String {
    if case let DbError.Refused(reason, _) = error {
        return reason.message
    }
    if case let DbError.Other(detail) = error, !detail.isEmpty {
        return detail
    }
    return "Try again."
}

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []
    @Published var errorMessage: String?

    private let db: () -> EnsuDb?
    private let logger = EnsuLogging.shared.logger("TodoStore")

    init(db: @escaping () -> EnsuDb?) {
        self.db = db
    }

    func reload() {
        run { _ in }
    }

    @discardableResult
    func add(title: String, due: Date?) -> Bool {
        run { _ = try $0.createTodo(title: title, dueAtMs: due.map(Self.milliseconds)) }
    }

    @discardableResult
    func update(_ todo: TodoItem, title: String, due: Date?) -> Bool {
        run {
            _ = try $0.updateTodo(
                id: todo.id, version: todo.version, title: title,
                dueAtMs: due.map(Self.milliseconds))
        }
    }

    func setCompleted(_ todo: TodoItem, _ completed: Bool) {
        run {
            _ = try $0.setTodoCompleted(id: todo.id, version: todo.version, completed: completed)
        }
    }

    func delete(_ todo: TodoItem) {
        run { try $0.deleteTodo(id: todo.id, version: todo.version) }
    }

    @discardableResult
    private func run(_ change: (EnsuDb) throws -> Void) -> Bool {
        guard let db = db() else { return false }
        do {
            try change(db)
            todos = try db.listTodos()
            return true
        } catch {
            logger.error("To Do change failed", error)
            errorMessage = todoErrorMessage(error)
            if let current = try? db.listTodos() {
                todos = current
            }
            return false
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

final class ToolsWatcher: ToolsObserver {
    private let changed: @Sendable () -> Void

    init(_ changed: @escaping @Sendable () -> Void) {
        self.changed = changed
    }

    func onChange() {
        changed()
    }
}
