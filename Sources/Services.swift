import Foundation
import AppKit
import SQLite3
import Vision
import CoreGraphics
import Darwin

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - 本地词典（SQLite，离线）

final class DictionaryStore {
    static let shared = DictionaryStore()
    private var db: OpaquePointer?
    private var stmt: OpaquePointer?
    private let queue = DispatchQueue(label: "minidict.dict")

    struct Entry {
        var us: String?
        var uk: String?
        var zh: String?
        var ex: String?
    }

    private init() {
        guard let path = Bundle.main.resourcePath?.appending("/dict.sqlite") else { return }
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK { return }
        sqlite3_prepare_v2(db, "SELECT us, uk, zh, ex FROM dict WHERE word = ?1", -1, &stmt, nil)
    }

    func lookup(_ word: String) -> Entry? {
        var result: Entry?
        queue.sync {
            guard let stmt = stmt else { return }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return }
            result = Entry(us: col(0), uk: col(1), zh: col(2), ex: col(3))
        }
        return result
    }

    private func col(_ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: c)
    }

    func annotate(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z]+(?:['’\\-][A-Za-z]+)*") else { return text }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ipaList: [String] = []
        for m in regex.matches(in: text, range: full) {
            let word = ns.substring(with: m.range)
            let key = word.lowercased()
            if let e = lookup(key), let ipa = e.us ?? e.uk {
                ipaList.append("/\(ipa)/")
            } else {
                ipaList.append(word)
            }
        }
        return ipaList.joined(separator: " ")
    }
}

// MARK: - 划词取词（模拟 ⌘C + 剪贴板交换）

final class SelectionGrabber {
    static let shared = SelectionGrabber()

    func grab(completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()

        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            completion(nil)
            return
        }
        let vkC: CGKeyCode = 0x08
        let down = CGEvent(keyboardEventSource: src, virtualKey: vkC, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vkC, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let text = pb.string(forType: .string)
            pb.clearContents()
            if let s = saved, !s.isEmpty { pb.setString(s, forType: .string) }
            
            if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(t)
            } else if let s = saved, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(s)
            } else {
                completion(nil)
            }
        }
    }
}

// MARK: - OCR（截屏 + Vision 识别，离线）

final class OCRService {
    static let shared = OCRService()

    func capture(rect: CGRect, screen: NSScreen) -> CGImage? {
        let displayKey = NSDeviceDescriptionKey("NSScreenNumber")
        let displayID = (screen.deviceDescription[displayKey] as? CGDirectDisplayID) ?? CGMainDisplayID()
        guard let full = Self.screenCapture(displayID) else { return nil }
        let scale = screen.backingScaleFactor
        let pixelRect = CGRect(x: rect.minX * scale,
                               y: (screen.frame.height - rect.maxY) * scale,
                               width: rect.width * scale,
                               height: rect.height * scale)
        return full.cropping(to: pixelRect) ?? full
    }

    private static let screenCapture: (CGDirectDisplayID) -> CGImage? = {
        typealias Fn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(handle, "CGDisplayCreateImage") else {
            return { _ in nil }
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        return { id in fn(id)?.takeRetainedValue() }
    }()

    func recognize(image: CGImage, completion: @escaping (String?) -> Void) {
        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
            completion(lines?.joined(separator: "\n"))
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: image).perform([request])
        }
    }
}

// MARK: - 翻译（MyMemory 免费接口，联网）

final class Translator {
    static let shared = Translator()

    func translate(_ text: String, sourceIsChinese: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        if SettingsManager.shared.engine == .openAI {
            translateWithOpenAI(text, sourceIsChinese: sourceIsChinese, completion: completion)
        } else {
            translateWithMyMemory(text, sourceIsChinese: sourceIsChinese, completion: completion)
        }
    }

    private func translateWithOpenAI(_ text: String, sourceIsChinese: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        let config = SettingsManager.shared.openAIConfig
        guard let url = URL(string: config.url) else {
            completion(.failure(NSError(domain: "MiniDict", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的 API URL"])))
            return
        }
        
        let systemPrompt = sourceIsChinese ? "Translate the following Chinese text to English. Return only the translation, no extra explanations." : "Translate the following English text to Chinese. Return only the translation, no extra explanations."
        
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "MiniDict", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析响应失败"])))
                return
            }
            
            if let error = obj["error"] as? [String: Any], let msg = error["message"] as? String {
                completion(.failure(NSError(domain: "MiniDict", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }
            
            guard let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let translated = message["content"] as? String else {
                completion(.failure(NSError(domain: "MiniDict", code: -1, userInfo: [NSLocalizedDescriptionKey: "大模型未返回预期格式"])))
                return
            }
            
            completion(.success(translated.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }

    private func translateWithMyMemory(_ text: String, sourceIsChinese: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        let langpair = sourceIsChinese ? "zh-CN|en" : "en|zh-CN"
        let maxBytes = 450
        var qtext = text
        var truncated = false
        while qtext.data(using: .utf8)?.count ?? 0 > maxBytes {
            qtext = String(qtext.dropLast())
            truncated = true
        }
        if truncated { qtext += "…" }

        guard var comps = URLComponents(string: "https://api.mymemory.translated.net/get") else {
            completion(.failure(NSError(domain: "MiniDict", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "请求构建失败"])))
            return
        }
        comps.queryItems = [
            URLQueryItem(name: "q", value: qtext),
            URLQueryItem(name: "langpair", value: langpair),
        ]
        guard let url = comps.url else {
            completion(.failure(NSError(domain: "MiniDict", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "请求构建失败"])))
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rd = obj["responseData"] as? [String: Any],
                  let translated = rd["translatedText"] as? String,
                  !translated.isEmpty,
                  !translated.contains("MYMEMORY WARNING") else {
                completion(.failure(NSError(domain: "MiniDict", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "翻译服务响应异常"])))
                return
            }
            completion(.success(translated))
        }.resume()
    }
}
