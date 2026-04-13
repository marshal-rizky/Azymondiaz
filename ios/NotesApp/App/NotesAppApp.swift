// ios/NotesApp/App/NotesAppApp.swift
import SwiftUI

@main
struct NotesAppApp: App {
    @State private var container = AppContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(container)
                .preferredColorScheme(.dark)
        }
    }
}
