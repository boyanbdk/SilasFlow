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
                if !controller.lastOutcome.isEmpty {
                    Text(controller.lastOutcome)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Auto-paste status + test
            HStack {
                Image(systemName: controller.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(controller.accessibilityGranted ? .green : .red)
                Text(controller.accessibilityGranted ? "Auto-paste: ready" : "Auto-paste: OFF (needs Accessibility)")
                    .font(.caption)
            }
            Button("Test paste (click into a text field first)…") {
                controller.runPasteTest()
            }
            .font(.caption)

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
            Toggle("Launch at login", isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }
            ))

            Divider()

            // Custom vocabulary + corrections
            DisclosureGroup("Vocabulary & corrections") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Words to recognize better (comma-separated):")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("SilasFlow, WhisperKit, …", text: $settings.vocabulary, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .lineLimit(1...3)

                    Text("Fix mishears — one per line, \"heard = correct\":")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextEditor(text: $settings.corrections)
                        .font(.caption)
                        .frame(height: 64)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    Text("e.g.  C was Flow = SilasFlow")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
            .font(.caption)

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
