import Foundation

/// One routine on one day, joined with whatever has been logged for it.
struct CareTask: Identifiable, Hashable {
    let routine: Routine
    let day: Day
    /// The day it actually came due (earlier than `day` when an occasional task is overdue).
    let dueDay: Day
    let log: CareLog?

    var id: String { "\(routine.id)-\(day.string)" }
    var isDone: Bool { log?.isDone == true }
    var isSkipped: Bool { log?.isSkipped == true }
    var isResolved: Bool { log != nil }

    enum State { case done, skipped, overdue, dueNow, upcoming, anytime }

    func state(now: Date = .now) -> State {
        if isDone { return .done }
        if isSkipped { return .skipped }
        if dueDay < day { return .overdue }
        guard let time = routine.timeOfDay else { return .anytime }
        let due = time.date(on: day)
        if now < due { return .upcoming }
        return now.timeIntervalSince(due) > 2 * 3600 ? .overdue : .dueNow
    }

    func statusLine(now: Date = .now) -> String {
        if let log {
            let who = log.loggedByName.isEmpty ? "someone" : log.loggedByName
            let time = log.loggedAt.formatted(date: .omitted, time: .shortened)
            return log.isDone ? "Done by \(who), \(time)" : "Skipped by \(who), \(time)"
        }
        switch state(now: now) {
        case .overdue:
            if dueDay < day {
                let n = dueDay.days(until: day)
                return n == 1 ? "Overdue since yesterday" : "Overdue by \(n) days"
            }
            return "Overdue · was due \(routine.timeOfDay?.label ?? "")"
        case .dueNow: return "Due now · \(routine.timeOfDay?.label ?? "")"
        case .upcoming: return "Due at \(routine.timeOfDay?.label ?? "")"
        default: return "Any time today"
        }
    }

    enum Slot: Int, CaseIterable, Identifiable {
        case morning, afternoon, evening, anytime
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .evening: "Evening"
            case .anytime: "Any time"
            }
        }
    }

    var slot: Slot {
        guard let t = routine.timeOfDay else { return .anytime }
        if t.hour < 12 { return .morning }
        return t.hour < 17 ? .afternoon : .evening
    }
}

/// Something that isn't part of the daily rhythm but is coming up: an occasional task or a vaccine.
struct UpcomingItem: Identifiable, Hashable {
    enum Kind: Hashable { case routine(Routine), vaccine(Vaccine) }
    let kind: Kind
    let day: Day
    let petId: UUID

    var id: String {
        switch kind {
        case .routine(let r): "r-\(r.id)-\(day.string)"
        case .vaccine(let v): "v-\(v.id)"
        }
    }

    var title: String {
        switch kind {
        case .routine(let r): r.title
        case .vaccine(let v): "\(v.name) vaccine"
        }
    }

    var category: CareCategory {
        switch kind {
        case .routine(let r): r.category
        case .vaccine: .vet
        }
    }
}

enum Schedule {
    /// The tasks a pet has on `day`, in time order.
    static func tasks(petId: UUID, on day: Day, routines: [Routine], logs: [CareLog]) -> [CareTask] {
        var result: [CareTask] = []
        for routine in routines where routine.petId == petId && routine.active {
            let todaysLog = logs.first { $0.routineId == routine.id && $0.scheduledFor == day }
            var dueDay: Day?

            switch routine.schedule {
            case .daily:
                if inWindow(routine, day) { dueDay = day }
            case .weekly:
                if inWindow(routine, day), routine.weekdays.contains(day.weekday) { dueDay = day }
            case .interval:
                if todaysLog != nil {
                    dueDay = day
                } else if routine.endDate.map({ day <= $0 }) ?? true {
                    let next = nextIntervalDue(routine)
                    if next <= day { dueDay = next }
                }
            case .once:
                if todaysLog != nil {
                    dueDay = day
                } else if routine.lastDone == nil, routine.startDate <= day {
                    dueDay = routine.startDate
                }
            }

            if let dueDay {
                result.append(CareTask(routine: routine, day: day, dueDay: dueDay, log: todaysLog))
            }
        }
        return result.sorted { a, b in
            switch (a.routine.timeOfDay, b.routine.timeOfDay) {
            case let (x?, y?): return x == y ? a.routine.title < b.routine.title : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.routine.title < b.routine.title
            }
        }
    }

    /// Occasional tasks and vaccines due after today, within `horizon` days. Overdue vaccines are included.
    static func upcoming(petIds: Set<UUID>, routines: [Routine], logs: [CareLog], vaccines: [Vaccine], horizon: Int = 60) -> [UpcomingItem] {
        let today = Day.today
        let limit = today.adding(horizon)
        var items: [UpcomingItem] = []

        for routine in routines where petIds.contains(routine.petId) && routine.active {
            var next: Day?
            switch routine.schedule {
            case .daily:
                break
            case .weekly:
                next = (1...7).map { today.adding($0) }.first { routine.weekdays.contains($0.weekday) && inWindow(routine, $0) }
            case .interval:
                let due = nextIntervalDue(routine)
                if due > today { next = due }
            case .once:
                if routine.lastDone == nil, routine.startDate > today { next = routine.startDate }
            }
            if let next, next <= limit, routine.endDate.map({ next <= $0 }) ?? true {
                items.append(UpcomingItem(kind: .routine(routine), day: next, petId: routine.petId))
            }
        }

        for vaccine in vaccines where petIds.contains(vaccine.petId) {
            if let due = vaccine.dueDate, due <= limit {
                items.append(UpcomingItem(kind: .vaccine(vaccine), day: due, petId: vaccine.petId))
            }
        }
        return items.sorted { $0.day < $1.day }
    }

    private static func inWindow(_ routine: Routine, _ day: Day) -> Bool {
        if day < routine.startDate { return false }
        if let end = routine.endDate, day > end { return false }
        return true
    }

    /// Occasional tasks count from the last time they were actually done, so a late flea treatment pushes the next one back.
    private static func nextIntervalDue(_ routine: Routine) -> Day {
        guard let last = routine.lastDone else { return routine.startDate }
        return last.adding(max(routine.intervalDays ?? 1, 1))
    }
}

/// Starter routines offered when a pet is first added, so owners set things up once without typing.
struct RoutineTemplate: Identifiable, Hashable {
    let id = UUID()
    let category: CareCategory
    let title: String
    let time: ClockTime?
    var schedule: ScheduleKind = .daily
    var intervalDays: Int? = nil

    func routine(petId: UUID) -> Routine {
        Routine(petId: petId, category: category, title: title, timeOfDay: time, schedule: schedule, intervalDays: intervalDays)
    }

    static func suggestions(for species: Species) -> [RoutineTemplate] {
        let breakfast = RoutineTemplate(category: .feeding, title: "Breakfast", time: ClockTime(hour: 8))
        let dinner = RoutineTemplate(category: .feeding, title: "Dinner", time: ClockTime(hour: 18))
        let water = RoutineTemplate(category: .water, title: "Fresh water", time: ClockTime(hour: 8))
        switch species {
        case .dog:
            return [breakfast, dinner, water,
                    RoutineTemplate(category: .walk, title: "Morning walk", time: ClockTime(hour: 7, minute: 30)),
                    RoutineTemplate(category: .walk, title: "Evening walk", time: ClockTime(hour: 18, minute: 30)),
                    RoutineTemplate(category: .grooming, title: "Brush coat", time: nil, schedule: .interval, intervalDays: 7)]
        case .cat:
            return [breakfast, dinner, water,
                    RoutineTemplate(category: .cleaning, title: "Scoop litter box", time: ClockTime(hour: 19)),
                    RoutineTemplate(category: .play, title: "Play time", time: nil),
                    RoutineTemplate(category: .cleaning, title: "Change litter", time: nil, schedule: .interval, intervalDays: 7)]
        case .bird, .rabbit, .smallPet, .reptile:
            return [RoutineTemplate(category: .feeding, title: "Feeding", time: ClockTime(hour: 8)), water,
                    RoutineTemplate(category: .cleaning, title: "Spot-clean habitat", time: ClockTime(hour: 19)),
                    RoutineTemplate(category: .cleaning, title: "Deep-clean habitat", time: nil, schedule: .interval, intervalDays: 7)]
        case .fish:
            return [RoutineTemplate(category: .feeding, title: "Feeding", time: ClockTime(hour: 8)),
                    RoutineTemplate(category: .cleaning, title: "Water change", time: nil, schedule: .interval, intervalDays: 14)]
        case .horse:
            return [RoutineTemplate(category: .feeding, title: "Morning feed", time: ClockTime(hour: 7)),
                    RoutineTemplate(category: .feeding, title: "Evening feed", time: ClockTime(hour: 17)), water,
                    RoutineTemplate(category: .cleaning, title: "Muck out stall", time: ClockTime(hour: 9)),
                    RoutineTemplate(category: .grooming, title: "Groom", time: nil)]
        case .other:
            return [breakfast, dinner, water]
        }
    }
}
