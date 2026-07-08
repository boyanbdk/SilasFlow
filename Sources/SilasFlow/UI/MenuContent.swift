import SwiftUI

/// The menu-bar dropdown — intentionally minimal; everything else lives in
/// the Settings window.
struct MenuContent: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

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
                Button("Fix last transcript…") {
                    openWindow(id: "fixTranscript")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .font(.caption)
            }

            Divider()

            if !controller.accessibilityGranted {
                Label("Auto-paste OFF — grant Accessibility in Settings", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Test paste (click into a text field first)…") {
                controller.runPasteTest()
            }
            .font(.caption)

            Divider()

            Button("Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit SilasFlow") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { controller.refreshPermissions() }
    }
}
