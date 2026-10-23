@preconcurrency import AVFoundation
import NaturalLanguage
import Observation
import Speech

@Observable
final class VoiceController: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentUtterance: AVSpeechUtterance?
    private var hasInstalledAudioTap = false

    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var speakingMessageID: String?
    var errorMessage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startTranscribing() async {
        guard !isListening else { return }

        errorMessage = nil
        stopSpeaking()

        guard await requestSpeechAuthorization() else {
            errorMessage = "Speech recognition permission is required. You can enable it in Settings."
            return
        }
        guard await requestMicrophoneAuthorization() else {
            errorMessage = "Microphone permission is required. You can enable it in Settings."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            errorMessage = "Speech recognition is not currently available."
            return
        }

        cancelRecognition()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceError.microphoneUnavailable
            }

            transcript = ""
            recognitionRequest = request
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledAudioTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self, weak request] result, error in
                DispatchQueue.main.async {
                    guard let self, let request, self.recognitionRequest === request else { return }

                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }

                    if result?.isFinal == true {
                        self.finishRecognition()
                    } else if let error {
                        let shouldReport = self.isListening
                        self.finishRecognition()
                        if shouldReport {
                            self.errorMessage = "Could not recognize speech: \(error.localizedDescription)"
                        }
                    }
                }
            }
        } catch {
            cancelRecognition()
            errorMessage = "Could not start listening: \(error.localizedDescription)"
        }
    }

    func stopTranscribing() {
        guard recognitionRequest != nil else { return }
        stopAudioCapture()
        recognitionRequest?.endAudio()
    }

    func cancelTranscribing() {
        cancelRecognition()
    }

    func toggleSpeaking(messageID: String, text: String) {
        if speakingMessageID == messageID {
            stopSpeaking()
        } else {
            speak(messageID: messageID, text: text)
        }
    }

    func stopAll() {
        cancelRecognition()
        stopSpeaking()
    }

    private func speak(messageID: String, text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        stopTranscribing()
        stopSpeaking()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not start speech playback: \(error.localizedDescription)"
            return
        }

        let utterance = AVSpeechUtterance(string: content)
        let language = NLLanguageRecognizer.dominantLanguage(for: content)?.rawValue
            ?? Locale.preferredLanguages.first
            ?? "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        currentUtterance = utterance
        speakingMessageID = messageID
        synthesizer.speak(utterance)
    }

    private func stopSpeaking() {
        currentUtterance = nil
        speakingMessageID = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func finishRecognition() {
        stopAudioCapture()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func cancelRecognition() {
        if recognitionRequest != nil {
            stopAudioCapture()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completeSpeechIfCurrent(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completeSpeechIfCurrent(utterance)
    }

    private func completeSpeechIfCurrent(_ utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        speakingMessageID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private enum VoiceError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? {
        "No microphone input is available."
    }
}
