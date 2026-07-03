import Foundation

/// One HTTP GET result: status code + body. Transport failures surface as a
/// `FailureReason` instead, so a caught `URLError` never reaches logs/UI (R10).
public struct HTTPResult: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// The network seam providers depend on — injected so tests drive decode and
/// failure-taxonomy paths without real network (no test hits the live endpoints).
public protocol UsageFetching: Sendable {
    func get(url: URL, headers: [String: String]) async -> Result<HTTPResult, FailureReason>
}

/// Production client. Its session **refuses all redirects** so a redirected
/// response can never forward the `Authorization: Bearer` token to another host
/// (R12) — the usage endpoints are not expected to redirect. The session's delegate
/// is a standalone `RedirectBlocker` (not `self`), so the client isn't caught in the
/// session→delegate retain cycle, and requests carry an explicit timeout so a hung
/// endpoint can't stall a poll cycle indefinitely.
public final class RedirectBlockingHTTPClient: UsageFetching, @unchecked Sendable {
    private let session: URLSession

    public init(timeout: TimeInterval = 20) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    public func get(url: URL, headers: [String: String]) async -> Result<HTTPResult, FailureReason> {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transient("No HTTP response"))
            }
            return .success(HTTPResult(status: http.statusCode, body: data))
        } catch {
            // Do not interpolate the error (may echo the request/token) — typed only.
            return .failure(.transient("Network unavailable"))
        }
    }
}

/// Session delegate that blocks every redirect: passing `nil` stops the redirect and
/// returns the 3xx response as-is, so the Authorization header is never re-sent to a
/// new host (R12). A standalone object, not the client, to avoid a retain cycle.
final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// ISO 8601 parsing tolerant of fractional seconds (both endpoints return UTC).
public enum DateParsing {
    public static func iso8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        return ISO8601DateFormatter().date(from: string)
    }
}
