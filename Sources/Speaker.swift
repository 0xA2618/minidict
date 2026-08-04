import AppKit
import AVFoundation

final class Speaker {
    static let shared = Speaker()
    private var synth: NSSpeechSynthesizer?
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    func speak(_ text: String, language: String) {
        stop()

        let voiceID = language.hasPrefix("zh") ? SettingsManager.shared.chineseVoice : SettingsManager.shared.englishVoice

        if voiceID == "edge_tts" {
            speakWithEdgeTTS(text, language: language)
            return
        }

        if let s = NSSpeechSynthesizer(voice: NSSpeechSynthesizer.VoiceName(rawValue: voiceID)) {
            synth = s
            s.startSpeaking(text)
        }
    }

    private func speakWithEdgeTTS(_ text: String, language: String) {
        let voice = language.hasPrefix("zh") ? "zh-CN-XiaoxiaoNeural" : "en-US-JennyNeural"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("minidict_tts.mp3")

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/edge-tts")
            process.arguments = ["--text", text, "--voice", voice, "--write-media", fileURL.path]

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        do {
                            self.audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                            self.audioPlayer?.play()
                        } catch {
                            print("Audio play error:", error)
                        }
                    }
                }
            } catch {
                print("edge-tts error:", error)
            }
        }
    }

    func stop() {
        if let s = synth, s.isSpeaking {
            s.stopSpeaking()
        }
        synth = nil

        audioPlayer?.stop()
        audioPlayer = nil
    }

    func englishVoices() -> [String] {
        var voices = NSSpeechSynthesizer.availableVoices
            .filter { $0.rawValue.contains("en-US") }
            .map { $0.rawValue }
            .sorted()
        voices.insert("edge_tts", at: 0)
        return voices
    }
    
    func chineseVoices() -> [String] {
        let localeKey = NSSpeechSynthesizer.VoiceAttributeKey(rawValue: "VoiceLocaleIdentifier")
        var voices = NSSpeechSynthesizer.availableVoices
            .filter { v in
                let locale = NSSpeechSynthesizer.attributes(forVoice: v)[localeKey] as? String ?? ""
                return locale.hasPrefix("zh_CN")
            }
            .map { $0.rawValue }
            .sorted()
        voices.insert("edge_tts", at: 0)
        return voices
    }

    func displayName(for identifier: String) -> String {
        if identifier == "edge_tts" {
            return "✨ 微软 Edge 神经网络音色 (推荐)"
        }
        let nameKey = NSSpeechSynthesizer.VoiceAttributeKey(rawValue: "VoiceNameRoot")
        let voice = NSSpeechSynthesizer.VoiceName(rawValue: identifier)
        let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
        if let n = attrs[nameKey] as? String, !n.isEmpty { return n }
        return identifier
    }
}
