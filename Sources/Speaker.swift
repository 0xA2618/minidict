import AppKit
import AVFoundation

final class Speaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = Speaker()
    private let avSynth = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var activeDataTask: URLSessionDataTask?
    private var highlightTimer: Timer?
    private var currentSpeakingText: String = ""
    private var serverProcess: Process?

    var onWordHighlight: ((NSRange, String) -> Void)?
    var onSpeechEnded: (() -> Void)?

    private override init() {
        super.init()
        avSynth.delegate = self
        ensureKokoroDaemon()
    }

    private func ensureKokoroDaemon() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pythonBin = "\(home)/.minidict/kokoro/.venv/bin/python"
        let serverScript = "\(home)/.minidict/kokoro/server.py"

        guard FileManager.default.isExecutableFile(atPath: pythonBin),
              FileManager.default.fileExists(atPath: serverScript) else {
            return
        }

        guard let url = URL(string: "http://127.0.0.1:51731/health") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.5

        let task = URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: pythonBin)
                proc.arguments = [serverScript]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    self?.serverProcess = proc
                } catch {}
            }
        }
        task.resume()
    }

    func speak(_ text: String, language: String) {
        stop()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentSpeakingText = trimmed

        let voiceID = language.hasPrefix("zh") ? SettingsManager.shared.chineseVoice : SettingsManager.shared.englishVoice
        let speed = SettingsManager.shared.speechRate

        if voiceID.hasPrefix("kokoro_") {
            let voiceName = String(voiceID.dropFirst("kokoro_".count))
            speakWithKokoro(trimmed, voice: voiceName, speed: speed, fallbackLanguage: language)
            return
        }

        if voiceID == "youdao_us" || voiceID == "youdao_uk" {
            let type = (voiceID == "youdao_uk") ? 1 : 2
            speakWithYoudao(trimmed, type: type, fallbackLanguage: language)
            return
        }

        if voiceID == "edge_tts" {
            speakWithEdgeTTS(trimmed, language: language)
            return
        }

        speakWithAppleVoice(trimmed, voiceID: voiceID, speed: speed, language: language)
    }

    private func speakWithKokoro(_ text: String, voice: String, speed: Double, fallbackLanguage: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let httpUrl = URL(string: "http://127.0.0.1:51731/tts?text=\(encoded)&voice=\(voice)&speed=\(String(format: "%.2f", speed))") else {
            speakWithKokoroCLI(text, voice: voice, speed: speed, fallbackLanguage: fallbackLanguage)
            return
        }

        var req = URLRequest(url: httpUrl)
        req.timeoutInterval = 3.5

        activeDataTask = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if error == nil, let data = data, data.count > 1000,
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let durationStr = http.value(forHTTPHeaderField: "X-Audio-Duration") ?? ""
                let duration = Double(durationStr) ?? 0.0

                DispatchQueue.main.async {
                    do {
                        self.audioPlayer = try AVAudioPlayer(data: data)
                        self.audioPlayer?.play()
                        let finalDuration = duration > 0 ? duration : (self.audioPlayer?.duration ?? 2.0)
                        self.startWordHighlightSimulation(text: text, duration: finalDuration)
                    } catch {
                        self.speakWithKokoroCLI(text, voice: voice, speed: speed, fallbackLanguage: fallbackLanguage)
                    }
                }
                return
            }

            self.speakWithKokoroCLI(text, voice: voice, speed: speed, fallbackLanguage: fallbackLanguage)
        }
        activeDataTask?.resume()
    }

    private func speakWithKokoroCLI(_ text: String, voice: String, speed: Double, fallbackLanguage: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pythonBin = "\(home)/.minidict/kokoro/.venv/bin/python"
        let scriptPath = "\(home)/.minidict/kokoro/tts.py"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("minidict_kokoro.wav")

        guard FileManager.default.isExecutableFile(atPath: pythonBin),
              FileManager.default.fileExists(atPath: scriptPath) else {
            speakWithAppleVoice(text, voiceID: "", speed: speed, language: fallbackLanguage)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: pythonBin)
            process.arguments = [
                scriptPath,
                "--text", text,
                "--voice", voice,
                "--speed", String(format: "%.2f", speed),
                "--output", fileURL.path
            ]
            process.standardOutput = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                var duration: Double = 0.0
                if let outStr = String(data: data, encoding: .utf8) {
                    for line in outStr.components(separatedBy: .newlines) {
                        if line.hasPrefix("KOKORO_META:") {
                            let jsonStr = String(line.dropFirst("KOKORO_META:".count))
                            if let jdata = jsonStr.data(using: .utf8),
                               let dict = try? JSONSerialization.jsonObject(with: jdata) as? [String: Any],
                               let d = dict["duration"] as? Double {
                                duration = d
                            }
                        }
                    }
                }

                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: fileURL.path) {
                    DispatchQueue.main.async {
                        do {
                            self.audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                            self.audioPlayer?.play()
                            let finalDuration = duration > 0 ? duration : (self.audioPlayer?.duration ?? 2.0)
                            self.startWordHighlightSimulation(text: text, duration: finalDuration)
                        } catch {
                            self.speakWithAppleVoice(text, voiceID: "", speed: speed, language: fallbackLanguage)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.speakWithAppleVoice(text, voiceID: "", speed: speed, language: fallbackLanguage)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.speakWithAppleVoice(text, voiceID: "", speed: speed, language: fallbackLanguage)
                }
            }
        }
    }

    private func startWordHighlightSimulation(text: String, duration: Double) {
        highlightTimer?.invalidate()

        let nsString = text as NSString
        var wordRanges: [NSRange] = []
        var wordWeights: [Double] = []

        if let regex = try? NSRegularExpression(pattern: "\\S+") {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            for m in matches {
                wordRanges.append(m.range)
                let wordStr = nsString.substring(with: m.range)
                var weight = max(Double(wordStr.count), 2.0)
                if wordStr.hasSuffix(".") || wordStr.hasSuffix(",") || wordStr.hasSuffix("!") || wordStr.hasSuffix("?") {
                    weight += 2.5
                }
                wordWeights.append(weight)
            }
        }

        guard !wordRanges.isEmpty else { return }

        let totalWeight = wordWeights.reduce(0, +)
        var cumulativeTimes: [Double] = []
        var cur: Double = 0
        for w in wordWeights {
            cumulativeTimes.append(cur)
            cur += (w / totalWeight) * duration
        }

        let startTime = Date()
        var lastIndex = -1

        highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self = self else {
                t.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= duration {
                t.invalidate()
                self.highlightTimer = nil
                self.onSpeechEnded?()
                return
            }

            var activeIndex = 0
            for (i, cTime) in cumulativeTimes.enumerated() {
                if elapsed >= cTime {
                    activeIndex = i
                } else {
                    break
                }
            }

            if activeIndex != lastIndex, activeIndex < wordRanges.count {
                lastIndex = activeIndex
                self.onWordHighlight?(wordRanges[activeIndex], text)
            }
        }
    }

    private func speakWithYoudao(_ text: String, type: Int, fallbackLanguage: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=\(type)") else {
            speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: fallbackLanguage)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        activeDataTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard error == nil, let data = data, data.count > 500,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                DispatchQueue.main.async {
                    self.speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: fallbackLanguage)
                }
                return
            }

            DispatchQueue.main.async {
                do {
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioPlayer?.play()
                    let dur = self.audioPlayer?.duration ?? 1.5
                    self.startWordHighlightSimulation(text: text, duration: dur)
                } catch {
                    self.speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: fallbackLanguage)
                }
            }
        }
        activeDataTask?.resume()
    }

    private func speakWithAppleVoice(_ text: String, voiceID: String, speed: Double, language: String) {
        let isChinese = language.hasPrefix("zh")
        let targetLang = isChinese ? "zh-CN" : "en-US"

        let utterance = AVSpeechUtterance(string: text)
        if !voiceID.isEmpty, let matchedVoice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = matchedVoice
        } else if let langVoice = AVSpeechSynthesisVoice(language: targetLang) {
            utterance.voice = langVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: isChinese ? "zh" : "en")
        }

        let adjustedRate = Float(0.50 * speed)
        utterance.rate = min(max(adjustedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        avSynth.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onWordHighlight?(characterRange, utterance.speechString)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onSpeechEnded?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.onSpeechEnded?()
        }
    }

    private func speakWithEdgeTTS(_ text: String, language: String) {
        let voice = language.hasPrefix("zh") ? "zh-CN-XiaoxiaoNeural" : "en-US-JennyNeural"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("minidict_tts.mp3")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let edgePath = "/opt/homebrew/bin/edge-tts"
            
            guard FileManager.default.isExecutableFile(atPath: edgePath) else {
                DispatchQueue.main.async {
                    self.speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: language)
                }
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: edgePath)
            process.arguments = ["--text", text, "--voice", voice, "--write-media", fileURL.path]

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: fileURL.path) {
                    DispatchQueue.main.async {
                        do {
                            self.audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                            self.audioPlayer?.play()
                            let dur = self.audioPlayer?.duration ?? 1.5
                            self.startWordHighlightSimulation(text: text, duration: dur)
                        } catch {
                            self.speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: language)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: language)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.speakWithAppleVoice(text, voiceID: "", speed: 1.0, language: language)
                }
            }
        }
    }

    func stop() {
        highlightTimer?.invalidate()
        highlightTimer = nil
        onSpeechEnded?()

        activeDataTask?.cancel()
        activeDataTask = nil

        if avSynth.isSpeaking {
            avSynth.stopSpeaking(at: .immediate)
        }

        audioPlayer?.stop()
        audioPlayer = nil
    }

    func englishVoices() -> [String] {
        var result = [
            "youdao_us",
            "youdao_uk",
            "kokoro_af_heart",
            "kokoro_af_bella",
            "kokoro_bf_emma",
            "kokoro_bm_george"
        ]

        let appleVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" || $0.language == "en-GB" }
            .sorted { $0.name < $1.name }
            .map { $0.identifier }

        result.append(contentsOf: appleVoices)
        result.append("edge_tts")
        return result
    }
    
    func chineseVoices() -> [String] {
        var voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-CN" }
            .sorted { $0.name < $1.name }
            .map { $0.identifier }

        voices.append("edge_tts")
        return voices
    }

    func displayName(for identifier: String) -> String {
        switch identifier {
        case "youdao_us":
            return "🌟 真人原声 · 美音 (有道词典)"
        case "youdao_uk":
            return "🌟 真人原声 · 英音 (有道词典)"
        case "kokoro_af_heart":
            return "🎙️ Kokoro-82M 离线 · 美音 Heart (顶级自然)"
        case "kokoro_af_bella":
            return "🎙️ Kokoro-82M 离线 · 美音 Bella"
        case "kokoro_bf_emma":
            return "🎙️ Kokoro-82M 离线 · 英音 Emma (伦敦腔)"
        case "kokoro_bm_george":
            return "🎙️ Kokoro-82M 离线 · 英音 George (绅士男声)"
        case "edge_tts":
            return "☁️ 微软 Edge 神经网络语音 (需网络)"
        default:
            if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return " \(voice.name) (\(voice.language))"
            }
            return identifier
        }
    }
}
