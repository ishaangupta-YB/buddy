import AVFoundation

/// Records microphone audio while the push-to-talk shortcut is held and returns the captured
/// audio as a single WAV payload for Whisper transcription.
///
/// A WAV (linear PCM) container is used because it requires no encoder priming, so the very
/// short clips push-to-talk produces are never truncated, and Whisper on Workers AI decodes
/// it reliably. Recording goes to a temporary file that is read into memory and deleted as
/// soon as the clip is handed off.
@MainActor
final class PushToTalkRecorder {
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?

    enum RecorderError: Error {
        case couldNotCreateRecorder
    }

    func startRecording() throws {
        let temporaryRecordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("buddy-push-to-talk-\(UUID().uuidString).wav")

        // 16 kHz mono linear PCM keeps clips small while staying well within Whisper's range.
        let recordingSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        guard let audioRecorder = try? AVAudioRecorder(url: temporaryRecordingURL, settings: recordingSettings) else {
            throw RecorderError.couldNotCreateRecorder
        }

        self.audioRecorder = audioRecorder
        self.currentRecordingURL = temporaryRecordingURL
        audioRecorder.record()
    }

    /// Stops recording, returns the captured audio bytes, and removes the temporary file.
    func stopRecordingAndExtractAudio() -> Data? {
        guard let audioRecorder, let currentRecordingURL else {
            return nil
        }
        audioRecorder.stop()
        self.audioRecorder = nil
        self.currentRecordingURL = nil

        defer {
            try? FileManager.default.removeItem(at: currentRecordingURL)
        }
        return try? Data(contentsOf: currentRecordingURL)
    }
}
