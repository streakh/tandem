import SwiftUI

/// Everything that isn't part of the daily rhythm: occasional tasks and vaccines, soonest first.
struct UpcomingView: View {
    @Environment(AppStore.self) private var store
    let petId: UUID
    @State private var editingRoutine: Routine?
    @State private var editingVaccine: Vaccine?

    private struct Row: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let category: CareCategory
        let day: Day
        let routine: Routine?
        let vaccine: Vaccine?
    }

    private enum Bucket: Int, CaseIterable, Identifiable {
        case overdue, thisWeek, thisMonth, later
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .overdue: "Due now"
            case .thisWeek: "Next 7 days"
            case .thisMonth: "Next 30 days"
            case .later: "Later"
            }
        }

        static func of(_ day: Day) -> Bucket {
            let n = Day.today.days(until: day)
            if n <= 0 { return .overdue }
            if n <= 7 { return .thisWeek }
            return n <= 30 ? .thisMonth : .later
        }
    }

    private var pet: Pet? { store.pets.first { $0.id == petId } }

    private var rows: [Row] {
        var result: [Row] = []
        // Occasional tasks that are already due sit on Today; list them here too so nothing is hidden.
        for task in store.tasks(for: petId) where !task.isResolved && task.routine.schedule != .daily && task.routine.schedule != .weekly {
            result.append(Row(id: "due-\(task.id)", title: task.routine.title, subtitle: task.routine.scheduleLabel,
                              category: task.routine.category, day: task.dueDay, routine: task.routine, vaccine: nil))
        }
        for item in Schedule.upcoming(petIds: [petId], routines: store.routines, logs: store.logs, vaccines: store.vaccines, horizon: 365) {
            switch item.kind {
            case .routine(let routine):
                result.append(Row(id: item.id, title: routine.title, subtitle: routine.scheduleLabel, category: routine.category,
                                  day: item.day, routine: routine, vaccine: nil))
            case .vaccine(let vaccine):
                result.append(Row(id: item.id, title: "\(vaccine.name) vaccine",
                                  subtitle: vaccine.dateGiven.map { "Last given \($0.longLabel)" } ?? "Vaccine",
                                  category: .vet, day: item.day, routine: nil, vaccine: vaccine))
            }
        }
        return result.sorted { $0.day < $1.day }
    }

    var body: some View {
        let rows = rows
        let canEdit = pet.map { store.canEdit($0) } ?? false

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if rows.isEmpty {
                    EmptyState(icon: "calendar", title: "Nothing coming up",
                               message: "Tasks that don't happen every day, like a monthly flea treatment or a nail trim, and vaccines with a due date show up here.")
                        .padding(.top, 40)
                }
                ForEach(Bucket.allCases) { bucket in
                    let group = rows.filter { Bucket.of($0.day) == bucket }
                    if !group.isEmpty {
                        SectionTitle(bucket.title)
                        VStack(spacing: 0) {
                            ForEach(Array(group.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { Divider().padding(.leading, 56) }
                                Button {
                                    guard canEdit else { return }
                                    editingRoutine = row.routine
                                    editingVaccine = row.vaccine
                                } label: {
                                    HStack(spacing: 12) {
                                        CategoryIcon(category: row.category, size: 40)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.title).font(.headline).foregroundStyle(Theme.text)
                                            Text(row.subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                        }
                                        Spacer(minLength: 8)
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(dateLabel(row.day, bucket: bucket))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(bucket == .overdue ? Theme.danger : Theme.text)
                                            if bucket != .overdue {
                                                Text(countdown(row.day)).font(.caption).foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card(padding: 14)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Coming up for \(pet?.name ?? "pet")")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0, isNew: false) }
        .sheet(item: $editingVaccine) { VaccineEditor(vaccine: $0) }
    }

    private func dateLabel(_ day: Day, bucket: Bucket) -> String {
        guard bucket == .overdue else { return day.relativeLabel }
        let n = day.days(until: .today)
        if n == 0 { return "Due today" }
        return n == 1 ? "Due yesterday" : "\(n) days overdue"
    }

    private func countdown(_ day: Day) -> String {
        let n = Day.today.days(until: day)
        if n < 14 { return n == 1 ? "in 1 day" : "in \(n) days" }
        if n < 60 { return "in \(n / 7) weeks" }
        return "in \(n / 30) months"
    }
}
