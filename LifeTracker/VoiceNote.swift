import Foundation
import AVFoundation
import Observation

/// Tap, speak, tap. The recording goes to the assistant as it is — it listens far
/// better than the phone's own dictation to Hindi and English mixed together, and
/// writes what it heard in ordinary Latin letters.
@MainActor
@Observable
final class VoiceNote {
    var recording = false
    var seconds = 0
    var problem: String?

    /// Long enough for a thought, short enough to stay a small upload.
    static let limit = 60

    private var recorder: AVAudioRecorder?
    private var clock: Timer?
    private var file: URL { FileManager.default.temporaryDirectory.appendingPathComponent("voice-note.wav") }

    func start() {
        problem = nil
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            Task { @MainActor in
                guard allowed else {
                    self.problem = "The microphone is switched off for Life Tracker — allow it in Settings."
                    return
                }
                self.begin()
            }
        }
    }

    /// Stops and hands back what was recorded — nothing if it was too short to hold a word.
    func finish() -> Data? {
        guard recording else { return nil }
        let long = recorder?.currentTime ?? 0
        halt()
        guard long >= 0.4 else { return nil }
        return try? Data(contentsOf: file)
    }

    func cancel() {
        halt()
        try? FileManager.default.removeItem(at: file)
    }

    private func begin() {
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            /* plain 16 kHz mono speech: small, and understood everywhere */
            let shape: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            try? FileManager.default.removeItem(at: file)
            let fresh = try AVAudioRecorder(url: file, settings: shape)
            guard fresh.record() else { throw NSError(domain: "voice", code: 1) }
            recorder = fresh
            recording = true
            seconds = 0
            clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.seconds += 1 }
            }
        } catch {
            problem = "Could not start recording."
            halt()
        }
    }

    private func halt() {
        clock?.invalidate()
        clock = nil
        recorder?.stop()
        recorder = nil
        recording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
