import Foundation
import TimingBombCore

/// System notification: sent via osascript's display notification (the daemon is a GUI-less process and
/// displays through the host terminal's/system's notification permission; fails silently when unauthorized, without affecting flow execution).
public struct OsascriptNotifier: Notifying {
    public init() {}

    public func notify(title: String, body: String) async {
        let script =
            "display notification \"\(Self.escape(body))\" with title \"\(Self.escape(title))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
