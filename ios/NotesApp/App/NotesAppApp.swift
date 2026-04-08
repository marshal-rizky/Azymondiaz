import SwiftUI

@main
struct NotesAppApp: App {
    @State private var container = AppContainer.makeDefault()
    @AppStorage("themePreference") private var themePreference: String = "system"

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(container)
                .preferredColorScheme(ThemePreference.fromStorage(themePreference).colorScheme)
        }
    }
}
