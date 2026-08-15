import Foundation
import AppKit

// MARK: - 文本工具

func containsChinese(_ s: String) -> Bool {
    s.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
}

func englishTokens(in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "[A-Za-z]+(?:['’\\-][A-Za-z]+)*") else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range) }
}

let exchangeName: [String: String] = [
    "p": "过去式", "d": "过去分词", "i": "现在分词", "3": "第三人称单数",
    "r": "比较级", "t": "最高级", "s": "复数"
]

func phoneticLine(_ e: DictionaryStore.Entry) -> String? {
    var parts: [String] = []
    if let us = e.us { parts.append("美 /\(us)/") }
    if let uk = e.uk { parts.append("英 /\(uk)/") }
    return parts.isEmpty ? nil : parts.joined(separator: "  ")
}

struct DictCard: Equatable {
    var word: String
    var phonetics: String?
    var meanings: [String]
    var exchanges: [String]
}

func parseDictCard(word: String, e: DictionaryStore.Entry) -> DictCard {
    var meanings: [String] = []
    if let zh = e.zh {
        for l in zh.split(separator: "\n") { meanings.append(String(l)) }
    }
    var exchanges: [String] = []
    if let ex = e.ex {
        for item in ex.split(separator: "/") {
            let kv = item.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let val = String(kv[1])
            exchanges.append("\(exchangeName[key] ?? key): \(val)")
        }
    }
    return DictCard(word: word, phonetics: phoneticLine(e), meanings: meanings, exchanges: exchanges)
}

final class AppFocusManager {
    static let shared = AppFocusManager()
    private(set) var previousApp: NSRunningApplication?

    func recordFrontmostApp() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }
    }

    func restorePreviousApp() {
        let app = previousApp
        previousApp = nil
        if let app = app, !app.isTerminated {
            app.activate()
        }
        NSApp.hide(nil)
    }
}
