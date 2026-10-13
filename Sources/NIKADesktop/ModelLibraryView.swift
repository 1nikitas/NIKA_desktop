import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
    @ObservedObject var library: ModelLibrary
    @ObservedObject var store: DesktopStore
    let use: (DesktopModel) -> Void
    @State private var filter = "Все модели"
    @State private var capability = "Все возможности"
    @State private var importing = false
    @State private var discovery = false
    @State private var selection: DesktopModel?
    @State private var deleting: DesktopModel?
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ваш Mac.\nВаш интеллект.").font(.system(size: 34, weight: .medium, design: .rounded))
                        Text("Установите модель один раз. Общайтесь без интернета.").fixedSize(horizontal: false, vertical: true).font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "desktopcomputer").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(.tertiary).padding(12)
                }
                if library.relocating { ProgressView("Перенос моделей…") }
                if let bytes = library.residentBytes { Label("Движок сейчас использует " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory), systemImage: "memorychip").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 24) {
                    hardware("ПАМЯТЬ MAC", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                    Divider().frame(height: 28)
                    hardware("ДОСТУПНО НА ДИСКЕ", ByteCountFormatter.string(fromByteCount: library.freeBytes, countStyle: .file))
                    Spacer()
                    Label(Self.architecture, systemImage: "cpu").font(.callout).foregroundStyle(.secondary)
                }.padding(20).nikaGlass(radius: 18)
                if geometry.size.width >= 850 {
                    HStack {
                        filterPicker.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 510)
                        Spacer()
                        discoveryActions
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        filterPicker.pickerStyle(.menu).frame(maxWidth: 310)
                        HStack { discoveryActions; Spacer() }
                    }
                }
                Picker("Возможности", selection: $capability) {
                    ForEach(["Все возможности", "Лёгкие · до 1,5 ГБ", "С изображениями", "Для кода"], id: \.self) { Text($0) }
                }.frame(maxWidth: 310)
                let shown = library.models.filter { model in
                    (model.id != "mini" || library.installed.contains(model.id) || library.progress[model.id] != nil) && (filter == "Все модели" || (filter == "Для этого Mac" && library.compatible(model)) || (filter == "Установленные" && library.installed.contains(model.id)) || (filter == "Загрузки" && library.progress[model.id] != nil))
                }
                let filtered = shown.filter { model in
                    capability == "Все возможности" || (capability == "Лёгкие · до 1,5 ГБ" && model.bytes <= 1_500_000_000 && model.auxiliaryFor == nil) || (capability == "С изображениями" && model.visionProjector != nil) || (capability == "Для кода" && !(Set(model.tags ?? []).intersection(["code", "coding", "code-generation"]).isEmpty))
                }
                if filtered.isEmpty { EmptyWorkspace(symbol: "square.stack", title: "Пока пусто", detail: "Выберите модель в каталоге или импортируйте GGUF с вашего Mac.").frame(height: 230) }
                ForEach(filtered) { model in row(model) }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Локально значит локально", systemImage: "lock.shield").font(.headline)
                    Text("Модели загружаются из Hugging Face. После установки запросы обрабатываются на вашем Mac. Облачные инструменты в локальном разговоре не запускаются.")
                        .foregroundStyle(.secondary).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Text("Оценка включает модель, контекст 4096, 1 ГБ для движка и 3 ГБ для macOS. Дополнение для изображений требует памяти отдельно; фактическое потребление зависит от задачи. Совместимость подтверждается загрузкой в движок.")
                        .foregroundStyle(.tertiary).font(.caption)
                }.padding(.top, 4)
            }.frame(width: max(0, min(920, geometry.size.width - 56)), alignment: .leading).padding(28).frame(maxWidth: .infinity)
        }
        }
        .task {
            while !Task.isCancelled { library.residentBytes = await library.runtime.residentMemory(); try? await Task.sleep(for: .seconds(3)) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
            switch result { case .success(let url): Task { await library.importModel(url) }; case .failure(let error): library.error = error.localizedDescription }
        }
        .sheet(isPresented: $discovery) { ModelDiscoveryView(library: library) }
        .sheet(item: $selection) { model in details(model) }
        .confirmationDialog("Удалить файл модели?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let model = deleting { Task { await library.delete(model) } }; deleting = nil }
        } message: { Text("Разговоры сохранятся. Для новых ответов понадобится установить модель снова.") }
        .alert("Локальные модели", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) { Button("Понятно") { library.error = nil } } message: { Text(library.error ?? "") }
    }
    private var filterPicker: some View {
        Picker("Показать", selection: $filter) { ForEach(["Все модели", "Для этого Mac", "Установленные", "Загрузки"], id: \.self) { Text($0) } }
    }
    @ViewBuilder private var discoveryActions: some View {
        Button("Найти модель") { discovery = true }
        Button { importing = true } label: { Label("Импорт GGUF", systemImage: "square.and.arrow.down") }
    }
    static var architecture: String {
        #if arch(arm64)
        "Apple Silicon · Metal"
        #else
        "Intel · CPU"
        #endif
    }
    private func hardware(_ caption: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(caption).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary); Text(value).font(.system(size: 17, weight: .medium, design: .rounded)) } }
    private func row(_ model: DesktopModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: model.id == "mini" ? "leaf" : model.id == "balance" ? "circle.lefthalf.filled" : "sparkles")
                    .font(.system(size: 24, weight: .light)).foregroundStyle(Color.accentColor).frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(model.name).font(.title3.weight(.semibold)); if library.loadedID == model.id { Text("В памяти").font(.caption).foregroundStyle(.green) } }
                    Text(model.imported ? "GGUF · импортировано" : model.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if library.loadingID == model.id { ProgressView("Загрузка в память…").controlSize(.small) }
                else if library.installed.contains(model.id) {
                    Button("Начать разговор") { use(model) }.buttonStyle(.borderedProminent).disabled(model.auxiliaryFor != nil)
                    Menu { Button("Сведения") { selection = model }; Button("Выгрузить из памяти") { Task { await library.unload() } }; Button("Удалить модель", role: .destructive) { deleting = model } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                } else if library.progress[model.id] == nil {
                    Button { library.download(model) } label: { Label(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file), systemImage: "arrow.down") }.buttonStyle(.bordered)
                }
            }
            HStack {
                Text(model.auxiliaryFor != nil ? "Дополнение для обработки изображений на Mac" : model.repository != nil ? "Из каталога Hugging Face · \(model.license ?? "проверьте лицензию")" : model.imported ? "Метаданные модели не проверены" : model.id == "smart" ? "Рекомендуем для Mac с 8 ГБ · контекст до 4096" : model.id == "desktop-quality" ? "Меньше сжатие · рекомендуем от 16 ГБ, особенно для изображений" : model.id == "balance" ? "Экономный вариант, когда открыто много приложений" : "Ранее установленная компактная модель")
                Spacer()
                Button("Подробнее") { selection = model }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }.font(.callout).foregroundStyle(.secondary)
            if !library.compatible(model) { Label("Модель может потребовать больше памяти, чем доступно на этом Mac", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            if let progress = library.progress[model.id] {
                VStack(spacing: 8) {
                    ProgressView(value: progress.fraction)
                    HStack {
                        Text(progress.state).font(.caption)
                        Spacer()
                        Text("\(ByteCountFormatter.string(fromByteCount: progress.received, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))").font(.caption.monospacedDigit())
                        if progress.state == "Загрузка" { Button("Пауза") { library.pause(model) } }
                        else if !progress.state.contains("Проверка SHA") { Button("Продолжить") { library.download(model) } }
                        Button("Отменить") { library.cancel(model) }
                    }.font(.caption).foregroundStyle(.secondary)
                    if progress.received > 0 && progress.state == "Загрузка" {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(progress.speed), countStyle: .file))/с · примерно \(Int(Double(max(0, model.bytes - progress.received)) / max(1, progress.speed))) с осталось")
                            .font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(24).nikaGlass(radius: 20)
    }
    private func details(_ model: DesktopModel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(model.name).font(.largeTitle.weight(.medium)); Spacer(); Button("Готово") { selection = nil } }
            LabeledContent("Издатель", value: model.publisher)
            LabeledContent("Параметры", value: model.parameters)
            LabeledContent("Квантование", value: model.quantization)
            LabeledContent("Формат / движок", value: "GGUF / llama.cpp")
            LabeledContent("Лицензия", value: model.license ?? (model.imported || model.repository != nil ? "Проверьте у издателя" : "Apache 2.0 · проверено 11.10.2026"))
            LabeledContent("Размер", value: ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))
            LabeledContent("Память с запасом для macOS", value: ByteCountFormatter.string(fromByteCount: model.memoryEstimate, countStyle: .memory))
            LabeledContent("Контекст", value: model.contextLimit.map { "\($0) токенов · по данным издателя" } ?? "Настраивается · максимум модели не проверен")
            LabeledContent("Возможности приложения", value: model.visionProjector == nil ? "Текст · текстовые PDF" : "Текст · PDF · изображения с дополнением")
            if let vision = model.visionProjector {
                if let item = library.visionModel(model), library.installed.contains(item.id) { Label("Работа с изображениями установлена", systemImage: "checkmark.circle") }
                else { Button("Работа с изображениями · " + ByteCountFormatter.string(fromByteCount: vision.bytes, countStyle: .file)) { library.downloadVision(model); selection = nil } }
            }
            Text("SHA-256").font(.caption.weight(.semibold)); Text(model.sha256).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            if let url = model.url {
                Link("Карточка и лицензия издателя ↗", destination: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            }
            Text("Характеристики показываются по проверяемому каталогу NIKA или метаданным издателя. У импортированного файла неизвестные значения не подставляются.").font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(width: 570)
    }
}
