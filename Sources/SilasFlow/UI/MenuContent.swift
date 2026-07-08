import SwiftUI

/// The menu-bar dropdown.
struct MenuContent: View {
    @EnvironmentObject private var controller: DictationController
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status
            HStack {
                Image(systemName: controller.state.menuBarSymbol)
                Text(controller.state.label)
                    .font(.callout)
                    .lineLimit(2)
            }

            if !controller.lastTranscript.isEmpty {
                Divider()
                Text(controller.lastTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Divider()

            // Hotkey
            Picker("Hold to dictate", selection: $settings.hotkeyID) {
                ForEach(HotkeyManager.presets) { combo in
                    Text(combo.label).tag(combo.id)
                }
            }
            .onChange(of: settings.hotkeyID) {
                controller.applyHotkeyFromSettings()
            }

            // Model
            Picker("Speech model", selection: $settings.modelName) {
                ForEach(Settings.availableModels, id: \.self) { Text($0) }
            }
            .onChange(of: settings.modelName) {
                Task { await controller.loadModel() }
            }

            Toggle("AI cleanup (on-device)", isOn: $settings.aiCleanup)
            Text(CleanupEngine.aiAvailability)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Toggle("Restore clipboard after paste", isOn: $settings.restoreClipboard)

            Divider()

            // Permissions
            if !controller.accessibilityGranted {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Accessibility needed to paste at cursor", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                    Text("Until granted, text is copied — press ⌘V yourself. Relaunch after granting.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings…") {
                        Permissions.promptAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .font(.caption)
                }
            }

            Divider()

            Button("Quit SilasFlow") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { controller.refreshPermissions() }
    }
}
