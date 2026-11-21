import SwiftUI

/// Two weeks at a glance: one row per regular task, one dot per day. A missed dose stands out
/// without reading the list underneath.
struct ConsistencyGrid: View {
    @Environment(AppStore.self) private var store
    let petId: UUID
    var dayCount = 14

    private enum Mark { case done, skipped, missed, pending, none }

    private struct Row: Identifiable {
        let routine: Routine
        let marks: [Mark]
        var id: UUID { routine.id }
    }

    /// A sitter can only see history from their own plan, so earlier days are left blank rather than shown as missed.
    private var firstKnownDay: Day {
        let windowStart = Day.today.adding(-(dayCount - 1))
        guard let pet = store.pets.first(where: { $0.id == petId }), !store.canEdit(pet),
              let plan = store.sitterPlan(for: petId) else { return windowStart }
        return max(windowStart, plan.startDate)
    }

    private var rows: [Row] {
        let today = Day.today
        let days = (0..<dayCount).map { today.adding($0 - (dayCount - 1)) }
        let logs = store.logs.filter { $0.petId == petId }
        let known = firstKnownDay

        return store.routines
            .filter { $0.petId == petId && $0.active && ($0.schedule == .daily || $0.schedule == .weekly) }
            .sorted { ($0.timeOfDay ?? ClockTime(hour: 24)) < ($1.timeOfDay ?? ClockTime(hour: 24)) }
            .map { routine in
                let marks: [Mark] = days.map { day in
                    guard day >= known,
                          let task = Schedule.tasks(petId: petId, on: day, routines: [routine], logs: logs).first else { return .none }
                    if task.isDone { return .done }
                    if task.isSkipped { return .skipped }
                    return day == today ? .pending : .missed
                }
                return Row(routine: routine, marks: marks)
            }
    }

    var body: some View {
        let rows = rows
        let missed = rows.reduce(0) { $0 + $1.marks.filter { $0 == .missed }.count }

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last two weeks").font(.headline).foregroundStyle(Theme.text)
                    Text(missed == 0 ? "Nothing missed." : (missed == 1 ? "1 task was missed." : "\(missed) tasks were missed."))
                        .font(.subheadline)
                        .foregroundStyle(missed == 0 ? Theme.textSecondary : Theme.warning)
                }

                VStack(spacing: 9) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Text(row.routine.title)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: gap) {
                                ForEach(Array(row.marks.enumerated()), id: \.offset) { _, mark in
                                    dot(mark)
                                }
                            }
                            .frame(width: dotsWidth)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(summary(row))
                    }
                    HStack {
                        Spacer(minLength: 0)
                        HStack {
                            Text(Day.today.adding(-(dayCount - 1)).shortLabel)
                            Spacer()
                            Text("Today")
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: dotsWidth)
                    }
                }

                HStack(spacing: 14) {
                    legend(.done, "Done")
                    legend(.skipped, "Skipped")
                    legend(.missed, "Missed")
                }
            }
            .card()
        }
    }

    private let size: CGFloat = 11
    private let gap: CGFloat = 4
    private var dotsWidth: CGFloat { CGFloat(dayCount) * size + CGFloat(dayCount - 1) * gap }

    @ViewBuilder
    private func dot(_ mark: Mark) -> some View {
        switch mark {
        case .done:
            Circle().fill(Theme.primary).frame(width: size, height: size)
        case .skipped:
            Capsule().fill(Theme.textSecondary.opacity(0.55)).frame(width: size, height: 4).frame(height: size)
        case .missed:
            Circle().strokeBorder(Theme.warning, lineWidth: 2).frame(width: size, height: size)
        case .pending:
            Circle().strokeBorder(Theme.separator, lineWidth: 2).frame(width: size, height: size)
        case .none:
            Circle().fill(Theme.separator.opacity(0.6)).frame(width: 4, height: 4).frame(width: size, height: size)
        }
    }

    private func legend(_ mark: Mark, _ label: String) -> some View {
        HStack(spacing: 5) {
            dot(mark)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func summary(_ row: Row) -> String {
        let done = row.marks.filter { $0 == .done }.count
        let missed = row.marks.filter { $0 == .missed }.count
        let skipped = row.marks.filter { $0 == .skipped }.count
        return "\(row.routine.title): done \(done) days, missed \(missed), skipped \(skipped)"
    }
}
