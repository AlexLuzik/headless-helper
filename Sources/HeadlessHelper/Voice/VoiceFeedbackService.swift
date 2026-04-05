import AppKit
import Foundation

/// Provides text-to-speech feedback using NSSpeechSynthesizer.
/// Used for announcing device lists, connection status, and PIN prompts.
final class VoiceFeedbackService: NSObject, ObservableObject, NSSpeechSynthesizerDelegate {
    private var synthesizer: NSSpeechSynthesizer
    private var queue: [String] = []
    private var isSpeaking = false

    override init() {
        synthesizer = NSSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    /// Set the speech language/voice based on app language setting.
    func setLanguage(_ language: String) {
        let voiceName: String?
        switch language {
        case "uk":
            // Try Ukrainian voices, or any available Ukrainian voice
            voiceName = NSSpeechSynthesizer.availableVoices.first { voice in
                let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
                let locale = attrs[.localeIdentifier] as? String ?? ""
                return locale.hasPrefix("uk")
            }?.rawValue
        default:
            voiceName = nil // system default
        }

        if let voiceName {
            synthesizer = NSSpeechSynthesizer(voice: NSSpeechSynthesizer.VoiceName(rawValue: voiceName))
                ?? NSSpeechSynthesizer()
        } else {
            synthesizer = NSSpeechSynthesizer()
        }
        synthesizer.delegate = self
    }

    /// Speak a single string. Interrupts any current speech.
    func speak(_ text: String) {
        stopSpeaking()
        queue = [text]
        speakNext()
    }

    /// Speak the device list: "1, Device Name. 2, Other Device."
    func speakDeviceList(_ devices: [AirPlayDevice]) {
        stopSpeaking()
        queue = devices.enumerated().map { index, device in
            "\(index + 1), \(device.name)."
        }
        speakNext()
    }

    /// Speak the WiFi network list.
    func speakWiFiList(_ networks: [WiFiNetwork]) {
        stopSpeaking()
        queue = networks.enumerated().map { index, net in
            let status = net.isConnected ? ", connected" : ""
            let security = net.isSecure ? ", secure" : ""
            return "\(index + 1), \(net.name)\(status)\(security)."
        }
        speakNext()
    }

    /// Stop all speech immediately.
    func stopSpeaking() {
        synthesizer.stopSpeaking()
        queue.removeAll()
        isSpeaking = false
    }

    private func speakNext() {
        guard !queue.isEmpty else {
            isSpeaking = false
            return
        }
        isSpeaking = true
        let text = queue.removeFirst()
        synthesizer.startSpeaking(text)
    }

    // MARK: - NSSpeechSynthesizerDelegate

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.speakNext()
        }
    }
}
