import SwiftUI

/// Same streaming-safe Markdown grammar as the iPhone client.
struct MarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in render(block) }
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
    }
    @ViewBuilder private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text): Text(MarkdownParser.inline(text)).font(.system(size: level == 1 ? 25 : level == 2 ? 21 : 17, weight: .semibold)).padding(.top, 6)
        case .paragraph(let text): Text(MarkdownParser.inline(text))
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 12) { Text(ordered ? "\(start + index)." : "•").foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing); Text(MarkdownParser.inline(item)) }
                }
            }
        case .blockquote(let text): HStack { RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.35)).frame(width: 3); Text(MarkdownParser.inline(text)).foregroundStyle(.secondary) }.fixedSize(horizontal: false, vertical: true)
        case .thematicBreak: Divider().padding(.vertical, 6)
        case .code(let code, let language, _):
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(language ?? "Code").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Скопировать") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }; Button("Сохранить…") { save(code, name: "NIKA-code.txt") } }.font(.caption).buttonStyle(.plain)
                ScrollView(.horizontal) { Text(highlight(code)).font(.system(size: 12, design: .monospaced)) }
            }.padding(16).nikaGlass(radius: 12)
        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 12) {
                        GridRow { ForEach(Array(headers.enumerated()), id: \.offset) { _, header in Text(MarkdownParser.inline(header)).fontWeight(.semibold) } }
                        Divider().gridCellColumns(max(1, headers.count))
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in GridRow { ForEach(Array(row.enumerated()), id: \.offset) { _, cell in Text(MarkdownParser.inline(cell)) } } }
                    }.padding(16)
                }.nikaGlass(radius: 12)
                Button("Сохранить таблицу CSV…") { save(Self.csv([headers] + rows), name: "NIKA-table.csv") }.font(.caption).buttonStyle(.plain)
            }
        }
    }
    static func csv(_ rows: [[String]]) -> String {
        rows.map { row in row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }.joined(separator: "\r\n")
    }
    private func save(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        panel.begin { response in if response == .OK, let url = panel.url { do { try Data(text.utf8).write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() } } }
    }
    private func highlight(_ code: String) -> AttributedString {
        var value = AttributedString(code)
        let pattern = "\\b(let|var|func|return|if|else|import|class|struct|def|const|async|await|throw|try|for|while|public|private|true|false|null|nil)\\b|\"[^\"\\n]*\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                if let range = Range(match.range, in: code), let converted = Range(range, in: value) { value[converted].foregroundColor = code[range].hasPrefix("\"") ? .orange : .purple }
            }
        }
        return value
    }
}
