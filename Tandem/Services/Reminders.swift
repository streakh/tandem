import Foundation
import UserNotifications

/// Local reminders for timed tasks. They're rebuilt every time the data changes, so a task
/// someone else already logged doesn't nag you (as long as the app has synced since).
enum Reminders {
    private static let center = UNUserNotificationCenter.current()
    private static let daysAhead = 3
    private static let limit = 48

    static func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    @MainActor
    static func reschedule(for store: AppStore) {
        center.removeAllPendingNotificationRequests()
        guard store.remindersEnabled else { return }

        var requests: [(Date, UNNotificationRequest)] = []
        let now = Date.now
        for offset in 0..<daysAhead {
            let day = Day.today.adding(offset)
            for pet in store.pets where store.canLog(for: pet, on: day) {
                for task in store.tasks(for: pet.id, on: day) where !task.isResolved {
                    guard let time = task.routine.timeOfDay else { continue }
                    let fireDate = time.date(on: day)
                    guard fireDate > now else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = "\(pet.name): \(task.routine.title)"
                    content.body = task.routine.amount.isEmpty
                        ? "Due at \(time.label). Tap to check it off."
                        : "\(task.routine.amount) · due at \(time.label)"
                    content.sound = .default

                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    requests.append((fireDate, UNNotificationRequest(identifier: task.id, content: content, trigger: trigger)))
                }
            }
        }
        for (_, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(limit) {
            center.add(request)
        }
    }
}
