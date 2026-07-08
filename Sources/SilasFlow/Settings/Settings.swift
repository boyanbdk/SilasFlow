import Foundation

/// UserDefaults-backed app settings.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    /// WhisperKit model identifier (e.g. "base.en", "small.en", "large-v3_turbo").
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: "modelName") }
    }

    /// Whether the AI (FoundationModels) cleanup pass is applied on top of rule-based cleanup.
    @Published var aiCleanup: Bool {
        didSet { defaults.set(aiCleanup, forKey: "aiCleanup") }
    }

    /// Restore the previous clipboard contents after paste-injection.
    @Published var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") }
    }

    /// ID of the selected push-to-talk combo (see HotkeyManager.presets).
    @Published var hotkeyID: String {
        didSet { defaults.set(hotkeyID, forKey: "hotkeyID") }
    }

    static let availableModels = ["tiny.en", "base.en", "small.en", "large-v3_turbo"]

    private init() {
        defaults.register(defaults: [
            "modelName": "base.en",
            "aiCleanup": true,
            "restoreClipboard": true,
            "hotkeyID": "opt-space",
        ])
        modelName = defaults.string(forKey: "modelName") ?? "base.en"
        aiCleanup = defaults.bool(forKey: "aiCleanup")
        restoreClipboard = defaults.bool(forKey: "restoreClipboard")
        hotkeyID = defaults.string(forKey: "hotkeyID") ?? "opt-space"
    }
}
