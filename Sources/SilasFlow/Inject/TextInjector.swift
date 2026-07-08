import AppKit
import ApplicationServices
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

    private static var lastPasteAt: Date?

    @discardableResult
    static func insert(_ text: String, restoreClipboard: Bool) -> Outcome {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(of: pasteboard) : nil

        guard AXIsProcessTrusted() else {
            // Manual-paste fallback: leave the raw text (no auto-spacing, since
            // the user positions the cursor themselves).
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            Diag.log("INJECT: AXIsProcessTrusted=false → copied \(text.count) chars to clipboard only (press ⌘V yourself)")
            return .copiedOnly
        }

        // Auto-space: prepend a space when the cursor sits right after a word so
        // consecutive dictations don't jam together ("happy.you" → "happy. you").
        let out = needsLeadingSpace() ? " " + text : text
        pasteboard.clearContents()
        pasteboard.setString(out, forType: .string)
        lastPasteAt = Date()

        // Let the pasteboard settle before synthesizing the keystroke; some
        // apps read the pasteboard lazily on the ⌘V event.
        usleep(60_000) // 60 ms
        sendCmdV()
        Diag.log("INJECT: posted ⌘V for \(out.count) chars (leadingSpace=\(out.hasPrefix(" ")))")

        if let saved {
            // Give the target app time to read the pasteboard before restoring.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                restore(saved, to: pasteboard)
            }
        }
        return .pasted
    }

    /// Decides whether to prepend a space. Reads the character before the caret
    /// in the focused text field via the Accessibility API:
    ///   - caret at field start, or preceding char already whitespace → no space
    ///   - preceding char is a normal character → add a space
    ///   - can't determine (app doesn't expose AX text) → add a space only if we
    ///     pasted recently (likely appending to earlier dictation)
    private static func needsLeadingSpace() -> Bool {
        switch precedingIsWhitespaceOrStart() {
        case .some(true): return false
        case .some(false): return true
        case .none:
            if let last = lastPasteAt, Date().timeIntervalSince(last) < 300 { return true }
            return false
        }
    }

    /// true = caret at start or preceded by whitespace; false = preceded by a
    /// normal char; nil = undeterminable.
    private static func precedingIsWhitespaceOrStart() -> Bool? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        if range.location <= 0 { return true } // caret at field start

        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String else { return nil }
        let units = Array(text.utf16)
        let idx = range.location - 1
        guard idx >= 0, idx < units.count, let scalar = Unicode.Scalar(units[idx]) else { return nil }
        let ch = Character(scalar)
        return ch.isWhitespace || ch.isNewline
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
