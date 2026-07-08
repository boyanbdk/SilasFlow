import Foundation

/// Deterministic post-transcription corrections.
/// The user supplies lines of the form `heard = correct`, e.g.
///   C was Flow = SilasFlow
///   whisper kit = WhisperKit
/// Each `heard` phrase is replaced (case-insensitive, whole-phrase) with `correct`.
enum VocabCorrector {
    struct Rule {
        let heard: String
        let correct: String
    }

    /// Parses the multi-line settings string into rules.
    static func parse(_ raw: String) -> [Rule] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return Rule(heard: parts[0], correct: parts[1])
        }
    }

    /// Applies all rules to `text`. Longer `heard` phrases are applied first so
    /// multi-word replacements win over any overlapping single words.
    static func apply(_ text: String, rules: [Rule]) -> String {
        var result = text
        for rule in rules.sorted(by: { $0.heard.count > $1.heard.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: rule.heard) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result, range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: rule.correct)
                )
            }
        }
        return result
    }

    /// Builds a Whisper decoder prompt from vocabulary terms so the model is
    /// biased toward spelling them correctly during transcription.
    static func prompt(from vocabulary: String, rules: [Rule]) -> String {
        var terms = vocabulary
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // The `correct` side of each rule is also a term worth biasing toward.
        terms.append(contentsOf: rules.map(\.correct))
        let unique = Array(NSOrderedSet(array: terms)) as? [String] ?? terms
        guard !unique.isEmpty else { return "" }
        return unique.joined(separator: ", ")
    }
}
