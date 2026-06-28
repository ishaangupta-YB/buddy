import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BuddyKit

final class WorkersAIClientTests: XCTestCase {
    private func makeProxyConfiguration(proxySecret: String? = nil) -> BuddyConfiguration {
        BuddyConfiguration(
            endpointMode: .workerProxy(
                baseURL: URL(string: "https://buddy-proxy.example.workers.dev")!,
                proxySecret: proxySecret
            )
        )
    }

    func testStreamingChatAccumulatesDeltasAndReportsProgress() async throws {
        let transport = MockHTTPTransport()
        transport.nextStreamingResponse = MockHTTPTransport.StreamingResponse(
            lines: [
                "data: {\"choices\":[{\"delta\":{\"content\":\"hello \"}}]}",
                "data: {\"choices\":[{\"delta\":{\"content\":\"there\"}}]}",
                "data: [DONE]"
            ],
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "text/event-stream")
        )
        let client = WorkersAIClient(configuration: makeProxyConfiguration(), transport: transport)

        let progressCollector = AccumulatedTextCollector()
        let finalText = try await client.streamCompanionResponse(
            labeledScreenImages: [LabeledScreenImage(imageData: Data([0xFF, 0xD8]), label: "primary focus")],
            userPrompt: "what is this",
            conversationHistory: []
        ) { accumulatedText in
            progressCollector.append(accumulatedText)
        }

        XCTAssertEqual(finalText, "hello there")
        XCTAssertEqual(progressCollector.snapshots, ["hello ", "hello there"])

        // The streaming request must target the proxy /chat route and carry stream:true.
        let request = try XCTUnwrap(transport.receivedRequests.last)
        XCTAssertEqual(request.url?.absoluteString, "https://buddy-proxy.example.workers.dev/chat")
        let body = try XCTUnwrap(transport.lastRequestJSONBody())
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["model"] as? String, WorkersAIModelCatalog.defaultModel.modelIdentifier)
    }

    func testStreamingChatThrowsOnHTTPError() async {
        let transport = MockHTTPTransport()
        transport.nextStreamingResponse = MockHTTPTransport.StreamingResponse(
            lines: ["{\"error\":\"bad model\"}"],
            metadata: HTTPResponseMetadata(statusCode: 400, contentType: "application/json")
        )
        let client = WorkersAIClient(configuration: makeProxyConfiguration(), transport: transport)

        do {
            _ = try await client.streamCompanionResponse(
                labeledScreenImages: [],
                userPrompt: "hi",
                conversationHistory: []
            ) { _ in }
            XCTFail("expected an error to be thrown")
        } catch let WorkersAIResponseError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 400)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testTranscribeSpeechSendsBase64AudioAndDecodesText() async throws {
        let transport = MockHTTPTransport()
        transport.nextBufferedResponse = MockHTTPTransport.BufferedResponse(
            data: Data("{\"text\":\"hello world\"}".utf8),
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "application/json")
        )
        let client = WorkersAIClient(configuration: makeProxyConfiguration(), transport: transport)

        let audioBytes = Data([0x01, 0x02, 0x03, 0x04])
        let transcript = try await client.transcribeSpeech(audioData: audioBytes)

        XCTAssertEqual(transcript, "hello world")
        let request = try XCTUnwrap(transport.receivedRequests.last)
        XCTAssertEqual(request.url?.absoluteString, "https://buddy-proxy.example.workers.dev/transcribe")
        let body = try XCTUnwrap(transport.lastRequestJSONBody())
        XCTAssertEqual(body["audio"] as? String, audioBytes.base64EncodedString())
        XCTAssertEqual(body["language"] as? String, "en")
    }

    func testSynthesizeSpeechReturnsAudioBytesFromAudioContentType() async throws {
        let transport = MockHTTPTransport()
        let fakeAudio = Data([0x49, 0x44, 0x33]) // "ID3" mp3 header bytes
        transport.nextBufferedResponse = MockHTTPTransport.BufferedResponse(
            data: fakeAudio,
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "audio/mpeg")
        )
        let client = WorkersAIClient(configuration: makeProxyConfiguration(), transport: transport)

        let audio = try await client.synthesizeSpeech(text: "hello")
        XCTAssertEqual(audio, fakeAudio)
        let request = try XCTUnwrap(transport.receivedRequests.last)
        XCTAssertEqual(request.url?.absoluteString, "https://buddy-proxy.example.workers.dev/tts")
        let body = try XCTUnwrap(transport.lastRequestJSONBody())
        XCTAssertEqual(body["prompt"] as? String, "hello")
        XCTAssertEqual(body["lang"] as? String, "en")
    }

    func testDirectCloudflareModeUsesBearerTokenAndCanonicalURLs() async throws {
        let configuration = BuddyConfiguration(
            endpointMode: .directCloudflare(accountIdentifier: "acct123", apiToken: "secret-token")
        )
        let transport = MockHTTPTransport()
        transport.nextBufferedResponse = MockHTTPTransport.BufferedResponse(
            data: Data("{\"text\":\"hi\"}".utf8),
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "application/json")
        )
        let client = WorkersAIClient(configuration: configuration, transport: transport)

        _ = try await client.transcribeSpeech(audioData: Data([0x00]))
        let request = try XCTUnwrap(transport.receivedRequests.last)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.cloudflare.com/client/v4/accounts/acct123/ai/run/@cf/openai/whisper-large-v3-turbo"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testWorkerProxyModeSendsBearerSecretWhenConfigured() async throws {
        let transport = MockHTTPTransport()
        transport.nextBufferedResponse = MockHTTPTransport.BufferedResponse(
            data: Data("{\"text\":\"hi\"}".utf8),
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "application/json")
        )
        let client = WorkersAIClient(
            configuration: makeProxyConfiguration(proxySecret: "shared-proxy-secret"),
            transport: transport
        )

        _ = try await client.transcribeSpeech(audioData: Data([0x00]))
        let request = try XCTUnwrap(transport.receivedRequests.last)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer shared-proxy-secret"
        )
    }

    func testWorkerProxyModeOmitsAuthorizationWhenNoSecretConfigured() async throws {
        let transport = MockHTTPTransport()
        transport.nextBufferedResponse = MockHTTPTransport.BufferedResponse(
            data: Data("{\"text\":\"hi\"}".utf8),
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "application/json")
        )
        let client = WorkersAIClient(configuration: makeProxyConfiguration(), transport: transport)

        _ = try await client.transcribeSpeech(audioData: Data([0x00]))
        let request = try XCTUnwrap(transport.receivedRequests.last)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
