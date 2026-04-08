import SwiftUI

struct LibraryView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: LibraryViewModel?
    @State private var showingNewNotebookSheet = false
    @State private var newNotebookTitle = ""

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 24)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let vm = viewModel {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(vm.notebooks) { notebook in
                            NavigationLink(value: notebook) {
                                NotebookCoverTile(notebook: notebook)
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    vm.delete(notebook)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newNotebookTitle = ""
                        showingNewNotebookSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .navigationDestination(for: Notebook.self) { notebook in
                NotebookView(notebook: notebook)
            }
            .sheet(isPresented: $showingNewNotebookSheet) {
                newNotebookSheet
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = LibraryViewModel(repo: container.notebooks)
                }
                viewModel?.reload()
            }
        }
    }

    private var newNotebookSheet: some View {
        NavigationStack {
            Form {
                TextField("Notebook title", text: $newNotebookTitle)
            }
            .navigationTitle("New notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingNewNotebookSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newNotebookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        viewModel?.createNotebook(title: title)
                        showingNewNotebookSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct NotebookCoverTile: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: notebook.coverColor) ?? .blue)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    Text(notebook.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                }
                .shadow(radius: 4, y: 2)
            Text(notebook.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8)  & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }
}
