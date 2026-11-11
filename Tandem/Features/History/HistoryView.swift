import SwiftUI

/// The shared record: who did what, and when.
struct HistoryView: View {
    @Environment(AppStore.self) private var store
    let petId: UUID
    @State private var category: CareCategory?
    @State private var person: String?

    private var pet: Pet? { store.pets.first { $0.id == petId } }
    private var all: [CareLog] { store.logs.filter { $0.petId == petId } }

    private var filtered: [CareLog] {
        all.filter { (category == nil || $0.category == category) && (person == nil || $0.loggedByName == person) }
    }

    var body: some View {
        let people = Array(Set(all.map(\.loggedByName))).filter { !$0.isEmpty }.sorted()
        let categories = CareCategory.allCases.filter { c in all.contains { $0.category == c } }
        let days = Dictionary(grouping: filtered, by: \.scheduledFor).sorted { $0.key > $1.key }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !all.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "All", isOn: category == nil && person == nil) { category = nil; person = nil }
                            ForEach(categories) { c in
                                FilterChip(label: c.label, icon: c.icon, isOn: category == c) { category = category == c ? nil : c }
                            }
                            if people.count > 1 {
                                ForEach(people, id: \.self) { p in
                                    FilterChip(label: p, icon: "person.fill", isOn: person == p) { person = person == p ? nil : p }
                                }
                            }
                        }
                    }
                }

                if filtered.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "Nothing logged yet",
                               message: "As tasks get checked off, they'll show up here with who did them and when.")
                        .padding(.top, 40)
                }

                ForEach(days, id: \.key) { day, logs in
                    SectionTitle(day.relativeLabel)
                    VStack(spacing: 0) {
                        ForEach(Array(logs.sorted { $0.loggedAt > $1.loggedAt }.enumerated()), id: \.element.id) { index, log in
                            if index > 0 { Divider().padding(.leading, 52) }
                            LogRow(log: log)
                                .contextMenu {
                                    if let pet, store.canEdit(pet) || log.loggedBy == store.userId {
                                        Button("Delete entry", systemImage: "trash", role: .destructive) {
                                            Task { await store.delete(log) }
                                        }
                                    }
                                }
                        }
                    }
                    .card(padding: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("\(pet?.name ?? "Pet")'s history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LogRow: View {
    let log: CareLog

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(category: log.category, size: 36, dimmed: log.isSkipped)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(log.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).strikethrough(log.isSkipped)
                    if log.isSkipped { Pill(text: "Skipped", color: Theme.textSecondary, soft: Theme.surfaceMuted) }
                }
                if !log.note.isEmpty { Text(log.note).font(.subheadline).foregroundStyle(Theme.text) }
                Text("\(log.loggedByName.isEmpty ? "Someone" : log.loggedByName) · \(log.loggedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

struct FilterChip: View {
    let label: String
    var icon: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.caption) }
                Text(label).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isOn ? .white : Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? Theme.primary : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
