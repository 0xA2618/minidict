import AppKit
import CoreGraphics
import CoreText
import Vision

// MARK: - 无 UI 自测（./MiniDict --selftest）

enum SelfTest {
    static func run() {
        print("== MiniDict 自测 ==")

        let dict = DictionaryStore.shared
        if let e = dict.lookup("apple") {
            print("[dict] apple → us=\(e.us ?? "nil") uk=\(e.uk ?? "nil")")
            print("[dict]   释义: \(e.zh ?? "nil")")
        } else {
            print("[dict] ❌ apple 未命中")
        }

        let ann = dict.annotate("The quick brown fox jumps over the lazy dog.")
        print("[ipa]  \(ann)")

        print("[zh]   containsChinese(\"你好\")=\(containsChinese("你好"))  containsChinese(\"hello\")=\(containsChinese("hello"))")

        testOCR()
        testNetwork()
        print("== 自测结束 ==")
    }

    static func testOCR() {
        let img = renderTextImage("Hello World 你好世界 2024")
        let sem = DispatchSemaphore(value: 0)
        OCRService.shared.recognize(image: img) { text in
            print("[ocr]  识别: \(text ?? "nil")")
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
    }

    static func renderTextImage(_ text: String) -> CGImage {
        let size = CGSize(width: 720, height: 160)
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = CGPoint(x: 20, y: 60)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    static func testNetwork() {
        let sem = DispatchSemaphore(value: 0)
        Translator.shared.translate("The quick brown fox jumps over the lazy dog.", sourceIsChinese: false) { r in
            switch r {
            case .success(let t): print("[net]   en→zh: \(t)")
            case .failure(let e): print("[net]   ❌ \(e.localizedDescription)")
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 20)

        let sem2 = DispatchSemaphore(value: 0)
        Translator.shared.translate("世界那么大，我想去看看", sourceIsChinese: true) { r in
            switch r {
            case .success(let t): print("[net]   zh→en: \(t)")
            case .failure(let e): print("[net]   ❌ \(e.localizedDescription)")
            }
            sem2.signal()
        }
        _ = sem2.wait(timeout: .now() + 20)
    }
}
