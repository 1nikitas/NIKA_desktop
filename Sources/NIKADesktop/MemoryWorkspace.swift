import SwiftUI

struct MemoryWorkspace: View {
    @ObservedObject var store: DesktopStore
    @ObservedObject var workspace: Workspace
    let openChat: () -> Void
    let signIn: () -> Void
    @State private var cloud = false
    @State private var editor = false
    @State private var selected: String?
    @State private var title = ""
    @State private var detail = ""
    @AppStorage("localMemoryEnabled") private var enabled = true
    var body: some View {
        VStack(spacing: 0) {
            Picker("Хранилище", selection: $cloud) { Text("На этом Mac").tag(false); Text("Аккаунт NIKA").tag(true) }.pickerStyle(.segmented).frame(width: 320).padding(24)
            if cloud { CloudSurfaceView(kind: "memory", store: store, workspace: workspace, openChat: openChat, signIn: signIn).id(store.login?.session.clientID) }
            else {
                ScrollView { VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("Память на Mac").font(.largeTitle.weight(.medium)); Spacer(); Button("Запомнить") { selected = nil; title = ""; detail = ""; editor = true } }
                    Toggle("Учитывать эти записи в локальных ответах", isOn: $enabled)
                    Text("Вы сами выбираете, что сохранить. Эти записи не синхронизируются с аккаунтом и не используются в облачных запросах.").font(.callout).foregroundStyle(.secondary)
                    if store.localMemories.isEmpty { EmptyWorkspace(symbol: "brain", title: "Что стоит помнить?", detail: "Предпочтения, привычки и рабочий контекст — только на вашем Mac.") }
                    ForEach(store.localMemories.sorted { $0.isPinned && !$1.isPinned }) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text(item.title).font(.headline); Spacer(); if item.isPinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) } }
                            Text(item.detail).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button("Изменить") { selected = item.id; title = item.title; detail = item.detail; editor = true }
                                Button(item.isPinned ? "Открепить" : "Закрепить") { var items = store.localMemories; if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].isPinned.toggle() }; store.saveMemories(items) }
                                Spacer(); Button("Удалить", role: .destructive) { store.saveMemories(store.localMemories.filter { $0.id != item.id }) }
                            }
                        }.padding(20).nikaGlass()
                    }
                }.padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 850).frame(maxWidth: .infinity) }
            }
        }.sheet(isPresented: $editor) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Запомнить на этом Mac").font(.title2)
                TextField("Название", text: $title).textFieldStyle(.roundedBorder)
                DesktopTextArea(text: $detail, label: "Что запомнить")
                HStack { Button("Отмена") { editor = false }; Spacer(); Button("Сохранить") {
                    var items = store.localMemories
                    if let selected, let i = items.firstIndex(where: { $0.id == selected }) { items[i].title = title; items[i].detail = detail; items[i].updatedAt = Date() }
                    else { items.append(DesktopMemory(title: title, detail: detail)) }
                    store.saveMemories(items); editor = false
                }.buttonStyle(.borderedProminent).disabled(title.isEmpty || detail.isEmpty) }
            }.padding(28).frame(width: 470)
        }
    }
}
