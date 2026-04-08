import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTemplate") private var defaultTemplateRaw: String = PageTemplateKind.line.rawValue
    @AppStorage("themePreference") private var themePreference: String = "system"

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
            Section("AI") {
                Text("Plan C will add PC server URL, Groq keys, and voice language here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
