import ArgumentParser
import Foundation
import TimingBombCore
import TimingBombDaemon
import TimingBombL10n

@main
struct TBCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tb",
        abstract: L10n.t("TimingBomb — Mac task automation orchestration"),
        version: DaemonApp.version,
        subcommands: [
            Status.self, Serve.self, AuthCommand.self, Flow.self, Run.self, Runs.self,
            Allow.self, Logging.self,
        ]
    )
}

// MARK: - API client

struct APIClient {
    let baseURL: URL
    let token: String

    static func load() throws -> APIClient {
        var token = ProcessInfo.processInfo.environment["TIMINGBOMB_TOKEN"] ?? ""
        if token.isEmpty {
            token = (try? String(contentsOf: TBPaths.tokenFileURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if token.isEmpty {
            throw TBApiError(
                status: 400, code: "tokenNotFound",
                template: "API token not found (expected at {path}). Start the daemon first: tb serve",
                params: ["path": TBPaths.tokenFileURL.path])
        }
        let port = TBPaths.defaultPort
        guard let url = URL(string: "http://127.0.0.1:\(port)") else {
            throw TBError.internalError("invalid base url")
        }
        return APIClient(baseURL: url, token: token)
    }

    func request(
        _ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError
        where [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost].contains(error.code) {
            throw TBApiError(
                status: 400, code: "daemonUnreachable",
                template: "cannot connect to daemon ({url}). Start it first: tb serve",
                params: ["url": baseURL.absoluteString])
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Re-render structured server errors in this client's locale.
            if let apiError = try? TBJSON.decodeData(APIErrorBody.self, from: data) {
                if let template = apiError.template, !template.isEmpty {
                    throw TBApiError(
                        status: 400, code: apiError.code ?? "serverError",
                        template: template, params: apiError.params ?? [:])
                }
                throw TBError.invalidRequest(apiError.error)
            }
            throw TBApiError(
                status: 400, code: "httpError", template: "HTTP {status}",
                params: ["status": String(status)])
        }
        return data
    }

    func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        try await request("GET", path, query: query)
    }

    func post(_ path: String, body: Data? = nil, query: [String: String] = [:]) async throws -> Data {
        try await request("POST", path, query: query, body: body)
    }

    func delete(_ path: String) async throws -> Data {
        try await request("DELETE", path)
    }
}

struct APIErrorBody: Decodable {
    let error: String
    let code: String?
    let template: String?
    let params: [String: String]?
}

// MARK: - Shared helpers

enum CLI {
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try TBJSON.decodeData(type, from: data)
    }

    static func printJSON(_ data: Data) {
        let object = try? JSONSerialization.jsonObject(with: data)
        if let object,
            let pretty = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])),
            let text = String(data: pretty, encoding: .utf8)
        {
            print(text)
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    static func fmt(_ date: Date?) -> String {
        guard let date else { return "-" }
        return dateFormatter.string(from: date)
    }

    static func fmtDuration(_ ms: Double?) -> String {
        guard let ms else { return "-" }
        if ms < 1000 { return String(format: "%.0fms", ms) }
        return String(format: "%.1fs", ms / 1000)
    }

    /// Fixed-width row join for aligned tables; overlong columns pass through.
    static func row(_ columns: String..., widths: [Int]) -> String {
        var parts: [String] = []
        for (index, column) in columns.enumerated() {
            let width = index < widths.count ? widths[index] : 0
            if column.count >= width {
                parts.append(column)
            } else {
                parts.append(column + String(repeating: " ", count: width - column.count))
            }
        }
        return parts.joined(separator: "  ")
    }

    /// Convenience overload for five "column, width" pairs.
    static func row(
        _ c1: String, _ w1: Int, _ c2: String, _ w2: Int, _ c3: String, _ w3: Int,
        _ c4: String, _ w4: Int, _ c5: String, _ w5: Int
    ) -> String {
        row(c1, c2, c3, c4, c5, widths: [w1, w2, w3, w4, w5])
    }

    static func readFlowSource(_ file: String?) throws -> Data {
        if let file {
            guard let data = FileManager.default.contents(atPath: file) else {
                throw TBApiError(
                    status: 400, code: "fileUnreadable",
                    template: "failed to read file: {file}", params: ["file": file])
            }
            return data
        }
        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty else {
            throw TBApiError(
                status: 400, code: "stdinEmpty",
                template: "stdin is empty; provide --file or pipe flow JSON in")
        }
        return stdinData
    }

    /// Maps low-level transport errors to friendly CLI errors.
    static func clean(_ error: Error) -> Error {
        if let error = error as? TBError { return error }
        if let error = error as? TBApiError { return error }
        if let urlError = error as? URLError,
            [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost]
                .contains(urlError.code)
        {
            return TBApiError(
                status: 400, code: "daemonUnreachable",
                template: "cannot connect to daemon. Start it first: tb serve")
        }
        if let decodingError = error as? DecodingError {
            return TBApiError(
                status: 400, code: "responseDecodeFailed",
                template: "failed to decode response: {detail}",
                params: ["detail": decodingError.localizedDescription])
        }
        return error
    }
}

// MARK: - status / serve / auth

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: L10n.t("View daemon status"))

    @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

    func run() async throws {
        do {
            let client = try APIClient.load()
            let data = try await client.get("healthz")
            if json {
                CLI.printJSON(data)
                return
            }
            let health = try CLI.decode(HealthBody.self, data)
            print(
                L10n.t(
                    "daemon: running ({status}, v{version}) — http://127.0.0.1:{port}",
                    [
                        "status": health.status,
                        "version": health.version,
                        "port": String(TBPaths.defaultPort),
                    ]))
        } catch {
            throw CLI.clean(error)
        }
    }
}

struct HealthBody: Decodable {
    let status: String
    let version: String
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: L10n.t("Start the daemon in the foreground"))

    func run() async throws {
        let app = try await DaemonApp.bootstrap()
        try await app.start()
    }
}

struct AuthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: L10n.t("Authentication info"),
        subcommands: [Token.self]
    )

    struct Token: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Print the API token"))

        func run() throws {
            if let env = ProcessInfo.processInfo.environment["TIMINGBOMB_TOKEN"], !env.isEmpty {
                print(env)
                return
            }
            let token = try String(contentsOf: TBPaths.tokenFileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print(token)
        }
    }
}
