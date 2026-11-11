import Foundation

struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var displayName: String = ""
}

struct Household: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var inviteCode: String = ""
    var createdBy: UUID?
}

struct HouseholdMember: Codable, Identifiable, Hashable {
    var householdId: UUID
    var userId: UUID
    var role: String = "member"
    var displayName: String = ""
    var id: String { "\(householdId)-\(userId)" }
    var isOwner: Bool { role == "owner" }
}

struct Pet: Codable, Identifiable, Hashable {
    var id = UUID()
    var householdId: UUID
    var name: String = ""
    var species: Species = .dog
    var breed = ""
    var sex = ""
    @Nullable var birthdate: Day? = nil
    @Nullable var weight: Double? = nil
    var weightUnit = "lb"
    @Nullable var photoPath: String? = nil
    var notes = ""
    var microchip = ""
    var vetName = ""
    var vetClinic = ""
    var vetPhone = ""
    var vetAddress = ""
    var emergencyName = ""
    var emergencyPhone = ""

    var ageLabel: String? {
        guard let birthdate else { return nil }
        let c = Calendar.current.dateComponents([.year, .month], from: birthdate.date, to: .now)
        let years = c.year ?? 0, months = c.month ?? 0
        if years >= 1 { return years == 1 ? "1 year" : "\(years) years" }
        return months == 1 ? "1 month" : "\(max(months, 0)) months"
    }

    var weightLabel: String? {
        guard let weight else { return nil }
        return "\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(weightUnit)"
    }

    /// "Cat · Tabby · 4 years · 10 lb"
    var summaryLine: String {
        [species.label, breed.isEmpty ? nil : breed, ageLabel, weightLabel].compactMap { $0 }.joined(separator: " · ")
    }

    var hasVetInfo: Bool { !(vetName.isEmpty && vetClinic.isEmpty && vetPhone.isEmpty) }
    var hasEmergencyInfo: Bool { !(emergencyName.isEmpty && emergencyPhone.isEmpty) }
}

struct Routine: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    var category: CareCategory = .feeding
    var title = ""
    var details = ""
    var amount = ""
    @Nullable var timeOfDay: ClockTime? = nil
    var schedule: ScheduleKind = .daily
    var weekdays: [Int] = []
    @Nullable var intervalDays: Int? = nil
    var startDate: Day = .today
    @Nullable var endDate: Day? = nil
    @Nullable var medicationId: UUID? = nil
    var active = true
    /// Maintained by the server: the last day this was logged as done, by anyone.
    var lastDone: Day?

    /// "Every day · 8:00 AM", "Mon, Thu", "Every 30 days", "Once on Nov 20"
    var scheduleLabel: String {
        let time = timeOfDay.map { " · \($0.label)" } ?? ""
        switch schedule {
        case .daily:
            return "Every day" + time
        case .weekly:
            let symbols = Calendar.current.shortWeekdaySymbols
            let days = weekdays.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }
            return (days.isEmpty ? "No days chosen" : days.joined(separator: ", ")) + time
        case .interval:
            let n = intervalDays ?? 1
            let every = n % 7 == 0 && n >= 7 ? (n == 7 ? "Every week" : "Every \(n / 7) weeks") : "Every \(n) days"
            return every + time
        case .once:
            return "Once on \(startDate.shortLabel)" + time
        }
    }
}

struct CareLog: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    @Nullable var routineId: UUID? = nil
    var category: CareCategory = .other
    var title: String
    var scheduledFor: Day = .today
    var status = "done"
    var note = ""
    var loggedBy: UUID?
    var loggedByName = ""
    var loggedAt: Date = .now
    @Nullable var carePlanId: UUID? = nil

    var isDone: Bool { status == "done" }
    var isSkipped: Bool { status == "skipped" }
}

struct Allergy: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    var name = ""
    var severity = ""
    var notes = ""
}

struct Medication: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    var name = ""
    var dose = ""
    var frequency = ""
    var instructions = ""
    @Nullable var startDate: Day? = nil
    @Nullable var endDate: Day? = nil
    var active = true

    var summary: String { [dose, frequency].filter { !$0.isEmpty }.joined(separator: ", ") }
}

struct Vaccine: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    var name = ""
    @Nullable var dateGiven: Day? = nil
    @Nullable var dueDate: Day? = nil
    var notes = ""

    enum Status { case upToDate, dueSoon, overdue, unknown }

    var status: Status {
        guard let dueDate else { return dateGiven == nil ? .unknown : .upToDate }
        let days = Day.today.days(until: dueDate)
        if days < 0 { return .overdue }
        return days <= 30 ? .dueSoon : .upToDate
    }
}

struct WeightEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    var weight: Double
    var unit = "lb"
    var measuredOn: Day = .today
}

struct PetDocument: Codable, Identifiable, Hashable {
    var id = UUID()
    var petId: UUID
    var title = ""
    var kind = ""
    var storagePath: String
    var createdAt: Date?
}

struct CarePlan: Codable, Identifiable, Hashable {
    var id = UUID()
    var householdId: UUID
    var title = ""
    var caregiverLabel = ""
    var startDate: Day = .today
    var endDate: Day = Day.today.adding(2)
    var categories: [CareCategory] = []
    var notes = ""
    var emergencyNotes = ""
    var inviteCode: String?
    var status = "active"
    var sitterId: UUID?
    var sitterName: String?
    var createdBy: UUID?
    var createdByName = ""
    var acceptedAt: Date?

    enum Phase { case upcoming, current, ended, revoked }

    var phase: Phase {
        if status == "revoked" { return .revoked }
        let today = Day.today
        if today < startDate { return .upcoming }
        return today > endDate ? .ended : .current
    }

    var isAccepted: Bool { sitterId != nil }
    var dateRangeLabel: String { "\(startDate.shortLabel) – \(endDate.shortLabel)" }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !caregiverLabel.isEmpty { return "Care plan for \(caregiverLabel)" }
        return "Care plan"
    }

    /// The person the plan is for: their real name once they've joined, else the label the owner typed.
    var caregiverName: String {
        if let sitterName, !sitterName.isEmpty { return sitterName }
        return caregiverLabel.isEmpty ? "your sitter" : caregiverLabel
    }
}

/// Only the fields an owner edits, so saving a plan never overwrites who accepted it.
struct CarePlanEdit: Encodable {
    var title: String
    var caregiverLabel: String
    var startDate: Day
    var endDate: Day
    var categories: [CareCategory]
    var notes: String
    var emergencyNotes: String
}

struct CarePlanPet: Codable, Hashable, Identifiable {
    var carePlanId: UUID
    var petId: UUID
    var id: String { "\(carePlanId)-\(petId)" }
}
