import SwiftUI

/// The Settings window: General + Dictionary tabs.
struct SettingsView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DictionaryTab()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
        }
        .frame(width: 560, height: 430)
        .environmentObject(controller)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            controller.refreshPermissions()
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject private var controller: DictationController
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Hold to dictate", selection: $settings.hotkeyID) {
                    ForEach(HotkeyManager.presets) { combo in
                        Text(combo.label).tag(combo.id)
                    }
                }
                .onChange(of: settings.hotkeyID) {
                    controller.applyHotkeyFromSettings()
                }

                Picker("Speech model", selection: $settings.modelName) {
                    ForEach(Settings.availableModels, id: \.self) { Text($0) }
                }
                .onChange(of: settings.modelName) {
                    Task { await controller.loadModel() }
                }
            }

            Section("Cleanup") {
                Toggle("AI cleanup (on-device)", isOn: $settings.aiCleanup)
                Text(CleanupEngine.aiAvailability)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Restore clipboard after paste", isOn: $settings.restoreClipboard)
                Toggle("Launch at login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
            }

            Section("Permissions") {
                permissionRow(
                    granted: controller.micGranted,
                    label: "Microphone",
                    detail: "Required to hear you.",
                    action: {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                        )
                    }
                )
                permissionRow(
                    granted: controller.accessibilityGranted,
                    label: "Accessibility",
                    detail: "Required to paste at your cursor. Relaunch after granting.",
                    action: {
                        Permissions.promptAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                )
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(granted: Bool, label: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading) {
                Text(label)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings…", action: action)
            }
        }
    }
}

// MARK: - Dictionary

private struct DictionaryTab: View {
    @ObservedObject private var settings = Settings.shared

    @State private var words: [String] = []
    @State private var newWord: String = ""
    @State private var rows: [CorrectionRow] = []

    struct CorrectionRow: Identifiable {
        let id = UUID()
        var heard: String
        var correct: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Vocabulary
            Text("Vocabulary").font(.headline)
            Text("Names and jargon the transcriber should recognize.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Add a word or phrase…", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button("Add", action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(words, id: \.self) { word in
                        HStack(spacing: 4) {
                            Text(word).font(.callout)
                            Button {
                                words.removeAll { $0 == word }
                                saveWords()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
            .frame(height: 34)

            Divider()

            // Corrections
            HStack {
                Text("Corrections").font(.headline)
                Spacer()
                Button {
                    rows.append(CorrectionRow(heard: "", correct: ""))
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
            }
            Text("When a phrase is misheard, replace it. Applied after every dictation (case-insensitive).")
                .font(.caption).foregroundStyle(.secondary)

            List {
                ForEach($rows) { $row in
                    HStack(spacing: 8) {
                        TextField("When it hears…", text: $row.heard)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Replace with…", text: $row.correct)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            rows.removeAll { $0.id == row.id }
                            saveRows()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listStyle(.inset)
            .onChange(of: rows.map { "\($0.heard)|\($0.correct)" }) {
                saveRows()
            }
        }
        .padding(16)
        .onAppear(perform: load)
    }

    private func load() {
        words = settings.vocabulary
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        rows = VocabCorrector.parse(settings.corrections).map {
            CorrectionRow(heard: $0.heard, correct: $0.correct)
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !words.contains(where: { $0.lowercased() == word.lowercased() }) else {
            newWord = ""
            return
        }
        words.append(word)
        newWord = ""
        saveWords()
    }

    private func saveWords() {
        settings.vocabulary = words.joined(separator: ", ")
    }

    private func saveRows() {
        settings.corrections = rows
            .filter { !$0.heard.trimmingCharacters(in: .whitespaces).isEmpty
                   && !$0.correct.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.heard.trimmingCharacters(in: .whitespaces)) = \($0.correct.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")
    }
}
