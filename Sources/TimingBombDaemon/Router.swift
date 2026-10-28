import Foundation
import TimingBombL10n

/// Exact-path router with `:param` captures. Populate before starting the server.
public final class Router: @unchecked Sendable {
    struct Route {
        let method: String
        let segments: [String]
        let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    }

    private var routes: [Route] = []

    public init() {}

    public func add(
        _ method: String, _ pattern: String,
        handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse
    ) {
        routes.append(
            Route(
                method: method.uppercased(),
                segments: pattern.split(separator: "/").map(String.init),
                handler: handler))
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let pathSegments = request.path.split(separator: "/").map(String.init)
        var allowedMethods = Set<String>()
        for route in routes {
            guard let params = match(route.segments, pathSegments) else { continue }
            if route.method == request.method {
                var matched = request
                matched.parameters = params
                return await route.handler(matched)
            }
            allowedMethods.insert(route.method)
        }
        if !allowedMethods.isEmpty {
            return .error(
                405, code: "methodNotAllowed", template: "method {method} is not allowed for {path}",
                params: ["method": request.method, "path": request.path])
        }
        return .error(
            404, code: "noRoute", template: "no route for {method} {path}",
            params: ["method": request.method, "path": request.path])
    }

    private func match(_ pattern: [String], _ path: [String]) -> [String: String]? {
        guard pattern.count == path.count else { return nil }
        var params: [String: String] = [:]
        for (token, segment) in zip(pattern, path) {
            if token.hasPrefix(":") {
                params[String(token.dropFirst())] = segment
            } else if token != segment {
                return nil
            }
        }
        return params
    }
}
