import Foundation

/// Deterministic, dependency-free transcript cleanup.
/// Always runs; the guaranteed baseline when the AI pass is off or unavailable.
enum RuleCleaner {
    /// Standalone filler words removed wherever they appear (word-boundary, case-insensitive).
    private static let fillerPattern = #"(?i)\b(?:um+|uh+|uhm+|erm+|hmm+)\b[,.]?\s*"#

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // 1. Strip filler words.
        text = text.replacingOccurrences(of: fillerPattern, with: "", options: .regularExpression)

        // 2. Collapse repeated whitespace and fix space-before-punctuation.
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // 3. Capitalize the first letter.
        text = text.prefix(1).uppercased() + text.dropFirst()

        // 4. Ensure terminal punctuation.
        if let last = text.unicodeScalars.last, !CharacterSet(charactersIn: ".!?…\"')").contains(last) {
            text += "."
        }
        return text
    }
}
