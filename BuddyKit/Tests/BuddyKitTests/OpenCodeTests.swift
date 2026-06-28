import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BuddyKit

final class OpenCodeConfigurationTests: XCTestCase {
    func testConfigurationObjectPinsCloudflareWorkersAIProvider() {
        let configuration = OpenCodeConfiguration.makeConfigurationObject(accountIdentifier: "acct123")

        XCTAssertEqual(configuration["$schema"] as? String, "https://opencode.ai/config.json")
        XCTAssertEqual(
            configuration["model"] as? String,
            "cloudflare-workers-ai/@cf/moonshotai/kimi-k2.7-code"
        )

        let provider = try? XCTUnwrap(
            (configuration["provider"] as? [String: Any])?["cloudflare-workers-ai"] as? [String: Any]
        )
        XCTAssertEqual(provider?["npm"] as? String, "@ai-sdk/openai-compatible")
        let options = provider?["options"] as? [String: Any]
        XCTAssertEqual(
            options?["baseURL"] as? String,
            "https://api.cloudflare.com/client/v4/accounts/acct123/ai/v1"
        )
        XCTAssertEqual(options?["apiKey"] as? String, "${CLOUDFLARE_API_KEY}")

        let models = provider?["models"] as? [String: Any]
        XCTAssertNotNil(models?["@cf/moonshotai/kimi-k2.7-code"])
        XCTAssertNotNil(models?["@cf/moonshotai/kimi-k2.6"])
    }

    func testConfigurationJSONIsValidAndDoesNotEscapeSlashes() throws {
        let json = try OpenCodeConfiguration.makeConfigurationJSON(accountIdentifier: "acct123")
        XCTAssertTrue(json.contains("\"https://opencode.ai/config.json\""))
        // withoutEscapingSlashes keeps model identifiers readable.
        XCTAssertTrue(json.contains("@cf/moonshotai/kimi-k2.7-code"))
        // The rendered JSON must round-trip.
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertNotNil(parsed?["provider"])
    }
}

final class OpenCodeClientTests: XCTestCase {
    private let serverBaseURL = URL(string: "http://127.0.0.1:4096")!

    func testCreateSessionRequestTargetsSessionRoute() {
        let client = OpenCodeClient(serverBaseURL: serverBaseURL, transport: MockHTTPTransport())
        let request = client.makeCreateSessionRequest()
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:4096/session")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testSendMessageRequestCarriesProviderModelAndPrompt() throws {
        let client = OpenCodeClient(
            serverBaseURL: serverBaseURL,
            chatModel: WorkersAIModelCatalog.kimiK27Code,
            transport: MockHTTPTransport()
        )
        let request = try client.makeSendMessageRequest(promptText: "refactor this", sessionIdentifier: "ses_1")
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:4096/session/ses_1/message")

        let body = try XCTUnwrap(
            (try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody))) as? [String: Any]
        )
        XCTAssertEqual(body["providerID"] as? String, "cloudflare-workers-ai")
        XCTAssertEqual(body["modelID"] as? String, "@cf/moonshotai/kimi-k2.7-code")
        let parts = body["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, "refactor this")
    }

    func testDecodesSessionIdentifier() throws {
        let data = Data("{\"id\":\"ses_abc\",\"title\":\"x\"}".utf8)
        XCTAssertEqual(try OpenCodeClient.decodeSessionIdentifier(from: data), "ses_abc")
    }

    func testDecodesAssistantTextAcrossParts() throws {
        let data = Data("""
        {"parts":[{"type":"text","text":"hello "},{"type":"tool","name":"edit"},{"type":"text","text":"world"}]}
        """.utf8)
        XCTAssertEqual(try OpenCodeClient.decodeAssistantText(from: data), "hello world")
    }

    func testSendPromptEndToEndThroughMockTransport() async throws {
        let transport = MockHTTPTransport()
        transport.nextBufferedResponse = MockHTTPTransport.BufferedResponse(
            data: Data("{\"parts\":[{\"type\":\"text\",\"text\":\"done\"}]}".utf8),
            metadata: HTTPResponseMetadata(statusCode: 200, contentType: "application/json")
        )
        let client = OpenCodeClient(serverBaseURL: serverBaseURL, transport: transport)
        let reply = try await client.sendPrompt("hi", toSession: "ses_1")
        XCTAssertEqual(reply, "done")
    }
}
