import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: TodoStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var due: Date?
    @State private var editing: TodoItem?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                    composer

                    if store.todos.isEmpty {
                        Text("Nothing yet. Add one here, or ask in chat.")
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, EnsuSpacing.lg)
                    } else {
                        VStack(spacing: EnsuSpacing.sm) {
                            ForEach(store.todos) { todo in
                                row(todo)
                            }
                        }
                    }
                }
                .padding(EnsuSpacing.lg)
            }
            .background(EnsuColor.backgroundBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("To Do")
                        .font(EnsuTypography.large)
                        .foregroundStyle(EnsuColor.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $editing) { todo in
                TodoEditorSheet(todo: todo) { title, due in
                    if store.update(todo, title: title, due: due) { return nil }
                    defer { store.errorMessage = nil }
                    return store.errorMessage ?? "Couldn’t save"
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    ToastView(message: toastMessage)
                        .padding(.bottom, EnsuSpacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear { store.reload() }
        .onChange(of: store.errorMessage) { message in
            guard let message else { return }
            store.errorMessage = nil
            toastTask?.cancel()
            toastTask = presentToast(message, setToastMessage: { toastMessage = $0 }, duration: 2)
        }
    }

    private var composer: some View {
        EnsuCard(padding: EnsuSpacing.md) {
            TextField("New To Do", text: $title)
                .font(EnsuTypography.body)
                .foregroundStyle(EnsuColor.textPrimary)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.vertical, EnsuSpacing.xs)

            HStack(spacing: EnsuSpacing.sm) {
                TodoDueField(due: $due)
                Spacer(minLength: 0)
                CompactButton(text: "Add", action: add)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        HStack(spacing: EnsuSpacing.md) {
            Button {
                hapticTap()
                store.setCompleted(todo, !todo.isDone)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(todo.isDone ? EnsuColor.action : EnsuColor.textMuted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(EnsuTypography.body)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? EnsuColor.textMuted : EnsuColor.textPrimary)
                if let dueDate = todo.dueDate {
                    Text(formatDue(dueDate))
                        .font(EnsuTypography.small)
                        .foregroundStyle(
                            !todo.isDone && dueDate < Date() ? EnsuColor.error : EnsuColor.textMuted
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                hapticTap()
                editing = todo
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit")

            ActionButton(icon: "Delete01Icon", tooltip: "Delete", color: EnsuColor.textMuted) {
                store.delete(todo)
            }
        }
        .padding(.vertical, EnsuSpacing.sm)
        .padding(.horizontal, EnsuSpacing.sm)
        .background(EnsuColor.fillFaint)
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))
    }

    private func add() {
        guard !trimmedTitle.isEmpty else { return }
        if store.add(title: trimmedTitle, due: due) {
            title = ""
            due = nil
        }
    }

    private func formatDue(_ date: Date) -> String {
        let format = Date.FormatStyle.dateTime
            .weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return date.formatted(thisYear ? format : format.year())
    }
}

private struct TodoDueField: View {
    @Binding var due: Date?

    var body: some View {
        if let value = due {
            HStack(spacing: 0) {
                DatePicker(
                    "Due",
                    selection: Binding(get: { value }, set: { due = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                ActionButton(icon: "Cancel01Icon", tooltip: "Remove due date", size: 32) {
                    due = nil
                }
            }
        } else {
            TextActionButton(text: "Add due date") {
                due = Self.nextHour()
            }
        }
    }

    private static func nextHour() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
    }
}

private struct TodoEditorSheet: View {
    let todo: TodoItem
    let onSave: (String, Date?) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var due: Date?
    @State private var error: String?

    init(todo: TodoItem, onSave: @escaping (String, Date?) -> String?) {
        self.todo = todo
        self.onSave = onSave
        _title = State(initialValue: todo.title)
        _due = State(initialValue: todo.dueDate)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                TextField("Title", text: $title)
                    .font(EnsuTypography.body)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .padding(.horizontal, EnsuSpacing.inputHorizontal)
                    .padding(.vertical, EnsuSpacing.inputVertical)
                    .background(EnsuColor.fillFaint)
                    .clipShape(
                        RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous))

                TodoDueField(due: $due)
                if let error {
                    Text(error)
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.error)
                }
                Spacer(minLength: 0)
            }
            .padding(EnsuSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(EnsuColor.backgroundBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit To Do")
                        .font(EnsuTypography.large)
                        .foregroundStyle(EnsuColor.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        error = onSave(trimmedTitle, due)
        if error == nil {
            dismiss()
        }
    }
}
