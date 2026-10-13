import SwiftUI
struct ConversationModelPicker: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var library: ModelLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Модель для разговора").font(.title2); Spacer(); Button("Готово") { dismiss() } }
            TextField("Найти модель", text: $search).textFieldStyle(.roundedBorder)
            List {
                Section("На этом Mac · без отправки в облако") {
                    ForEach(library.models.filter { library.installed.contains($0.id) && $0.auxiliaryFor == nil && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) { model in
                        Button { workspace.selectProvider(model.id); dismiss() } label: { Label(model.name, systemImage: "lock.shield") }
                    }
                }
                Section("Облако NIKA") {
                    Button("Модель по умолчанию") { workspace.selectProvider("cloud"); workspace.cloudModel = ""; dismiss() }
                    ForEach(workspace.store.models.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, id: \.id) { model in
                        Button { workspace.selectProvider("cloud"); workspace.cloudModel = model.id; dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) { Text(model.name); if let context = model.contextLength { Text("Контекст: \(context) токенов").font(.caption).foregroundStyle(.secondary) } }
                        }
                    }
                }
            }.listStyle(.inset)
            Text("Переход между локальной и облачной моделью начинает новый разговор.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: DesktopFormLayout.width(530), height: DesktopFormLayout.height(520)).task { await workspace.store.fetchModels() }
    }
}
