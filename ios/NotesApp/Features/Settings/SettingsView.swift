// ios/NotesApp/Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @AppStorage("defaultTemplate") private var defaultTemplateRaw: String = PageTemplateKind.line.rawValue
    @AppStorage("voiceLanguage")   private var voiceLanguage: String = "auto"

    @State private var pcURL: String = ""
    @State private var keysText: String = ""
    @State private var savedMessage: String?
    @State private var syncStatus: String = "idle"

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            List {
                settingsSection("Paper") {
                    Picker("Default template", selection: $defaultTemplateRaw) {
                        Text("Line").tag(PageTemplateKind.line.rawValue)
                        Text("Grid").tag(PageTemplateKind.grid.rawValue)
                        Text("Blank").tag(PageTemplateKind.blank.rawValue)
                    }
                    .tint(AppColors.gold)
                }
                settingsSection("AI routing") {
                    HStack {
                        Text("Active").font(AppFonts.body).foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(container.aiRouter.activeLabel)
                            .font(AppFonts.caption).fontWeight(.semibold)
                            .foregroundStyle(AppColors.gold)
                    }
                }
                settingsSection("PC companion server") {
                    TextField("http://192.168.1.10:8000", text: $pcURL)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                settingsSection("Groq API keys (one per line)") {
                    TextEditor(text: $keysText)
                        .frame(minHeight: 100)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                settingsSection("Voice") {
                    Picker("Language", selection: $voiceLanguage) {
                        Text("Auto detect").tag("auto")
                        Text("English").tag("en")
                        Text("Indonesian").tag("id")
                        Text("Code-switching (id+en)").tag("id,en")
                    }
                    .tint(AppColors.gold)
                }
                settingsSection("") {
                    Button("Save AI configuration") { saveConfig() }
                        .font(AppFonts.bodyBold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppColors.goldGradient)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                    if let msg = savedMessage {
                        Text(msg)
                            .font(AppFonts.caption)
                            .foregroundStyle(msg.contains("failed") ? .red : AppColors.gold)
                    }
                }
                settingsSection("Sync") {
                    HStack {
                        Text("Status").font(AppFonts.body).foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(syncStatus).font(AppFonts.caption).foregroundStyle(AppColors.textTertiary)
                    }
                    Button("Sync now") {
                        Task {
                            await container.syncScheduler?.syncNow()
                            syncStatus = container.syncScheduler?.status ?? "idle"
                        }
                    }
                    .font(AppFonts.body)
                    .foregroundStyle(container.syncClient == nil ? AppColors.textTertiary : AppColors.gold)
                    .disabled(container.syncClient == nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { loadConfig() }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title.uppercased())
                .font(AppFonts.sectionHeader)
                .tracking(0.8)
                .foregroundStyle(AppColors.textTertiary)
        }
        .listRowBackground(AppColors.surface2)
        .listRowSeparatorTint(AppColors.border)
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
            savedMessage = "Saved — \(container.aiRouter.activeLabel)"
        } catch {
            savedMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
