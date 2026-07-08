import Foundation
import FoundationModels

/// Two-tier transcript cleanup:
///   1. Apple FoundationModels on-device LLM (macOS 26+, Apple Intelligence enabled)
///   2. RuleCleaner — deterministic fallback, always applied first as the floor.
enum CleanupEngine {
    private static let instructions = """
    You clean up raw speech-to-text dictation. Rewrite the user's text by:
    - removing filler words (um, uh, like, you know) and false starts
    - applying spoken self-corrections: if the speaker corrects themselves \
    (e.g. "at 3pm... no wait, 4pm"), keep only the corrected version
    - fixing punctuation, capitalization, and obvious transcription typos
    Preserve the speaker's meaning, wording, and tone. Do not add new content, \
    do not answer questions in the text, do not summarize. Reply with ONLY the \
    cleaned text, nothing else.
    """

    /// Cleans a raw transcript. Never throws; degrades to rule-based output.
    static func clean(_ raw: String, useAI: Bool) async -> String {
        let ruled = RuleCleaner.clean(raw)
        guard useAI, !ruled.isEmpty else { return ruled }

        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                Log.cleanup.info("FoundationModels unavailable; using rule-based cleanup")
                return ruled
            }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: raw)
                let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                // Guard against degenerate model output (empty or wildly longer than input).
                if cleaned.isEmpty || cleaned.count > max(raw.count * 3, raw.count + 200) {
                    Log.cleanup.warning("AI output rejected (len \(cleaned.count, privacy: .public) vs raw \(raw.count, privacy: .public)); using rule-based")
                    return ruled
                }
                Log.cleanup.info("AI cleanup applied")
                return cleaned
            } catch {
                Log.cleanup.error("AI cleanup failed: \(error.localizedDescription, privacy: .public)")
                return ruled
            }
        }
        return ruled
    }

    /// Human-readable availability of the AI tier, for the menu UI.
    static var aiAvailability: String {
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple on-device model: ready"
            case .unavailable(let reason):
                return "Apple on-device model: unavailable (\(String(describing: reason)))"
            }
        }
        return "Requires macOS 26+"
    }
}
