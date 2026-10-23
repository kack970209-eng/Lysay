import SwiftUI

/// 粘贴板：保存常用内容，键盘里点一下即可输入。
struct ClipboardView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var editing: ClipItem?
    @State private var showNew = false

    var body: some View {
        List {
            if coordinator.clips.isEmpty {
                ContentUnavailableView("还没有内容",
                                       systemImage: "doc.on.clipboard",
                                       description: Text("点右上角 + 添加常用的文字，例如地址、电话、常用回复。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(coordinator.clips) { item in
                    Button {
                        editing = item
                    } label: {
                        Text(item.text)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onDelete(perform: coordinator.deleteClips)
                .onMove(perform: coordinator.moveClips)
            }
        }
        .navigationTitle("粘贴板")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !coordinator.clips.isEmpty { EditButton() }
                Menu {
                    Button {
                        showNew = true
                    } label: {
                        Label("输入新内容", systemImage: "square.and.pencil")
                    }
                    Button {
                        if let s = UIPasteboard.general.string { coordinator.addClip(s) }
                    } label: {
                        Label("从系统剪贴板添加", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNew) {
            ClipEditor(title: "新增内容", text: "") { coordinator.addClip($0) }
        }
        .sheet(item: $editing) { item in
            ClipEditor(title: "编辑内容", text: item.text) { coordinator.updateClip(item, text: $0) }
        }
    }
}

private struct ClipEditor: View {
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
