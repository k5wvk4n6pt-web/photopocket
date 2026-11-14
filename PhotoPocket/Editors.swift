import SwiftUI
import SwiftData

/// 分類の作成・編集
struct CategoryEditor: View {
    let target: CategoryEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [PhotoCategory]

    @State private var name = ""
    @State private var symbol = CategorySymbol.all[0]
    @State private var colorName = "pink"

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(FolderColor.color(named: colorName).opacity(0.16))
                                .frame(width: 76, height: 76)
                                .overlay {
                                    Image(systemName: symbol)
                                        .font(.system(size: 34, weight: .semibold))
                                        .foregroundStyle(FolderColor.color(named: colorName))
                                }
                            Text(name.isEmpty ? "分類の名前" : name)
                                .font(.title3.bold())
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section("分類の名前") {
                    TextField("例：子ども、家族、書類", text: $name)
                }
                Section("色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(FolderColor.all, id: \.name) { item in
                            Button { colorName = item.name } label: {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colorName == item.name {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.label)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("アイコン") {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(CategorySymbol.all, id: \.self) { s in
                            Button { symbol = s } label: {
                                Image(systemName: s)
                                    .font(.title3)
                                    .frame(width: 48, height: 48)
                                    .background(symbol == s ? FolderColor.color(named: colorName).opacity(0.22) : Color(.tertiarySystemFill),
                                                in: Circle())
                                    .foregroundStyle(symbol == s ? FolderColor.color(named: colorName) : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(isNew ? "新しい分類" : "分類を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if case .edit(let c) = target {
                    name = c.name
                    symbol = c.symbol
                    colorName = c.colorName
                }
            }
        }
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .new:
            let order = (categories.map(\.sortOrder).max() ?? -1) + 1
            context.insert(PhotoCategory(name: trimmed, symbol: symbol, colorName: colorName, sortOrder: order))
        case .edit(let c):
            c.name = trimmed
            c.symbol = symbol
            c.colorName = colorName
        }
        try? context.save()
        dismiss()
    }
}

/// フォルダの作成・編集
struct FolderEditor: View {
    let target: FolderEditTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @State private var showUnlock = false
    @Query(sort: [SortDescriptor(\PhotoCategory.sortOrder), SortDescriptor(\PhotoCategory.createdAt)])
    private var categories: [PhotoCategory]

    @State private var name = ""
    @State private var category: PhotoCategory?
    @State private var colorName = "orange"

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            IconBadge(symbol: "folder.fill", color: FolderColor.color(named: colorName), size: 72)
                            Text(name.isEmpty ? "フォルダの名前" : name)
                                .font(.title3.bold())
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                            if let category {
                                Text(category.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section("フォルダの名前") {
                    TextField("例：運動会、保険の書類、旅行2026", text: $name)
                }
                Section("分類") {
                    Picker("分類", selection: $category) {
                        Text("未分類").tag(PhotoCategory?.none)
                        ForEach(categories) { c in
                            Label(c.name, systemImage: c.symbol).tag(Optional(c))
                        }
                    }
                }
                Section("色") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(FolderColor.all, id: \.name) { item in
                            Button { colorName = item.name } label: {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 36, height: 36)
                                    .overlay(Circle().strokeBorder(.white.opacity(colorName == item.name ? 0.9 : 0), lineWidth: 3))
                                    .overlay {
                                        if colorName == item.name {
                                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.label)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .sheet(isPresented: $showUnlock) { UnlockView().environmentObject(store) }
            .navigationTitle(isNew ? "新しいフォルダ" : "フォルダを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                switch target {
                case .new(let c):
                    category = c
                case .edit(let f):
                    name = f.name
                    category = f.category
                    colorName = f.colorName
                }
            }
        }
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch target {
        case .new:
            // 無料版はフォルダ3つまで
            guard FreeLimit.canAddFolder(store: store, context: context) else {
                showUnlock = true
                return
            }
            let order = (category?.folderArray.map(\.sortOrder).max() ?? -1) + 1
            context.insert(PhotoFolder(name: trimmed, category: category, colorName: colorName, sortOrder: order))
        case .edit(let f):
            f.name = trimmed
            f.category = category
            f.colorName = colorName
        }
        try? context.save()
        dismiss()
    }
}

/// 写真の移動先フォルダを選ぶ
struct MoveSheet: View {
    let currentFolder: PhotoFolder?
    let onSelect: (PhotoFolder) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\PhotoCategory.sortOrder), SortDescriptor(\PhotoCategory.createdAt)])
    private var categories: [PhotoCategory]
    @Query(sort: [SortDescriptor(\PhotoFolder.sortOrder), SortDescriptor(\PhotoFolder.createdAt)])
    private var folders: [PhotoFolder]

    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { c in
                    if !c.folderArray.isEmpty {
                        Section {
                            ForEach(c.sortedFolders) { row($0) }
                        } header: {
                            Label(c.name, systemImage: c.symbol)
                        }
                    }
                }
                let none = folders.filter { $0.category == nil }
                if !none.isEmpty {
                    Section("未分類") {
                        ForEach(none) { row($0) }
                    }
                }
            }
            .navigationTitle("移動先のフォルダ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
    }

    private func row(_ folder: PhotoFolder) -> some View {
        Button {
            onSelect(folder)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(folder.color)
                Text(folder.name).foregroundStyle(.primary)
                Spacer()
                if folder.id == currentFolder?.id {
                    Text("現在").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(folder.id == currentFolder?.id)
    }
}
