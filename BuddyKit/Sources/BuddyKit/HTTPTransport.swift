import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The metadata BuddyKit needs from an HTTP response, kept separate from `URLResponse`
/// so the transport layer can be mocked without constructing AppKit/Foundation URL types.
public struct HTTPResponseMetadata: Equatable, Sendable {
    public let statusCode: Int
    public let contentType: String?

    public init(statusCode: Int, contentType: String?) {
        self.statusCode = statusCode
        self.contentType = contentType
    }

    public var isSuccess: Bool {
        (200...299).contains(statusCode)
    }
}

/// Abstracts the HTTP layer so `WorkersAIClient` can be exercised with a deterministic mock
/// in tests and a real `URLSession` in the macOS app.
public protocol HTTPTransport: Sendable {
    /// Performs a buffered request, returning the full response body and metadata.
    func performRequest(_ request: URLRequest) async throws -> (Data, HTTPResponseMetadata)

    /// Performs a streaming request, returning the response metadata and an async sequence
    /// of decoded text lines (used for Server-Sent Events).
    func performStreamingRequest(
        _ request: URLRequest
    ) async throws -> (HTTPResponseMetadata, AsyncThrowingStream<String, Error>)
}

#if canImport(Darwin)
/// The production transport backed by `URLSession`.
///
/// A single long-lived `URLSession` is reused for every request. Using `.default` (rather
/// than `.ephemeral`) caches TLS session tickets, which avoids a cold TLS handshake on the
/// first large screenshot upload and the transient `-1200` handshake failures that causes.
///
/// This concrete transport is compiled only on Apple platforms (it relies on
/// `URLSession.bytes(for:)` for SSE streaming). On Linux, BuddyKit's tests inject a mock
/// transport instead, so the core logic stays fully exercisable in CI.
public final class URLSessionHTTPTransport: HTTPTransport {
    private let urlSession: URLSession

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        // Disable on-disk caching so no response or credential is persisted.
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        self.urlSession = URLSession(configuration: configuration)
    }

    public func performRequest(_ request: URLRequest) async throws -> (Data, HTTPResponseMetadata) {
        let (responseData, urlResponse) = try await urlSession.data(for: request)
        let metadata = Self.metadata(from: urlResponse)
        return (responseData, metadata)
    }

    public func performStreamingRequest(
        _ request: URLRequest
    ) async throws -> (HTTPResponseMetadata, AsyncThrowingStream<String, Error>) {
        let (byteStream, urlResponse) = try await urlSession.bytes(for: request)
        let metadata = Self.metadata(from: urlResponse)

        let lineStream = AsyncThrowingStream<String, Error> { continuation in
            let consumptionTask = Task {
                do {
                    for try await line in byteStream.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                consumptionTask.cancel()
            }
        }

        return (metadata, lineStream)
    }

    private static func metadata(from urlResponse: URLResponse) -> HTTPResponseMetadata {
        let httpResponse = urlResponse as? HTTPURLResponse
        return HTTPResponseMetadata(
            statusCode: httpResponse?.statusCode ?? -1,
            contentType: httpResponse?.value(forHTTPHeaderField: "Content-Type")
        )
    }
}
#endif
