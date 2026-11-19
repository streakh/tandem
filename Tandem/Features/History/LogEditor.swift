import SwiftUI

/// Add or change the note on something that's already been logged, or remove the entry.
struct LogEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var log: CareLog
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryIcon(category: log.category, size: 40, dimmed: log.isSkipped)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.title).font(.headline)
                            Text("\(log.isSkipped ? "Skipped" : (log.routineId == nil ? "Logged" : "Done")) by \(log.loggedByName.isEmpty ? "someone" : log.loggedByName) · \(log.loggedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Section("Note") {
                    TextField("e.g. \u{201C}ate about half\u{201D}", text: $log.note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                }
                Section {
                    Button("Delete entry", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text(log.routineId == nil ? "Removes this note from the shared history." : "Deleting puts the task back on the checklist as not done.")
                }
            }
            .themedForm()
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        log.note = log.note.trimmingCharacters(in: .whitespacesAndNewlines)
                        let log = log
                        Task {
                            if await store.save(log) {
                                store.track("note_edited")
                                dismiss()
                            }
                        }
                    }
                }
            }
            .alert("Delete this entry?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await store.undo(log); dismiss() } }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { focused = log.note.isEmpty }
        }
    }
}

extension AppStore {
    /// Household members can change any entry for their pets; a sitter can change their own.
    func canModify(_ log: CareLog) -> Bool {
        if log.loggedBy == userId { return true }
        guard let pet = pets.first(where: { $0.id == log.petId }) else { return false }
        return canEdit(pet)
    }
}
