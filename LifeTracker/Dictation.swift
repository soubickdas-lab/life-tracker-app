import Foundation
import Speech
import AVFoundation
import Observation

/// Saying it instead of typing it. Listens in Hindi-as-spoken-in-India, which also
/// catches the English mixed into it, and hands back the words as they come. What
/// was heard goes into the text box — nothing is sent until you send it.
@MainActor
@Observable
final class Dictation {
    var listening = false
    var heard = ""
    var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recogniser: SFSpeechRecognizer? =
        SFSpeechRecognizer(locale: Locale(identifier: "hi-IN"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
        ?? SFSpeechRecognizer()

    func toggle() { listening ? stop() : start() }

    func start() {
        problem = nil
        heard = ""
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.problem = "Speech recognition is switched off for Life Tracker — allow it in Settings."
                    return
                }
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
        }
    }

    func stop() {
        guard listening || task != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func begin() {
        guard let recogniser, recogniser.isAvailable else {
            problem = "Voice typing is not available right now."
            return
        }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif

            let fresh = SFSpeechAudioBufferRecognitionRequest()
            fresh.shouldReportPartialResults = true
            request = fresh

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                fresh.append(buffer)
            }
            engine.prepare()
            try engine.start()
            listening = true

            task = recogniser.recognitionTask(with: fresh) { [weak self] result, error in
                let words = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true || error != nil
                Task { @MainActor in
                    guard let self else { return }
                    if let words { self.heard = words }
                    if finished { self.stop() }
                }
            }
        } catch {
            problem = "Could not start listening."
            stop()
        }
    }
}
