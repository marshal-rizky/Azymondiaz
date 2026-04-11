import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @AppStorage("defaultTemplate") private var defaultTemplateRaw: String = PageTemplateKind.line.rawValue
    @AppStorage("themePreference") private var themePreference: String = "system"
    @AppStorage("voiceLanguage") private var voiceLanguage: String = "auto"

    @State private var pcURL: String = ""
    @State private var keysText: String = ""
    @State private var savedMessage: String?
    @State private var syncStatus: String = "idle"

    var body: some View {
        Form {
            Section("Paper") {
                Picker("Default template", selection: $defaultTemplateRaw) {
                    Text("Line").tag(PageTemplateKind.line.rawValue)
                    Text("Grid").tag(PageTemplateKind.grid.rawValue)
                    Text("Blank").tag(PageTemplateKind.blank.rawValue)
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $themePreference) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section("AI routing") {
                Text("Active: \(container.aiRouter.activeLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("PC companion server") {
                TextField("http://192.168.1.10:8000", text: $pcURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section("Groq API keys (one per line)") {
                TextEditor(text: $keysText)
                    .frame(minHeight: 120)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            Section("Voice") {
                Picker("Language", selection: $voiceLanguage) {
                    Text("Auto detect").tag("auto")
                    Text("English").tag("en")
                    Text("Indonesian").tag("id")
                    Text("Code-switching (id+en)").tag("id,en")
                }
            }
            Section {
                Button("Save AI configuration") {
                    saveConfig()
                }
            }
            Section("Sync") {
                Text(syncStatus)
                Button("Sync now") {
                    Task {
                        await container.syncScheduler?.syncNow()
                        syncStatus = container.syncScheduler?.status ?? "idle"
                    }
                }
                .disabled(container.syncClient == nil)
            }
            if let msg = savedMessage {
                Text(msg).foregroundStyle(.green)
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        pcURL = (try? KeychainStore.shared.getPCServerURL()) ?? ""
        let keys = (try? KeychainStore.shared.getGroqKeys()) ?? []
        keysText = keys.joined(separator: "\n")
        syncStatus = container.syncScheduler?.status ?? "not configured"
    }

    private func saveConfig() {
        do {
            try KeychainStore.shared.setPCServerURL(pcURL)
            let keys = keysText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            try KeychainStore.shared.setGroqKeys(keys)
            container.reloadAI()
            savedMessage = "Saved. Active: \(container.aiRouter.activeLabel)"
        } catch {
            savedMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
