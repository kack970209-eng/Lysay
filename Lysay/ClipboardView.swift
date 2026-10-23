import SwiftUI

/// 粘贴板：剪贴板记录（复制过的文字）+ 收藏文件夹
struct ClipboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var tab = 0
    @State private var newFolder = false
    @State private var folderName = ""

    var body: some View {
        List {
            Section {
                Picker("", selection: $tab) {
                    Text("剪贴板记录").tag(0)
                    Text("收藏文件夹").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if tab == 0 { historySection } else { foldersSection }
        }
        .navigationTitle("粘贴板")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if tab == 1 {
                    EditButton()
                    Button {
                        folderName = ""
                        newFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                } else if !coordinator.library.visibleHistory.isEmpty {
                    Button("清空", role: .destructive) { coordinator.clearHistory() }
                }
            }
        }
        .alert("新建文件夹", isPresented: $newFolder) {
            TextField("文件夹名称", text: $folderName)
            Button("取消", role: .cancel) {}
            Button("建立") { coordinator.addFolder(folderName) }
        }
        .onAppear { coordinator.reloadLibrary() }
    }

    @ViewBuilder
    private var historySection: some View {
        let history = coordinator.library.visibleHistory
        Section {
            if history.isEmpty {
                ContentUnavailableView("还没有剪贴板记录",
                                       systemImage: "doc.on.clipboard",
                                       description: Text("在任何 App 复制文字后，打开 Lysay 键盘就会自动记下来。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(history) { item in
                    HistoryRow(item: item)
                }
                .onDelete { offsets in
                    coordinator.deleteHistory(offsets.map { history[$0].id })
                }
            }
        } footer: {
            Text("最多保留 100 条。点一下复制，左滑删除，长按可收进文件夹。")
        }
    }

    @ViewBuilder
    private var foldersSection: some View {
        let folders = coordinator.library.visibleFolders
        Section {
            if folders.isEmpty {
                ContentUnavailableView("还没有文件夹",
                                       systemImage: "folder",
                                       description: Text("点右上角新建文件夹，在里面保存常用的文字，例如地址、常用回复。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(folders) { folder in
                    NavigationLink {
                        FolderView(folderId: folder.id)
                    } label: {
                        HStack {
                            Label(folder.name, systemImage: "folder.fill")
                            Spacer()
                            Text("\(coordinator.library.items(in: folder.id).count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { coordinator.deleteFolder(folders[i].id) }
                }
                .onMove(perform: coordinator.moveFolders)
            }
        } footer: {
            Text("文件夹里的内容会出现在键盘粘贴板的“收藏”里，点一下即可输入。")
        }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    let item: ClipHistoryItem
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = item.text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                Text(copied ? "已复制" : item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(copied ? Color.lysay : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            let folders = coordinator.library.visibleFolders
            if folders.isEmpty {
                Text("先建立文件夹才能收藏")
            }
            ForEach(folders) { f in
                Button {
                    coordinator.saveHistory(item, to: f.id)
                } label: {
                    Label("收进「\(f.name)」", systemImage: "folder")
                }
            }
        }
    }
}

/// 文件夹内容
struct FolderView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    let folderId: UUID
    @State private var editing: ClipItem?
    @State private var showNew = false
    @State private var rename = false
    @State private var newName = ""

    private var folder: ClipFolder? { coordinator.library.visibleFolders.first { $0.id == folderId } }

    var body: some View {
        let items = coordinator.library.items(in: folderId)
        List {
            if items.isEmpty {
                ContentUnavailableView("文件夹是空的",
                                       systemImage: "text.badge.plus",
                                       description: Text("点右上角 + 写入要保存的文字。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    Button {
                        editing = item
                    } label: {
                        Text(item.text)
                            .lineLimit(4)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onDelete { offsets in coordinator.deleteItems(offsets.map { items[$0].id }) }
                .onMove { coordinator.moveItems(in: folderId, from: $0, to: $1) }
            }
        }
        .navigationTitle(folder?.name ?? "文件夹")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newName = folder?.name ?? ""
                        rename = true
                    } label: {
                        Label("重命名", systemImage: "pencil")
                    }
                    Button {
                        if let s = UIPasteboard.general.string { coordinator.addItem(s, to: folderId) }
                    } label: {
                        Label("从系统剪贴板添加", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("重命名文件夹", isPresented: $rename) {
            TextField("文件夹名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") { coordinator.renameFolder(folderId, to: newName) }
        }
        .sheet(isPresented: $showNew) {
            ClipEditor(title: "新增内容", text: "") { coordinator.addItem($0, to: folderId) }
        }
        .sheet(item: $editing) { item in
            ClipEditor(title: "编辑内容", text: item.text) { coordinator.updateItem(item.id, text: $0) }
        }
    }
}

struct ClipEditor: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(.horizontal, 12)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            onSave(text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
