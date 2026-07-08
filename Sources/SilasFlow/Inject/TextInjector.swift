import AppKit
import Carbon.HIToolbox
import Foundation

/// Inserts text into whatever app has focus.
/// Strategy: clipboard + synthesized Cmd-V (needs Accessibility), then restore
/// the previous clipboard. Fallback when Accessibility is denied: leave the
/// text on the clipboard so nothing is lost.
enum TextInjector {
    enum Outcome: Equatable {
        case pasted
        case copiedOnly // Accessibility missing — text left on clipboard
    }

    /// Whether we're currently trusted to synthesize keystrokes.
    static var canPaste: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func insert(_ text: String, restoreClipboard: Bool) -> Outcome {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(of: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            Diag.log("INJECT: AXIsProcessTrusted=false → copied \(text.count) chars to clipboard only (press ⌘V yourself)")
            return .copiedOnly
        }

        // Let the pasteboard settle before synthesizing the keystroke; some
        // apps read the pasteboard lazily on the ⌘V event.
        usleep(60_000) // 60 ms
        sendCmdV()
        Diag.log("INJECT: AXIsProcessTrusted=true → posted ⌘V for \(text.count) chars")

        if let saved {
            // Give the target app time to read the pasteboard before restoring.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                restore(saved, to: pasteboard)
            }
        }
        return .pasted
    }

    /// Diagnostic: paste a known marker string right now (used by the menu's
    /// "Test paste" button after a countdown). Returns the outcome.
    @discardableResult
    static func testPaste() -> Outcome {
        insert("SilasFlow paste OK ✅", restoreClipboard: true)
    }

    private static func sendCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Diag.log("INJECT: failed to create CGEventSource")
            return
        }
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(20_000) // 20 ms between down and up
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard snapshot/restore

    private static func snapshot(of pasteboard: NSPasteboard) -> [[String: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type.rawValue] = data
                }
            }
            return entry
        }
    }

    private static func restore(_ items: [[String: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (raw, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(raw))
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
