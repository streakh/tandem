import Foundation
import SwiftUI

/// A calendar day ("2026-11-11"), matching Postgres `date`. Always interpreted in the device's time zone.
struct Day: Codable, Hashable, Comparable, Identifiable {
    let string: String
    var id: String { string }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(_ date: Date = .now) { string = Self.formatter.string(from: date) }
    init(string: String) { self.string = string }

    init(from decoder: Decoder) throws {
        string = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    static var today: Day { Day() }
    var date: Date { Self.formatter.date(from: string) ?? .now }

    func adding(_ days: Int) -> Day {
        Day(Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    func days(until other: Day) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    /// Calendar weekday, 1 = Sunday … 7 = Saturday.
    var weekday: Int { Calendar.current.component(.weekday, from: date) }

    static func < (a: Day, b: Day) -> Bool { a.string < b.string }

    /// "Today", "Tomorrow", "Yesterday", or "Mon, Nov 16".
    var relativeLabel: String {
        switch Day.today.days(until: self) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }

    var shortLabel: String { date.formatted(.dateTime.month(.abbreviated).day()) }
    var longLabel: String { date.formatted(.dateTime.month(.abbreviated).day().year()) }
}

/// A wall-clock time ("08:00:00"), matching Postgres `time`.
struct ClockTime: Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int = 0) { self.hour = hour; self.minute = minute }

    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = c.hour ?? 8
        minute = c.minute ?? 0
    }

    init(from decoder: Decoder) throws {
        let parts = try decoder.singleValueContainer().decode(String.self).split(separator: ":")
        hour = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%02d:%02d:00", hour, minute))
    }

    func date(on day: Day) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day.date) ?? day.date
    }

    var label: String { date(on: .today).formatted(date: .omitted, time: .shortened) }
    static func < (a: ClockTime, b: ClockTime) -> Bool { (a.hour, a.minute) < (b.hour, b.minute) }
}

/// Optional that encodes as an explicit JSON `null`, so a field can be cleared on the server.
@propertyWrapper
struct Nullable<T: Codable & Hashable>: Codable, Hashable {
    var wrappedValue: T?
    init(wrappedValue: T?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = c.decodeNil() ? nil : try c.decode(T.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let wrappedValue { try c.encode(wrappedValue) } else { try c.encodeNil() }
    }
}

extension KeyedDecodingContainer {
    func decode<T>(_ type: Nullable<T>.Type, forKey key: Key) throws -> Nullable<T> {
        try decodeIfPresent(type, forKey: key) ?? Nullable(wrappedValue: nil)
    }
}

enum Species: String, Codable, CaseIterable, Identifiable {
    case dog, cat, bird, rabbit, smallPet = "small_pet", fish, reptile, horse, other
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = Species(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }

    var label: String {
        switch self {
        case .dog: "Dog"
        case .cat: "Cat"
        case .bird: "Bird"
        case .rabbit: "Rabbit"
        case .smallPet: "Small pet"
        case .fish: "Fish"
        case .reptile: "Reptile"
        case .horse: "Horse"
        case .other: "Other"
        }
    }

    var emoji: String {
        switch self {
        case .dog: "🐶"
        case .cat: "🐱"
        case .bird: "🦜"
        case .rabbit: "🐰"
        case .smallPet: "🐹"
        case .fish: "🐠"
        case .reptile: "🦎"
        case .horse: "🐴"
        case .other: "🐾"
        }
    }
}

enum CareCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case feeding, water, walk, medication, cleaning, grooming, play, vet, other
    /// Free-form observation that isn't tied to a routine ("threw up after breakfast").
    case note
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = CareCategory(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }

    /// Categories a routine task can have.
    static let routineCases: [CareCategory] = [.feeding, .water, .walk, .medication, .cleaning, .grooming, .play, .vet, .other]

    var label: String {
        switch self {
        case .feeding: "Feeding"
        case .water: "Water"
        case .walk: "Walks"
        case .medication: "Medication"
        case .cleaning: "Cleaning"
        case .grooming: "Grooming"
        case .play: "Play & exercise"
        case .vet: "Vet"
        case .other: "Other"
        case .note: "Note"
        }
    }

    var icon: String {
        switch self {
        case .feeding: "fork.knife"
        case .water: "drop.fill"
        case .walk: "figure.walk"
        case .medication: "pills.fill"
        case .cleaning: "sparkles"
        case .grooming: "comb.fill"
        case .play: "tennisball.fill"
        case .vet: "cross.case.fill"
        case .other: "pawprint.fill"
        case .note: "note.text"
        }
    }

    var tint: Color {
        switch self {
        case .feeding: Color(hex: 0xD98A2B)
        case .water: Color(hex: 0x3D8FD1)
        case .walk: Color(hex: 0x3E9B5F)
        case .medication: Color(hex: 0xC8553D)
        case .cleaning: Color(hex: 0x8A6FC9)
        case .grooming: Color(hex: 0xC76A9E)
        case .play: Color(hex: 0x7BA428)
        case .vet: Color(hex: 0x2E8B7F)
        case .other: Color(hex: 0x7A8480)
        case .note: Color(hex: 0x7A8480)
        }
    }
}

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, interval, once
    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Certain days"
        case .interval: "Every few days"
        case .once: "One time"
        }
    }
}
