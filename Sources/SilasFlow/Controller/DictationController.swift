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
    @Published var micGranted = Permissions.microphoneGranted
    @Published var accessibilityGranted = Permissions.accessibilityGranted

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

        Task {
            do {
                let raw = try await transcriber.transcribe(samples)
                guard !raw.isEmpty else {
                    state = .idle
                    return
                }
                let cleaned = await CleanupEngine.clean(raw, useAI: useAI)
                lastTranscript = cleaned
                TextInjector.insert(cleaned, restoreClipboard: restoreClipboard)
                refreshPermissions()
                state = .idle
            } catch {
                state = .error("Transcription failed: \(error.localizedDescription)")
            }
        }
    }
}
