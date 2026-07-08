import AppKit
import Foundation
import SwiftUI

/// Orchestrates the dictation pipeline:
/// hotkey down → record → hotkey up → transcribe → clean → inject.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum State: Equatable {
        case loadingModel
        case idle
        case recording
        case processing
        case error(String)

        var label: String {
            switch self {
            case .loadingModel: return "Loading speech model…"
            case .idle: return "Ready — hold the hotkey and speak"
            case .recording: return "Listening…"
            case .processing: return "Transcribing…"
            case .error(let message): return message
            }
        }

        var menuBarSymbol: String {
            switch self {
            case .loadingModel: return "hourglass"
            case .idle: return "mic"
            case .recording: return "mic.fill"
            case .processing: return "waveform"
            case .error: return "mic.slash"
            }
        }
    }

    @Published private(set) var state: State = .loadingModel
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastOutcome: String = ""
    @Published var micGranted = Permissions.microphoneGranted
    @Published var accessibilityGranted = Permissions.accessibilityGranted
    @Published var launchAtLogin = LoginItem.isEnabled

    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let hotkey = HotkeyManager()
    private let settings = Settings.shared

    private init() {}

    /// Called once at app launch.
    func start() {
        hotkey.onPressDown = { [weak self] in
            Task { @MainActor in self?.beginRecording() }
        }
        hotkey.onPressUp = { [weak self] in
            Task { @MainActor in self?.endRecordingAndProcess() }
        }
        applyHotkeyFromSettings()

        // Load the model immediately; request the mic in parallel so a pending
        // TCC dialog never blocks startup.
        Task { await loadModel() }
        Task {
            micGranted = await Permissions.requestMicrophone()
            if !micGranted {
                Log.app.warning("Microphone permission not granted (yet)")
            }
        }
    }

    /// (Re)loads the WhisperKit model named in settings.
    func loadModel() async {
        state = .loadingModel
        do {
            try await transcriber.load(model: settings.modelName)
            state = .idle
        } catch {
            state = .error("Model load failed: \(error.localizedDescription)")
        }
    }

    /// Registers the combo currently selected in settings (call after changes).
    func applyHotkeyFromSettings() {
        let combo = HotkeyManager.presets.first { $0.id == settings.hotkeyID }
            ?? HotkeyManager.presets[0]
        hotkey.activate(combo: combo)
    }

    func refreshPermissions() {
        micGranted = Permissions.microphoneGranted
        accessibilityGranted = Permissions.accessibilityGranted
        launchAtLogin = LoginItem.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchAtLogin = LoginItem.isEnabled
    }

    /// Diagnostic: after a short countdown (so you can click into a text field),
    /// paste a marker string. Confirms Accessibility/paste works without dictating.
    func runPasteTest() {
        refreshPermissions()
        Diag.log("TEST: paste test requested (AXIsProcessTrusted=\(TextInjector.canPaste)). Countdown 3s…")
        state = .processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            let outcome = TextInjector.testPaste()
            self?.lastOutcome = outcome == .pasted
                ? "Test: pasted automatically ✅"
                : "Test: Accessibility denied — copied only ❌"
            self?.refreshPermissions()
            self?.state = .idle
        }
    }

    // MARK: - Pipeline

    private func beginRecording() {
        guard state == .idle else { return }
        refreshPermissions()
        guard micGranted else {
            state = .error("Microphone access needed — grant it in System Settings → Privacy → Microphone")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                if case .error = self?.state { self?.state = .idle }
            }
            return
        }
        do {
            try recorder.start()
            state = .recording
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func endRecordingAndProcess() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        // Ignore accidental taps shorter than ~0.3 s.
        guard samples.count > Int(Recorder.sampleRate * 0.3) else {
            state = .idle
            return
        }
        state = .processing
        let useAI = settings.aiCleanup
        let restoreClipboard = settings.restoreClipboard
        let rules = VocabCorrector.parse(settings.corrections)
        let promptText = VocabCorrector.prompt(from: settings.vocabulary, rules: rules)

        Diag.log("PIPELINE: recorded \(String(format: "%.2f", Double(samples.count) / Recorder.sampleRate))s, transcribing…")
        Task {
            do {
                let raw = try await transcriber.transcribe(samples, promptText: promptText)
                Diag.log("PIPELINE: raw transcript = \"\(raw)\"")
                guard !raw.isEmpty else {
                    Diag.log("PIPELINE: empty transcript, nothing to inject")
                    lastOutcome = "Didn't catch that — heard only silence. Try again?"
                    state = .idle
                    return
                }
                var cleaned = await CleanupEngine.clean(raw, useAI: useAI)
                cleaned = VocabCorrector.apply(cleaned, rules: rules)
                lastTranscript = cleaned
                let outcome = TextInjector.insert(cleaned, restoreClipboard: restoreClipboard)
                lastOutcome = outcome == .pasted
                    ? "Pasted automatically ✅"
                    : "Copied — press ⌘V (grant Accessibility for auto-paste)"
                refreshPermissions()
                state = .idle
            } catch {
                Diag.log("PIPELINE: transcription failed: \(error)")
                state = .error("Transcription failed: \(error.localizedDescription)")
            }
        }
    }
}
