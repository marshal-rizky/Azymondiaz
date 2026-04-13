// ios/NotesApp/Features/Library/LibraryView.swift
import SwiftUI

struct LibraryView: View {
    @Environment(AppContainer.self) private var container
    /// nil = Library root.  Set by FolderView when drilling in.
    var currentFolder: Folder? = nil

    @State private var viewModel: LibraryViewModel?
    @State private var showingCreationSheet = false
    @State private var newTitle = ""
    @State private var selectedCoverIndex = 0
    @State private var creatingFolder = false
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppSpacing.grid)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        searchBar
                        if let vm = viewModel {
                            if !vm.folders.isEmpty {
                                sectionHeader("Folders")
                                folderRows(vm: vm)
                            }
                            sectionHeader(currentFolder == nil ? "Notebooks" : "Notebooks — \(vm.notebooks.count)")
                            notebookGrid(vm: vm)
                        }
                    }
                }
            }
            .navigationTitle(currentFolder?.title ?? "My Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if currentFolder == nil {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gear")
                                .foregroundStyle(AppColors.gold)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreationSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 30, height: 30)
                            .background(AppColors.goldGradient)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                    }
                }
            }
            .sheet(isPresented: $showingCreationSheet) { creationSheet }
            .onAppear {
                if viewModel == nil {
                    viewModel = LibraryViewModel(
                        notebookRepo: container.notebooks,
                        folderRepo: container.folders,
                        currentFolderID: currentFolder?.id
                    )
                }
                viewModel?.reload()
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
                .font(.system(size: 14))
            Text("Search notebooks…")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(AppColors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.chip).stroke(AppColors.border, lineWidth: 0.5))
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppFonts.sectionHeader)
            .tracking(1.0)
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Folder rows

    private func folderRows(vm: LibraryViewModel) -> some View {
        VStack(spacing: AppSpacing.stack / 2) {
            ForEach(vm.folders) { folder in
                NavigationLink(destination: FolderView(folder: folder, ancestors: ancestorList())) {
                    folderRow(folder)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(folder) }
                }
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 4)
    }

    private func folderRow(_ folder: Folder) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.surface3)
                .frame(width: 30, height: 30)
                .overlay(Text("📁").font(.system(size: 15)))
            Text(folder.title)
                .font(AppFonts.bodyBold)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            Text("\(subCount(folder)) items")
                .font(AppFonts.caption)
                .foregroundStyle(AppColors.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.border2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border, lineWidth: 0.5))
    }

    // MARK: - Notebook grid

    private func notebookGrid(vm: LibraryViewModel) -> some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.grid) {
            ForEach(vm.notebooks) { notebook in
                NavigationLink(value: notebook) {
                    NotebookCoverTile(notebook: notebook)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(notebook) }
                }
            }
            // "New" tile inline at end of grid
            Button(action: { showingCreationSheet = true }) {
                newTile
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 24)
        .navigationDestination(for: Notebook.self) { notebook in
            NotebookView(notebook: notebook)
        }
    }

    private var newTile: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .fill(Color.clear)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.card)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(AppColors.border2)
                )
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                        Text("New").font(AppFonts.micro).fontWeight(.semibold)
                    }
                    .foregroundStyle(AppColors.gold)
                )
            Text(" ").font(AppFonts.micro)  // spacer matching date label height
        }
    }

    // MARK: - Creation sheet

    private var creationSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Title", text: $newTitle)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(12)
                        .background(AppColors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.chip).stroke(AppColors.border, lineWidth: 0.5))

                    Toggle(isOn: $creatingFolder) {
                        Text("Create a folder instead")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.gold)

                    if !creatingFolder {
                        Text("Cover".uppercased())
                            .font(AppFonts.sectionHeader)
                            .tracking(1)
                            .foregroundStyle(AppColors.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<LibraryViewModel.coverPalette.count, id: \.self) { i in
                                    let gradient = LibraryViewModel.coverPalette[i].asCoverGradient
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(gradient)
                                        .frame(width: 44, height: 60)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(i == selectedCoverIndex ? AppColors.gold : Color.clear,
                                                        lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                                        .onTapGesture { selectedCoverIndex = i }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Spacer()
                }
                .padding(AppSpacing.page)
            }
            .navigationTitle(creatingFolder ? "New Folder" : "New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCreationSheet = false
                        newTitle = ""
                    }
                    .foregroundStyle(AppColors.gold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        if creatingFolder {
                            viewModel?.createFolder(title: title)
                        } else {
                            viewModel?.createNotebook(
                                title: title,
                                coverColor: LibraryViewModel.coverPalette[selectedCoverIndex]
                            )
                        }
                        showingCreationSheet = false
                        newTitle = ""
                        selectedCoverIndex = 0
                        creatingFolder = false
                    }
                    .font(AppFonts.bodyBold)
                    .foregroundStyle(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? AppColors.textTertiary : AppColors.gold)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(AppColors.bg)
        }
    }

    // MARK: - Helpers

    private func ancestorList() -> [Folder] {
        guard let f = currentFolder else { return [] }
        return [f]
    }

    private func subCount(_ folder: Folder) -> Int {
        0  // placeholder — loaded lazily inside FolderView
    }
}

// MARK: - Notebook cover tile

struct NotebookCoverTile: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverRect
            Text(notebook.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(AppFonts.micro)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var coverRect: some View {
        RoundedRectangle(cornerRadius: AppRadius.card)
            .fill(notebook.coverColor.asCoverGradient)
            .aspectRatio(3.0/4.0, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                VStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(0.18)).frame(height: 1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
            .overlay(alignment: .bottomLeading) {
                Text(notebook.title)
                    .font(AppFonts.caption).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(10)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 5)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    .frame(maxHeight: .infinity)
            }
            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
    }
}
