#if os(iOS)
import Speech
import AVFoundation

/// Wraps SFSpeechRecognizer + AVAudioEngine for live voice transcription.
/// All mutation is MainActor-isolated; audio tap callbacks hop back via Task.
@MainActor
final class DictationEngine: NSObject {
    var isListening = false

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false

    /// Request permission then begin transcription. `onTranscription` fires on MainActor with
    /// the best partial or final string. Stops automatically when speech ends or on error.
    func start(onTranscription: @escaping @MainActor (String) -> Void) async {
        let authorized = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard authorized else { return }
        stop()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let inputNode = audioEngine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
            req.append(buf)
        }
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stop()
            return
        }

        isListening = true

        recognitionTask = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in
                if let result {
                    onTranscription(result.bestTranscription.formattedString)
                }
                if error != nil || result?.isFinal == true {
                    self?.stop()
                }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        isListening = false
    }
}
#endif
