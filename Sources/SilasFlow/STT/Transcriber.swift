import Foundation
import WhisperKit

/// On-device speech-to-text via WhisperKit (CoreML, Apple Neural Engine).
/// The model is auto-downloaded on first use, then cached — offline thereafter.
actor Transcriber {
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    /// Loads (downloading if needed) the given Whisper model.
    func load(model: String) async throws {
        if loadedModel == model, whisperKit != nil { return }
        whisperKit = nil
        loadedModel = nil
        Log.stt.info("Loading WhisperKit model \(model, privacy: .public)…")
        let config = WhisperKitConfig(model: model)
        let kit = try await WhisperKit(config)
        whisperKit = kit
        loadedModel = model
        Log.stt.info("WhisperKit model \(model, privacy: .public) ready")
    }

    var isReady: Bool { whisperKit != nil }

    /// Transcribes 16 kHz mono Float32 samples to raw text.
    ///
    /// NOTE: we deliberately do NOT pass `DecodingOptions.promptTokens` for
    /// vocabulary biasing. Doing so corrupts WhisperKit's decoder KV-cache,
    /// which persists on the reused instance and makes every call after the
    /// first return an empty transcript. Vocabulary is instead handled by the
    /// corrections map and the AI-cleanup instructions, neither of which touch
    /// the decoder state. `language = "en"` is safe across reuse and skips
    /// language auto-detection.
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisperKit else { throw TranscriberError.modelNotLoaded }
        let start = Date()

        var options = DecodingOptions()
        options.language = "en"
        options.usePrefillPrompt = true

        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = Date().timeIntervalSince(start)
        Log.stt.info("Transcribed \(samples.count, privacy: .public) samples in \(elapsed, format: .fixed(precision: 2), privacy: .public)s: \"\(text, privacy: .private(mask: .hash))\"")
        return text
    }
}

enum TranscriberError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Speech model is not loaded yet."
        }
    }
}
