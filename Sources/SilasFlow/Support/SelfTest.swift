import Foundation

/// Headless pipeline test: transcribe a WAV file → cleanup → print → exit.
/// Usage: SilasFlow --selftest /path/to/audio.wav [--no-ai] [--model NAME]
/// Exercises AudioFileLoader → Transcriber → CleanupEngine without needing
/// microphone, Accessibility, or a UI session.
enum SelfTest {
    /// --mictest N: N consecutive 2s record/stop cycles from one process,
    /// printing RMS each time. Proves the mic doesn't go silent on cycle ≥2
    /// (the fresh-engine-per-session fix). Requires mic permission.
    static func runMicTestIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flagIndex = args.firstIndex(of: "--mictest") else { return false }
        var cycles = 3
        if args.count > flagIndex + 1, let n = Int(args[flagIndex + 1]) { cycles = n }

        Task {
            let granted = await Permissions.requestMicrophone()
            guard granted else {
                print("[mictest] FAILED: microphone permission not granted")
                exit(1)
            }
            let recorder = Recorder()
            var failures = 0
            for i in 1...cycles {
                do {
                    try recorder.start()
                    try await Task.sleep(for: .seconds(2))
                    let samples = recorder.stop()
                    let rms = samples.isEmpty ? 0 : sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
                    let silent = rms < 0.001
                    if silent { failures += 1 }
                    print(String(format: "[mictest] cycle %d: %d samples, rms %.5f %@", i, samples.count, rms, silent ? "SILENT ❌" : "OK ✅"))
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    print("[mictest] cycle \(i) error: \(error)")
                    failures += 1
                }
            }
            print(failures == 0 ? "[mictest] PASS — no silent cycles" : "[mictest] FAIL — \(failures) silent cycle(s)")
            exit(failures == 0 ? 0 : 1)
        }
        return true
    }

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

                let rules = VocabCorrector.parse(Settings.shared.corrections)
                let promptText = VocabCorrector.prompt(from: Settings.shared.vocabulary, rules: rules)
                print("[selftest] vocab prompt: \"\(promptText)\" | \(rules.count) correction rule(s)")

                let sttStart = Date()
                let raw = try await transcriber.transcribe(samples, promptText: promptText)
                print("[selftest] transcribe took \(String(format: "%.2f", -sttStart.timeIntervalSinceNow))s")
                print("[selftest] RAW: \(raw)")

                let cleanStart = Date()
                var cleaned = await CleanupEngine.clean(raw, useAI: useAI)
                cleaned = VocabCorrector.apply(cleaned, rules: rules)
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
