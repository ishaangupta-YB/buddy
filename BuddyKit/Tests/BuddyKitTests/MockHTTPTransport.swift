import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BuddyKit

/// A deterministic in-memory `HTTPTransport` for exercising `WorkersAIClient` and
/// `OpenCodeClient` without any real network. Records the requests it receives and replays
/// canned responses, so tests can assert on both the outgoing request and the parsed result.
final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    struct BufferedResponse {
        let data: Data
        let metadata: HTTPResponseMetadata
    }

    struct StreamingResponse {
        let lines: [String]
        let metadata: HTTPResponseMetadata
    }

    private(set) var receivedRequests: [URLRequest] = []
    var nextBufferedResponse: BufferedResponse?
    var nextStreamingResponse: StreamingResponse?

    func performRequest(_ request: URLRequest) async throws -> (Data, HTTPResponseMetadata) {
        receivedRequests.append(request)
        guard let nextBufferedResponse else {
            return (Data(), HTTPResponseMetadata(statusCode: 500, contentType: nil))
        }
        return (nextBufferedResponse.data, nextBufferedResponse.metadata)
    }

    func performStreamingRequest(
        _ request: URLRequest
    ) async throws -> (HTTPResponseMetadata, AsyncThrowingStream<String, Error>) {
        receivedRequests.append(request)
        let streamingResponse = nextStreamingResponse
            ?? StreamingResponse(lines: [], metadata: HTTPResponseMetadata(statusCode: 500, contentType: nil))

        let lineStream = AsyncThrowingStream<String, Error> { continuation in
            for line in streamingResponse.lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (streamingResponse.metadata, lineStream)
    }

    /// The JSON body of the most recent request, decoded as a dictionary.
    func lastRequestJSONBody() -> [String: Any]? {
        guard let httpBody = receivedRequests.last?.httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: httpBody)) as? [String: Any]
    }
}

/// A thread-safe collector used to capture the progressive text snapshots emitted by the
/// `@Sendable` streaming callback without tripping Swift's concurrency checks.
final class AccumulatedTextCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ text: String) {
        lock.lock()
        storage.append(text)
        lock.unlock()
    }

    var snapshots: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
