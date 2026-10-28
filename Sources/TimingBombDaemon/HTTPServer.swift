import Foundation
import Network
import TimingBombCore
import TimingBombL10n

// MARK: - Request / Response

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data
    public var parameters: [String: String] = [:]

    public init(
        method: String, path: String, query: [String: String] = [:],
        headers: [String: String] = [:], body: Data = Data()
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let data = (try? TBJSON.encodeData(value)) ?? Data("{}".utf8)
        var response = HTTPResponse(status: status, body: data)
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        return response
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(["error": message], status: status)
    }

    /// Error response carrying a stable machine `code`, the English `template`
    /// and its `params`, so clients can render the message in their own locale.
    /// `error` holds a daemon-locale rendering for non-localizing consumers.
    public static func error(
        _ status: Int, code: String, template: String,
        params: [String: String] = [:], issues: [ValidationIssue]? = nil
    ) -> HTTPResponse {
        struct Body: Encodable {
            let error: String
            let code: String
            let template: String
            let params: [String: String]
            let issues: [ValidationIssue]?
        }
        return json(
            Body(
                error: L10n.t(template, params), code: code, template: template,
                params: params, issues: issues),
            status: status)
    }
}

// MARK: - Server

/// A minimal HTTP/1.1 server for the local API: binds to 127.0.0.1 only,
/// parses Content-Length bodies, and closes the connection after each response.
public final class MiniHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let handler: Handler
    private let listener: NWListener
    private let serveQueue = DispatchQueue(label: "tb.http.server")
    public private(set) var port: UInt16 = 0

    public init(port: UInt16, handler: @escaping Handler) throws {
        let params = NWParameters.tcp
        if port != 0, let endpointPort = NWEndpoint.Port(rawValue: port) {
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        }
        listener = try NWListener(using: params)
        self.handler = handler
    }

    public func start() async throws {
        let startGate = OnceResume()
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let bound = self?.listener.port?.rawValue, bound > 0 {
                    self?.port = bound
                }
                startGate.resume()
            case .failed(let error):
                startGate.resume(throwing: error)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serveQueue.async {
                self?.serve(connection)
            }
        }
        listener.start(queue: serveQueue)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startGate.attach(cont)
        }
    }

    // MARK: Connections

    public func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: serveQueue)
        receive(connection, buffer: [])
    }

    private func receive(_ connection: NWConnection, buffer: [UInt8]) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(contentsOf: data) }
            if error != nil {
                connection.cancel()
                return
            }
            if let request = Self.parseRequest(&buffer) {
                Task {
                    let response = await self.handler(request)
                    self.send(response, on: connection)
                }
            } else if isComplete || buffer.count > (16 << 20) {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        var headers = response.headers
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"

        var head = "HTTP/1.1 \(response.status) \(Self.statusText(response.status))\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var payload = Data(head.utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: Parsing

    static func parseRequest(_ buffer: inout [UInt8]) -> HTTPRequest? {
        guard let headerEnd = findSubsequence(buffer, [13, 10, 13, 10]) else { return nil }
        let headBytes = Array(buffer[0..<headerEnd])
        guard let head = String(bytes: headBytes, encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd + 4
        guard buffer.count - bodyStart >= contentLength, contentLength >= 0 else { return nil }
        let body = Data(buffer[bodyStart..<(bodyStart + contentLength)])
        buffer.removeFirst(bodyStart + contentLength)

        var path = target
        var query: [String: String] = [:]
        if let questionMark = target.firstIndex(of: "?") {
            path = String(target[..<questionMark])
            let queryString = String(target[target.index(after: questionMark)...])
            for pair in queryString.split(separator: "&") {
                let kv = pair.split(
                    separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = String(kv[0]).removingPercentEncoding else { continue }
                let rawValue = kv.count > 1 ? String(kv[1]) : ""
                query[key] = rawValue.removingPercentEncoding ?? rawValue
            }
        }
        path = path.removingPercentEncoding ?? path
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    private static func findSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        let span = haystack.count - needle.count
        var i = 0
        while i <= span {
            if haystack[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }

    static func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Status \(status)"
        }
    }
}

/// Resumes a continuation exactly once even if NWListener fires multiple state updates.
final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>? = nil
    private var alreadyResumed = false

    func attach(_ cont: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if alreadyResumed { cont.resume(); return }
        if let existing = continuation {
            existing.resume()
            continuation = cont
            return
        }
        continuation = cont
    }

    func resume() {
        lock.lock()
        let cont = continuation
        continuation = nil
        alreadyResumed = true
        lock.unlock()
        cont?.resume()
    }

    func resume(throwing error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        alreadyResumed = true
        lock.unlock()
        cont?.resume(throwing: error)
    }
}
