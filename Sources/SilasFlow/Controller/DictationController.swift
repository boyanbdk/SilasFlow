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
    let overlay = OverlayController()

    private init() {
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.overlay.push(level: level) }
        }
    }

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
            overlay.showListening()
        } catch {
            state = .error(error.localizedDescription)
            overlay.showErrorAndHide()
        }
    }

    private func endRecordingAndProcess() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        // Ignore accidental taps shorter than ~0.3 s.
        guard samples.count > Int(Recorder.sampleRate * 0.3) else {
            state = .idle
            overlay.hide()
            return
        }
        state = .processing
        overlay.showProcessing()
        let useAI = settings.aiCleanup
        let restoreClipboard = settings.restoreClipboard
        let rules = VocabCorrector.parse(settings.corrections)
        let vocabulary = settings.vocabulary

        Diag.log("PIPELINE: recorded \(String(format: "%.2f", Double(samples.count) / Recorder.sampleRate))s, transcribing…")
        Task {
            do {
                let raw = try await transcriber.transcribe(samples)
                Diag.log("PIPELINE: raw transcript = \"\(raw)\"")
                guard !raw.isEmpty else {
                    Diag.log("PIPELINE: empty transcript, nothing to inject")
                    lastOutcome = "Didn't catch that — heard only silence. Try again?"
                    state = .idle
                    overlay.showErrorAndHide()
                    return
                }
                var cleaned = await CleanupEngine.clean(raw, useAI: useAI, vocabulary: vocabulary)
                cleaned = VocabCorrector.apply(cleaned, rules: rules)
                lastTranscript = cleaned
                let outcome = TextInjector.insert(cleaned, restoreClipboard: restoreClipboard)
                lastOutcome = outcome == .pasted
                    ? "Pasted automatically ✅"
                    : "Copied — press ⌘V (grant Accessibility for auto-paste)"
                refreshPermissions()
                state = .idle
                overlay.hide()
            } catch {
                Diag.log("PIPELINE: transcription failed: \(error)")
                state = .error("Transcription failed: \(error.localizedDescription)")
                overlay.showErrorAndHide()
            }
        }
    }

    // MARK: - Teach loop ("Fix last transcript")

    /// Diffs the original transcript against the user's correction, saves a
    /// `heard = correct` rule (word-level, common prefix/suffix trimmed), and
    /// adds the corrected phrase to the vocabulary. Returns a description of
    /// what was learned, or nil if nothing usable changed.
    @discardableResult
    func learnCorrection(original: String, corrected: String) -> String? {
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctedTrimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correctedTrimmed.isEmpty, originalTrimmed != correctedTrimmed else { return nil }

        var heardWords = originalTrimmed.split(separator: " ").map(String.init)
        var correctWords = correctedTrimmed.split(separator: " ").map(String.init)

        // Trim the common prefix and suffix so the rule targets just the
        // differing middle segment.
        while let h = heardWords.first, let c = correctWords.first, h == c {
            heardWords.removeFirst(); correctWords.removeFirst()
        }
        while let h = heardWords.last, let c = correctWords.last, h == c {
            heardWords.removeLast(); correctWords.removeLast()
        }
        let heard = heardWords.joined(separator: " ")
        let correct = correctWords.joined(separator: " ")
        guard !heard.isEmpty, !correct.isEmpty else { return nil }

        // Append the rule (skip exact duplicates).
        let newRule = "\(heard) = \(correct)"
        let existing = VocabCorrector.parse(settings.corrections)
        if !existing.contains(where: { $0.heard.lowercased() == heard.lowercased() }) {
            settings.corrections = settings.corrections.isEmpty
                ? newRule
                : settings.corrections + "\n" + newRule
        }

        // Short corrected phrases are worth biasing transcription toward.
        if correctWords.count <= 4 {
            let vocabTerms = settings.vocabulary
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if !vocabTerms.contains(where: { $0.lowercased() == correct.lowercased() }) {
                settings.vocabulary = settings.vocabulary.isEmpty
                    ? correct
                    : settings.vocabulary + ", " + correct
            }
        }

        Diag.log("TEACH: learned \"\(heard)\" → \"\(correct)\"")
        return "Learned: “\(heard)” → “\(correct)”"
    }
}
