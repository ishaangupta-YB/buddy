import AppKit
import BuddyKit

/// The high-level state of the companion, surfaced to the menu bar panel and overlay so the
/// UI can reflect what Buddy is doing.
enum CompanionVoiceState: Equatable {
    case idle
    case listening
    case processing
    case responding
}

/// The central state machine that coordinates the entire push-to-talk pipeline:
/// record voice → transcribe with Whisper → capture screens → stream a Kimi response →
/// speak it with MeloTTS → optionally fly the cursor to a pointed-at element.
///
/// Every leg of the pipeline runs against Cloudflare Workers AI through `WorkersAIClient`.
/// The controller is `@MainActor` so all published UI state mutates on the main thread.
@MainActor
final class CompanionController: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var latestSpokenResponse: String = ""
    @Published var selectedChatModel: WorkersAIChatModel {
        didSet {
            AppConfiguration.saveSelectedChatModel(selectedChatModel)
            rebuildWorkersAIClient()
        }
    }

    private var workersAIClient: WorkersAIClient
    private let screenCaptureService = ScreenCaptureService()
    private let pushToTalkRecorder = PushToTalkRecorder()
    private let speechPlaybackService = SpeechPlaybackService()
    private let hotkeyMonitor = GlobalPushToTalkHotkeyMonitor()
    private let cursorOverlayController = CursorOverlayController()
    private var conversationHistory: ConversationHistoryStore

    private var activePipelineTask: Task<Void, Never>?

    init() {
        let configuration = AppConfiguration.makeBuddyConfiguration()
        self.selectedChatModel = configuration.chatModel
        self.conversationHistory = ConversationHistoryStore(limit: configuration.conversationHistoryLimit)
        self.workersAIClient = WorkersAIClient(
            configuration: configuration,
            transport: URLSessionHTTPTransport()
        )
    }

    // MARK: - Push-to-talk lifecycle

    func startListeningForPushToTalk() {
        hotkeyMonitor.onPress = { [weak self] in
            self?.handleHotkeyPressed()
        }
        hotkeyMonitor.onRelease = { [weak self] in
            self?.handleHotkeyReleased()
        }
        hotkeyMonitor.startMonitoring()
    }

    func stopListeningForPushToTalk() {
        hotkeyMonitor.stopMonitoring()
        activePipelineTask?.cancel()
    }

    private func handleHotkeyPressed() {
        // Ignore a new press while a previous turn is still being processed or spoken.
        guard voiceState == .idle else { return }
        voiceState = .listening
        latestSpokenResponse = ""
        cursorOverlayController.showListeningState()
        do {
            try pushToTalkRecorder.startRecording()
        } catch {
            failPipeline(withSpokenMessage: SystemPrompts.spokenErrorFallback)
        }
    }

    private func handleHotkeyReleased() {
        guard voiceState == .listening else { return }
        voiceState = .processing
        cursorOverlayController.showProcessingState()

        let recordedAudioData = pushToTalkRecorder.stopRecordingAndExtractAudio()
        activePipelineTask = Task { [weak self] in
            await self?.runPipeline(withRecordedAudioData: recordedAudioData)
        }
    }

    // MARK: - Pipeline

    private func runPipeline(withRecordedAudioData recordedAudioData: Data?) async {
        guard let recordedAudioData, !recordedAudioData.isEmpty else {
            resetToIdle()
            return
        }

        do {
            let transcribedText = try await workersAIClient.transcribeSpeech(audioData: recordedAudioData)
            let trimmedTranscript = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTranscript.isEmpty else {
                resetToIdle()
                return
            }

            let screenCapture = try await screenCaptureService.captureAllScreens()

            voiceState = .responding
            let fullResponseText = try await workersAIClient.streamCompanionResponse(
                labeledScreenImages: screenCapture.labeledImages,
                userPrompt: trimmedTranscript,
                conversationHistory: conversationHistory.exchanges
            ) { [weak self] accumulatedText in
                Task { @MainActor in
                    self?.updateStreamingResponse(accumulatedText)
                }
            }

            await finishTurn(
                userTranscript: trimmedTranscript,
                fullResponseText: fullResponseText,
                screenCapture: screenCapture
            )
        } catch is CancellationError {
            resetToIdle()
        } catch {
            failPipeline(withSpokenMessage: SystemPrompts.spokenErrorFallback)
        }
    }

    private func updateStreamingResponse(_ accumulatedText: String) {
        // Strip any partially-streamed pointing tag so it is never shown or spoken.
        let parseResult = PointTagParser.parse(from: accumulatedText)
        latestSpokenResponse = parseResult.spokenText
        cursorOverlayController.updateResponseText(parseResult.spokenText)
    }

    private func finishTurn(
        userTranscript: String,
        fullResponseText: String,
        screenCapture: ScreenCaptureResult
    ) async {
        let parseResult = PointTagParser.parse(from: fullResponseText)
        latestSpokenResponse = parseResult.spokenText
        cursorOverlayController.updateResponseText(parseResult.spokenText)

        conversationHistory.record(userText: userTranscript, assistantText: parseResult.spokenText)

        // If the model pointed at an element, map the screenshot coordinate to the right display
        // and fly the cursor there while the response is spoken.
        if let pointedCoordinate = parseResult.coordinate {
            moveCursorToPointedElement(
                pointedCoordinate: pointedCoordinate,
                screenNumber: parseResult.screenNumber,
                elementLabel: parseResult.elementLabel,
                screenCapture: screenCapture
            )
        }

        do {
            let spokenAudioData = try await workersAIClient.synthesizeSpeech(text: parseResult.spokenText)
            try speechPlaybackService.play(audioData: spokenAudioData)
        } catch {
            // Speech is best-effort: the text response is already on screen, so a TTS failure
            // should not surface as a hard error.
        }

        resetToIdle()
    }

    private func moveCursorToPointedElement(
        pointedCoordinate: BuddyPoint,
        screenNumber: Int?,
        elementLabel: String?,
        screenCapture: ScreenCaptureResult
    ) {
        // Screen numbers are 1-based in the model's response; default to the first display.
        let zeroBasedScreenIndex = max(0, (screenNumber ?? 1) - 1)
        guard zeroBasedScreenIndex < screenCapture.displayGeometries.count else { return }

        let displayGeometry = screenCapture.displayGeometries[zeroBasedScreenIndex]
        let globalPoint = ScreenCoordinateMapper.mapScreenshotPixelToGlobalAppKitPoint(
            screenshotPixelCoordinate: pointedCoordinate,
            displayGeometry: displayGeometry
        )
        cursorOverlayController.pointCursor(
            atGlobalPoint: CGPoint(x: globalPoint.x, y: globalPoint.y),
            elementLabel: elementLabel
        )
    }

    // MARK: - State helpers

    private func resetToIdle() {
        voiceState = .idle
        cursorOverlayController.scheduleFadeOutAfterInteraction()
    }

    private func failPipeline(withSpokenMessage spokenMessage: String) {
        latestSpokenResponse = spokenMessage
        cursorOverlayController.updateResponseText(spokenMessage)
        resetToIdle()
    }

    private func rebuildWorkersAIClient() {
        var configuration = AppConfiguration.makeBuddyConfiguration()
        configuration.chatModel = selectedChatModel
        workersAIClient = WorkersAIClient(
            configuration: configuration,
            transport: URLSessionHTTPTransport()
        )
    }
}
