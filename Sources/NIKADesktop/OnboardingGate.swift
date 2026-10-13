import SwiftUI

struct OnboardingGate<Content: View>: View {
    @AppStorage("desktop.birthDate") private var declaredDate = 0.0
    @AppStorage("desktop.consent.v1") private var accepted = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var consent = false
    let content: () -> Content
    private var allowed: Bool { declaredDate > 0 && Self.age(Date(timeIntervalSince1970: declaredDate)) >= 18 && accepted }
    static func age(_ date: Date, now: Date = Date()) -> Int { Calendar.current.dateComponents([.year], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: now)).year ?? 0 }
    var body: some View {
        if allowed { content() }
        else {
            VStack(spacing: 22) {
                NikaMark(size: 82)
                Text("Место для ваших идей.").font(.system(size: 32, weight: .medium, design: .rounded))
                Text("NIKA помогает с текстами, планами и файлами.\nВы выбираете: облачный аккаунт или модель на этом Mac.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Приложение предназначено для людей от 18 лет.").font(.callout)
                    DatePicker("Дата рождения", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    Text("Дата остаётся на этом Mac и используется для возрастного ограничения.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Принимаю условия использования", isOn: $consent)
                    HStack {
                        Link("Условия", destination: URL(string: "https://lumorai.online/legal/terms")!)
                        Text("·").foregroundStyle(.tertiary)
                        Link("Конфиденциальность", destination: URL(string: "https://lumorai.online/legal/privacy")!)
                    }.font(.caption)
                    if declaredDate > 0 && Self.age(Date(timeIntervalSince1970: declaredDate)) < 18 { Text("Продолжить можно с 18 лет. Если вы ошиблись, исправьте дату.").font(.callout).foregroundStyle(.orange) }
                }.padding(24).nikaGlass().frame(maxWidth: 430)
                Button("Начать") { declaredDate = birthDate.timeIntervalSince1970; accepted = consent }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!consent)
                Text("Проверяйте важные ответы: AI может ошибаться.").font(.caption).foregroundStyle(.secondary)
            }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity).background { AuroraCanvas() }
        }
    }
}
