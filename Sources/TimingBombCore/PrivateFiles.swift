import Foundation
import Darwin

/// Files owned by TimingBomb must not inherit a permissive process umask.
/// Operations validate the opened inode before changing permissions or data.
public enum PrivateFiles {
    public static func ensureDirectory(_ url: URL) throws {
        if mkdir(url.path, 0o700) != 0 && errno != EEXIST {
            // Parent directories belong to the user or OS; never chmod them.
            if errno == ENOENT {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard mkdir(url.path, 0o700) == 0 || errno == EEXIST else {
                    throw currentError()
                }
            } else {
                throw currentError()
            }
        }
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw currentError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw currentError() }
        guard info.st_uid == geteuid(), (info.st_mode & S_IFMT) == S_IFDIR else {
            throw POSIXError(.EPERM)
        }
        guard fchmod(descriptor, 0o700) == 0 else { throw currentError() }
    }

    public static func ensureFile(_ url: URL) throws {
        let descriptor = try openFile(url, flags: O_RDWR)
        close(descriptor)
    }

    public static func ensureExistingFile(_ url: URL) throws {
        do {
            let descriptor = try openFile(url, flags: O_RDWR, create: false)
            close(descriptor)
        } catch let error as POSIXError where error.code == .ENOENT {
            // SQLite sidecars are transient; do not create absent ones.
        }
    }

    public static func write(_ data: Data, to url: URL) throws {
        // Validate any existing destination, without truncating it. Rename
        // commits a complete 0600 replacement so clients never read half a token.
        try ensureFile(url)
        var template = Array(url.deletingLastPathComponent()
            .appendingPathComponent(".timingbomb-write-XXXXXX").path.utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { buffer in
            mkstemp(buffer.baseAddress!)
        }
        guard descriptor >= 0 else { throw currentError() }
        let temporaryPath = template.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        defer { unlink(temporaryPath) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        guard fchmod(descriptor, 0o600) == 0 else { throw currentError() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        guard rename(temporaryPath, url.path) == 0 else { throw currentError() }
    }

    public static func appendHandle(at url: URL) throws -> FileHandle {
        let descriptor = try openFile(url, flags: O_WRONLY | O_APPEND)
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    public static func temporaryDirectory(prefix: String) throws -> URL {
        // Keep the caller's prefix a filename, never a path.
        guard !prefix.isEmpty, !prefix.contains("/"), !prefix.contains("\0") else {
            throw POSIXError(.EINVAL)
        }
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-XXXXXX").path
        var bytes = Array(template.utf8CString)
        let path: String? = bytes.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress, mkdtemp(base) != nil else { return nil }
            return String(cString: base)
        }
        guard let path else { throw currentError() }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func openFile(_ url: URL, flags: Int32, create: Bool = true) throws -> Int32 {
        let descriptor = open(url.path, flags | (create ? O_CREAT : 0) | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw currentError() }
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { throw currentError() }
            guard info.st_uid == geteuid(), (info.st_mode & S_IFMT) == S_IFREG,
                info.st_nlink == 1
            else { throw POSIXError(.EPERM) }
            guard fchmod(descriptor, 0o600) == 0 else { throw currentError() }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func currentError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
