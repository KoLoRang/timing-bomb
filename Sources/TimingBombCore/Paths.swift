import Foundation

public enum TBPaths {
    public static var homeDir: URL {
        if let env = ProcessInfo.processInfo.environment["TIMINGBOMB_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let applicationSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("TimingBomb", isDirectory: true)
    }

    public static var databaseURL: URL {
        homeDir.appendingPathComponent("timingbomb.sqlite")
    }

    public static var tokenFileURL: URL {
        homeDir.appendingPathComponent("token")
    }

    public static var defaultPort: UInt16 {
        if let text = ProcessInfo.processInfo.environment["TIMINGBOMB_PORT"],
            let port = UInt16(text), port > 0
        {
            return port
        }
        return 47632
    }

    public static func ensureHome() throws {
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
    }
}
