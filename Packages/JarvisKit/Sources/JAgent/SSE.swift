import Foundation

/// One parsed server-sent-event frame.
struct SSEFrame: Sendable {
    var event: String?
    var data: String
}

/// Incremental SSE parser. Feed lines; get a frame at each blank-line boundary.
struct SSEAccumulator {
    private var event: String?
    private var data = ""

    mutating func feed(_ line: String) -> SSEFrame? {
        if line.isEmpty {
            guard !data.isEmpty else { event = nil; return nil }
            let frame = SSEFrame(event: event, data: data)
            event = nil
            data = ""
            return frame
        }
        if line.hasPrefix("event:") {
            event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            let chunk = line.dropFirst(5)
            let trimmed = chunk.first == " " ? String(chunk.dropFirst()) : String(chunk)
            data += data.isEmpty ? trimmed : "\n" + trimmed
        }
        // lines beginning with ":" are comments/heartbeats — ignored.
        return nil
    }

    mutating func flush() -> SSEFrame? {
        guard !data.isEmpty else { return nil }
        let frame = SSEFrame(event: event, data: data)
        event = nil
        data = ""
        return frame
    }
}

/// Shared HTTP+retry front door for streaming providers. Retries transient
/// failures *before* any bytes are surfaced, so retries are always safe.
enum ProviderTransport {
    static let transientStatuses: Set<Int> = [408, 425, 429, 500, 502, 503, 529]

    static func openSSEStream(
        session: URLSession,
        request: URLRequest,
        maxRetries: Int = 3
    ) async throws -> URLSession.AsyncBytes {
        var attempt = 0
        while true {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ProviderError.invalidResponse
                }
                if (200..<300).contains(http.statusCode) {
                    return bytes
                }

                var body = ""
                for try await line in bytes.lines {
                    body += line + "\n"
                    if body.count > 8192 { break }
                }

                if transientStatuses.contains(http.statusCode), attempt < maxRetries {
                    attempt += 1
                    try await backoff(attempt: attempt, retryAfter: http.value(forHTTPHeaderField: "retry-after"))
                    continue
                }
                throw ProviderError.http(status: http.statusCode, body: body)
            } catch let error as ProviderError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Network-level blip (URLError etc.): retry a few times.
                if attempt < maxRetries {
                    attempt += 1
                    try await backoff(attempt: attempt, retryAfter: nil)
                    continue
                }
                throw error
            }
        }
    }

    private static func backoff(attempt: Int, retryAfter: String?) async throws {
        if let retryAfter, let seconds = Double(retryAfter) {
            try await Task.sleep(for: .seconds(min(seconds, 20)))
            return
        }
        let base = pow(2.0, Double(attempt - 1)) * 0.5 // 0.5, 1, 2 …
        let jitter = Double(attempt) * 0.15
        try await Task.sleep(for: .seconds(min(base + jitter, 10)))
    }
}
