import Foundation
import TimingBombCore

/// Notification bridge from the background daemon to the foreground
/// TimingBomb.app. UserNotifications must be called by the registered app
/// process; calling it directly from timingbombd is rejected by macOS because
/// the daemon is not itself a GUI application. The app receives this
/// distributed wake-up and retrieves the payload through the authenticated API.
/// No notification content is broadcast to other processes in the login session.
public struct NativeNotifier: Notifying {
    public static let notificationName = Notification.Name("com.timingbomb.app.native-notification")
    private static let inbox = NativeNotificationInbox()

    public init() {}

    public func notify(title: String, body: String) async {
        await Self.inbox.append(title: title, body: body)
        DistributedNotificationCenter.default().post(
            name: Self.notificationName,
            object: nil)
    }

    public static func takePending() async -> [NativeNotificationMessage] {
        await inbox.takePending()
    }
}

public struct NativeNotificationMessage: Codable, Sendable {
    public let title: String
    public let body: String
}

public struct NativeNotificationListResponse: Codable, Sendable {
    public let notifications: [NativeNotificationMessage]
}

private actor NativeNotificationInbox {
    private var messages: [(createdAt: Date, message: NativeNotificationMessage)] = []

    func append(title: String, body: String) {
        removeExpired()
        messages.append((Date(), NativeNotificationMessage(title: title, body: body)))
        if messages.count > 100 { messages.removeFirst(messages.count - 100) }
    }

    func takePending() -> [NativeNotificationMessage] {
        removeExpired()
        defer { messages.removeAll() }
        return messages.map(\.message)
    }

    private func removeExpired() {
        let cutoff = Date().addingTimeInterval(-60)
        messages.removeAll { $0.createdAt < cutoff }
    }
}
