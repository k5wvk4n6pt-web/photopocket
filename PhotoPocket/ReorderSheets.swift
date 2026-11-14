import SwiftUI
import SwiftData

/// 分類の編集・並び替え
struct CategoryReorderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\PhotoCategory.sortOrder), SortDescriptor(\PhotoCategory.createdAt)])
    private var categories: [PhotoCategory]
    @State private var editingCategory: CategoryEditTarget?
    @State private var categoryToDelete: PhotoCategory?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { c in
                        Button { editingCategory = .edit(c) } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(c.color.opacity(0.16))
                                    .frame(width: 36, height: 36)
                                    .overlay(Image(systemName: c.symbol).foregroundStyle(c.color))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).foregroundStyle(.primary)
                                    Text("フォルダ\(c.folderArray.count)つ・\(c.allPhotos.count)枚")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { categoryToDelete = c } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("右の「≡」を上下にドラッグすると並び替えられます。分類をタップすると、名前・色・アイコンを変えられます。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("分類の編集・並び替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $editingCategory) { CategoryEditor(target: $0) }
            .deleteCategoryDialog($categoryToDelete)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = categories
        list.move(fromOffsets: source, toOffset: destination)
        for (i, c) in list.enumerated() { c.sortOrder = i }
        try? context.save()
    }
}

/// 分類の中のフォルダの編集・並び替え
struct FolderReorderSheet: View {
    let category: PhotoCategory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var editingFolder: FolderEditTarget?
    @State private var folderToDelete: PhotoFolder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(category.sortedFolders) { f in
                        Button { editingFolder = .edit(f) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.title3)
                                    .foregroundStyle(f.color)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).foregroundStyle(.primary)
                                    Text("\(f.photoArray.count)枚").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { folderToDelete = f } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                    .onMove(perform: move)
                } header: {
                    Label(category.name, systemImage: category.symbol)
                } footer: {
                    Text("右の「≡」を上下にドラッグすると並び替えられます。フォルダをタップすると、名前・色・分類を変えられます。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("フォルダの編集・並び替え")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $editingFolder) { FolderEditor(target: $0) }
            .deleteFolderDialog($folderToDelete)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = category.sortedFolders
        list.move(fromOffsets: source, toOffset: destination)
        for (i, f) in list.enumerated() { f.sortOrder = i }
        try? context.save()
    }
}
