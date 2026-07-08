import SwiftUI

/// The "Fix last transcript" teach loop: edit what it should have said,
/// and the correction is learned as a dictionary rule.
struct FixTranscriptView: View {
    @EnvironmentObject private var controller: DictationController
    @Environment(\.dismiss) private var dismiss

    @State private var edited: String = ""
    @State private var original: String = ""
    @State private var learnedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fix last transcript").font(.headline)

            if original.isEmpty {
                Text("Nothing dictated yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text("It heard:")
                    .font(.caption).foregroundStyle(.secondary)
                Text(original)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))

                Text("It should say:")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $edited)
                    .font(.callout)
                    .frame(minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                if let learnedMessage {
                    Label(learnedMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Learn & paste fixed text") {
                        learn(paste: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(edited.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Learn only") {
                        learn(paste: false)
                    }
                    .disabled(edited.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            original = controller.lastTranscript
            edited = controller.lastTranscript
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func learn(paste: Bool) {
        learnedMessage = controller.learnCorrection(original: original, corrected: edited)
            ?? "No change to learn — texts are identical."
        if paste {
            let text = edited.trimmingCharacters(in: .whitespacesAndNewlines)
            // Small delay so the click doesn't interfere with focus, then close
            // this window first so the paste lands in the user's app.
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                TextInjector.insert(text, restoreClipboard: Settings.shared.restoreClipboard)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
        }
    }
}
