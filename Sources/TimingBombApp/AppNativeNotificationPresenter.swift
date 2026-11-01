import Foundation
import TimingBombDaemon
import UserNotifications

/// Receives daemon events and submits them through the registered app bundle.
/// This is what gives notifications the TimingBomb.app icon and permission
/// identity instead of the icon of a shell or osascript process.
@MainActor
final class AppNativeNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNativeNotificationPresenter()

    private let center = UNUserNotificationCenter.current()
    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func start() {
        center.delegate = self
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NativeNotifier.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.receivePending()
            }
        }
        Task { @MainActor [weak self] in
            _ = await self?.requestAuthorizationIfNeeded()
            await self?.receivePending()
        }
    }

    private func receivePending() async {
        guard let messages = try? await TBAPIClient.takeNativeNotifications() else { return }
        for message in messages {
            await deliver(title: message.title, body: message.body)
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    private func deliver(title: String, body: String) async {
        guard await requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "timingbomb-\(UUID().uuidString.lowercased())",
            content: content,
            trigger: nil)
        try? await center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
