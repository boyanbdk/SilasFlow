import AppKit
import Carbon.HIToolbox
import Foundation

/// Inserts text into whatever app has focus.
/// Strategy: clipboard + synthesized Cmd-V (needs Accessibility), then restore
/// the previous clipboard. Fallback when Accessibility is denied: leave the
/// text on the clipboard so nothing is lost.
enum TextInjector {
    enum Outcome {
        case pasted
        case copiedOnly // Accessibility missing — text left on clipboard
    }

    @discardableResult
    static func insert(_ text: String, restoreClipboard: Bool) -> Outcome {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(of: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            Log.inject.warning("Accessibility not granted — text copied to clipboard only")
            return .copiedOnly
        }

        sendCmdV()
        Log.inject.info("Pasted \(text.count, privacy: .public) chars into focused app")

        if let saved {
            // Give the target app time to read the pasteboard before restoring.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                restore(saved, to: pasteboard)
            }
        }
        return .pasted
    }

    private static func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
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
