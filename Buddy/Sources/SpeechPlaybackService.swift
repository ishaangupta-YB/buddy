import AVFoundation

/// Plays the MP3 audio that MeloTTS returns for a spoken companion response.
///
/// A reference to the current player is retained for the duration of playback because
/// `AVAudioPlayer` stops immediately if it is deallocated. `isPlaying` lets the overlay keep
/// the cursor visible until the spoken response finishes.
@MainActor
final class SpeechPlaybackService {
    private var audioPlayer: AVAudioPlayer?

    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    func play(audioData: Data) throws {
        let audioPlayer = try AVAudioPlayer(data: audioData)
        self.audioPlayer = audioPlayer
        audioPlayer.prepareToPlay()
        audioPlayer.play()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
