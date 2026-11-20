import UIKit
import UserNotifications

/// Receives the things only an app delegate is told about: this phone's push token and incoming pushes.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await AppStore.shared.registerPushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// A push from another caregiver also wakes the app briefly so it can sync,
    /// which cancels local reminders for anything they just did.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await AppStore.shared.loadAll(quiet: true)
        return .newData
    }

    /// While the app is open the list already updates live, so pushes stay quiet; local reminders still show.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.trigger is UNPushNotificationTrigger ? [] : [.banner, .sound]
    }

    /// Tapping a notification opens the app on that pet.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = (info["pet_id"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run { AppStore.shared.selectPet(id) }
    }
}
