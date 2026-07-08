import Foundation

/// Headless pipeline test: transcribe a WAV file → cleanup → print → exit.
/// Usage: SilasFlow --selftest /path/to/audio.wav [--no-ai] [--model NAME]
/// Exercises AudioFileLoader → Transcriber → CleanupEngine without needing
/// microphone, Accessibility, or a UI session.
enum SelfTest {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--selftest"), args.count > flagIndex + 1 else {
            return false
        }
        let path = args[flagIndex + 1]
        let useAI = !args.contains("--no-ai")
        var model = Settings.shared.modelName
        if let modelIndex = args.firstIndex(of: "--model"), args.count > modelIndex + 1 {
            model = args[modelIndex + 1]
        }

        Task {
            do {
                print("[selftest] model=\(model) ai=\(useAI) file=\(path)")
                let samples = try AudioFileLoader.load(url: URL(fileURLWithPath: path))
                print("[selftest] loaded \(samples.count) samples (\(String(format: "%.2f", Double(samples.count) / Recorder.sampleRate))s)")

                let transcriber = Transcriber()
                let loadStart = Date()
                try await transcriber.load(model: model)
                print("[selftest] model ready in \(String(format: "%.1f", -loadStart.timeIntervalSinceNow))s")

                let sttStart = Date()
                let raw = try await transcriber.transcribe(samples)
                print("[selftest] transcribe took \(String(format: "%.2f", -sttStart.timeIntervalSinceNow))s")
                print("[selftest] RAW: \(raw)")

                let cleanStart = Date()
                let cleaned = await CleanupEngine.clean(raw, useAI: useAI)
                print("[selftest] cleanup took \(String(format: "%.2f", -cleanStart.timeIntervalSinceNow))s (ai: \(CleanupEngine.aiAvailability))")
                print("[selftest] CLEANED: \(cleaned)")
                exit(0)
            } catch {
                print("[selftest] FAILED: \(error)")
                exit(1)
            }
        }
        return true
    }
}
