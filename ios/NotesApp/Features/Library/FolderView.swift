// ios/NotesApp/Features/Library/FolderView.swift
import SwiftUI

/// Drilled-in view for a specific folder. Reuses LibraryViewModel layout.
struct FolderView: View {
    let folder: Folder
    /// All ancestor folders from root to the folder ABOVE this one.
    let ancestors: [Folder]

    @Environment(AppContainer.self) private var container
    @State private var viewModel: LibraryViewModel?
    @State private var showingCreationSheet = false
    @State private var newTitle = ""
    @State private var selectedCoverIndex = 0
    @State private var creatingFolder = false

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppSpacing.grid)]

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                breadcrumb
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let vm = viewModel {
                            if !vm.folders.isEmpty {
                                sectionHeader("Subfolders")
                                folderRows(vm: vm)
                            }
                            sectionHeader("Notebooks — \(vm.notebooks.count)")
                            notebookGrid(vm: vm)
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.surface, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
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
                    currentFolderID: folder.id
                )
            }
            viewModel?.reload()
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text("Library")
                    .font(AppFonts.micro)
                    .foregroundStyle(AppColors.textTertiary)
                ForEach(ancestors) { ancestor in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(ancestor.title)
                        .font(AppFonts.micro)
                        .foregroundStyle(AppColors.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary)
                Text(folder.title)
                    .font(AppFonts.micro).fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.vertical, 6)
        }
        .background(AppColors.surface.opacity(0.9))
        .overlay(alignment: .bottom) {
            Divider().background(AppColors.border)
        }
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
            ForEach(vm.folders) { subfolder in
                NavigationLink(destination: FolderView(folder: subfolder,
                                                       ancestors: ancestors + [folder])) {
                    folderRow(subfolder)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) { vm.delete(subfolder) }
                }
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.bottom, 4)
    }

    private func folderRow(_ f: Folder) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.surface3)
                .frame(width: 30, height: 30)
                .overlay(Text("📁").font(.system(size: 15)))
            Text(f.title)
                .font(AppFonts.bodyBold)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
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
                .overlay(RoundedRectangle(cornerRadius: AppRadius.card)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(AppColors.border2))
                .overlay(VStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 22, weight: .light))
                    Text("New").font(AppFonts.micro).fontWeight(.semibold)
                }.foregroundStyle(AppColors.gold))
            Text(" ").font(AppFonts.micro)
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
                        Text("Create a folder instead").font(AppFonts.body).foregroundStyle(AppColors.textPrimary)
                    }.tint(AppColors.gold)
                    if !creatingFolder {
                        Text("Cover".uppercased()).font(AppFonts.sectionHeader).tracking(1).foregroundStyle(AppColors.textTertiary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(0..<LibraryViewModel.coverPalette.count, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(LibraryViewModel.coverPalette[i].asCoverGradient)
                                        .frame(width: 44, height: 60)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(i == selectedCoverIndex ? AppColors.gold : Color.clear, lineWidth: 2))
                                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                                        .onTapGesture { selectedCoverIndex = i }
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                    Spacer()
                }.padding(AppSpacing.page)
            }
            .navigationTitle(creatingFolder ? "New Folder" : "New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreationSheet = false; newTitle = "" }
                        .foregroundStyle(AppColors.gold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        if creatingFolder {
                            viewModel?.createFolder(title: title)
                        } else {
                            viewModel?.createNotebook(title: title,
                                                      coverColor: LibraryViewModel.coverPalette[selectedCoverIndex])
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
}
