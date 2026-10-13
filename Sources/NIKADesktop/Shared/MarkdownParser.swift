import Foundation

/// Streaming-safe block subset shared with v2's native chat renderer.
///
/// Parsing is deliberately synchronous and forgiving: an unterminated fence
/// remains a code block and partially received tables/lists still render.
enum MarkdownBlock: Equatable, Sendable {
  case heading(level: Int, text: String)
  case paragraph(text: String)
  case list(ordered: Bool, start: Int, items: [String])
  case code(code: String, language: String?, closed: Bool)
  case table(headers: [String], rows: [[String]])
  case thematicBreak
  case blockquote(text: String)

  /// Identity component for the renderer: a block that changes kind mid-stream
  /// has to become a new view rather than morph an existing one.
  var kindToken: String {
    switch self {
    case .heading: return "heading"
    case .paragraph: return "paragraph"
    case .list: return "list"
    case .code: return "code"
    case .table: return "table"
    case .thematicBreak: return "thematicBreak"
    case .blockquote: return "blockquote"
    }
  }
}

/// Parses a growing answer without starting over on every token.
///
/// A stream used to re-parse the whole answer each coalesced frame: 8 000
/// characters in 20-token steps walked the text about seventy times. The
/// answer is frozen up to the last `RestartPoint` (a terminated blank line
/// outside a code fence); only the tail after it is parsed again. The result
/// equals `MarkdownParser.parse(content)` for every prefix — the fuzz in
/// `StreamWithoutExtraWorkTests` holds that (D-1152).
final class MarkdownStreamParser {
  private var frozenText = ""
  private var frozenUTF8Count = 0
  private var frozenBlocks: [MarkdownBlock] = []

  func parse(_ content: String) -> [MarkdownBlock] {
    if frozenUTF8Count > 0, !Self.content(content, startsWith: frozenText) {
      reset()
    }
    let utf8 = content.utf8
    let tailStart = utf8.index(utf8.startIndex, offsetBy: frozenUTF8Count)
    let tail = String(content[tailStart...])
    // `\r\n` is folded by the full parser before splitting; a frozen prefix
    // cannot follow that, so such text goes the whole way.
    if tail.utf8.contains(UInt8(ascii: "\r")) {
      reset()
      return MarkdownParser.parse(content, transient: true)
    }

    MarkdownParserDiagnostics.parsedUnits += tail.utf16.count
    let lines = tail.components(separatedBy: "\n")
    var lastRestart: MarkdownParser.RestartPoint?
    let tailBlocks = MarkdownParser.parseLines(lines) { lastRestart = $0 }
    let blocks = frozenBlocks + tailBlocks

    if let lastRestart, lastRestart.line > 0 {
      var frozenTail = 0
      for line in lines[..<lastRestart.line] {
        frozenTail += line.utf8.count + 1
      }
      let end = utf8.index(tailStart, offsetBy: frozenTail)
      frozenText = String(content[..<end])
      frozenUTF8Count += frozenTail
      frozenBlocks += tailBlocks[..<lastRestart.blockCount]
    }
    return blocks
  }

  func reset() {
    frozenText = ""
    frozenUTF8Count = 0
    frozenBlocks = []
  }

  private static func content(_ content: String, startsWith prefix: String) -> Bool {
    content.utf8.count >= prefix.utf8.count
      && content.utf8.starts(with: prefix.utf8)
  }
}

/// Parser runs that missed the cache. A streamed prefix must not push a
/// finished answer out of it (D-750).
enum MarkdownParserDiagnostics {
  nonisolated(unsafe) static var parseMisses = 0
  nonisolated(unsafe) static var inlineMisses = 0
  /// UTF-16 units the block parser walked. A stream that re-parses the whole
  /// answer on every token grows this quadratically (phase 149).
  nonisolated(unsafe) static var parsedUnits = 0
}

enum MarkdownParser {
  /// `transient` is for text nobody asks for twice: the growing tail of a
  /// streamed answer. It lands in a few scratch slots, so a stream of prefixes
  /// does not evict finished answers and scrolling back does not re-parse
  /// them (D-750).
  static func parse(_ content: String, transient: Bool = false) -> [MarkdownBlock] {
    let cache = transient ? transientParseCache : parseCache
    if let cached = cache.object(forKey: content as NSString) {
      return cached.value
    }
    MarkdownParserDiagnostics.parseMisses += 1
    let blocks = parseUncached(content)
    cache.setObject(CachedMarkdownBlocks(blocks), forKey: content as NSString)
    return blocks
  }

  private static func parseUncached(_ content: String) -> [MarkdownBlock] {
    MarkdownParserDiagnostics.parsedUnits += content.utf16.count
    let lines = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n")
    return parseLines(lines, restart: nil)
  }

  /// A point where the block loop starts fresh: `line` follows a blank line
  /// that is itself terminated, and `blockCount` blocks were emitted before
  /// it. No block before it looks at `line` or later, and parsing from `line`
  /// carries no state from above, so the text before it can be frozen.
  struct RestartPoint: Equatable {
    let line: Int
    let blockCount: Int
  }

  /// The block loop over pre-split lines. `restart` hears every
  /// `RestartPoint` — `MarkdownStreamParser` freezes the answer up to the
  /// last one (phase 149).
  static func parseLines(
    _ lines: [String],
    restart: ((RestartPoint) -> Void)?
  ) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var index = 0

    while index < lines.count {
      let line = lines[index].trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else {
        index += 1
        if index < lines.count {
          restart?(RestartPoint(line: index, blockCount: blocks.count))
        }
        continue
      }

      if line.hasPrefix("```") {
        let rawLanguage = String(line.dropFirst(3))
          .trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        var closed = false
        index += 1

        while index < lines.count {
          if lines[index]
            .trimmingCharacters(in: .whitespaces)
            .hasPrefix("```") {
            closed = true
            index += 1
            break
          }
          codeLines.append(lines[index])
          index += 1
        }

        blocks.append(
          .code(
            code: codeLines.joined(separator: "\n"),
            language: rawLanguage.isEmpty ? nil : rawLanguage,
            closed: closed
          )
        )
        continue
      }

      if let heading = heading(in: line) {
        blocks.append(.heading(level: heading.level, text: heading.text))
        index += 1
        continue
      }

      if isThematicBreak(line) {
        blocks.append(.thematicBreak)
        index += 1
        continue
      }

      if let quote = blockquoteText(in: line) {
        var quotes = [quote]
        index += 1
        while index < lines.count {
          let current = lines[index].trimmingCharacters(in: .whitespaces)
          guard let next = blockquoteText(in: current) else { break }
          quotes.append(next)
          index += 1
        }
        blocks.append(.blockquote(text: quotes.joined(separator: "\n")))
        continue
      }

      if line.contains("|"),
         index + 1 < lines.count,
         isTableSeparator(lines[index + 1]) {
        let headers = parseTableRow(lines[index])
        var rows: [[String]] = []
        index += 2
        while index < lines.count, lines[index].contains("|") {
          rows.append(parseTableRow(lines[index]))
          index += 1
        }
        blocks.append(.table(headers: headers, rows: rows))
        continue
      }

      // B-143: чек-лист из расширенного редактора уезжал в чат строками
      // «- [ ] пункт» — квадратики не рисовались нигде. Отдельного блока под
      // чек-лист у рендерера нет, поэтому пункты выходят одним абзацем с
      // настоящими ☐/☑ и переносами — тем же приёмом, что и цитата.
      if let first = taskItem(in: line) {
        var items = [checkboxLine(first)]
        index += 1
        while index < lines.count {
          let current = lines[index].trimmingCharacters(in: .whitespaces)
          guard let next = taskItem(in: current) else { break }
          items.append(checkboxLine(next))
          index += 1
        }
        blocks.append(.paragraph(text: items.joined(separator: "\n")))
        continue
      }

      let unordered = isUnorderedItem(line)
      let ordered = isOrderedItem(line)
      if unordered || ordered {
        // D-230: номер первого пункта — часть содержания, а не украшение.
        // «2026. Год был тяжёлым» — это список, начинающийся с 2026, и год
        // обязан доехать до экрана.
        let start = ordered ? (orderedMarker(line) ?? 1) : 1
        // Список, целиком сдвинутый вправо, — всё ещё список верхнего уровня:
        // глубина считается от первого пункта, а не от края строки.
        let baseDepth = listDepth(of: lines[index])
        var items: [String] = []
        while index < lines.count {
          let raw = lines[index]
          let current = raw.trimmingCharacters(in: .whitespaces)
          let depth = max(0, listDepth(of: raw) - baseDepth)
          if depth == 0 {
            let matches = unordered
              ? isUnorderedItem(current)
              : isOrderedItem(current)
            guard matches else { break }
            items.append(stripListMarker(current, ordered: ordered))
          } else {
            // D-364: вложенный пункт — любой маркер с отступом. Раньше строка
            // тримилась до маркера, и «  - подпункт» вставал вровень с
            // родителем; отступ уезжал, иерархия ответа пропадала.
            let nestedOrdered = isOrderedItem(current)
            guard nestedOrdered || isUnorderedItem(current) else { break }
            items.append(
              encodeListItem(
                stripListMarker(current, ordered: nestedOrdered),
                depth: depth,
                ordinal: nestedOrdered ? orderedMarker(current) : nil
              )
            )
          }
          index += 1
        }
        blocks.append(.list(ordered: ordered, start: start, items: items))
        continue
      }

      if index + 1 < lines.count, isSetextH1(lines[index + 1]) {
        blocks.append(.heading(level: 1, text: line))
        index += 2
        continue
      }

      var paragraph = [line]
      index += 1
      while index < lines.count {
        let current = lines[index]
          .trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty,
              heading(in: current) == nil,
              !current.hasPrefix("```"),
              !isThematicBreak(current),
              blockquoteText(in: current) == nil,
              !isSetextH1(current),
              !isUnorderedItem(current),
              !isOrderedItem(current)
        else {
          break
        }
        if current.contains("|"),
           index + 1 < lines.count,
           isTableSeparator(lines[index + 1]) {
          break
        }
        paragraph.append(current)
        index += 1
      }
      // D-363: одиночный перенос внутри абзаца — перенос, а не пробел. Адрес
      // в три строки, реквизиты, «шаги через Enter» склеивались в одну
      // строку; ChatGPT и Grok показывают их так, как модель написала.
      blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
    }

    return blocks
  }

  // MARK: - Вложенные пункты списка

  /// Разобранный пункт списка: глубина от нуля, собственный номер у
  /// вложенного нумерованного пункта и сам текст.
  struct ListItem: Equatable {
    let depth: Int
    let ordinal: Int?
    let text: String
  }

  /// Вложенность кодируется в самой строке пункта, чтобы не менять форму
  /// `MarkdownBlock.list` во всех местах, где она разбирается: табуляции
  /// впереди — глубина, число и U+2063 (невидимый разделитель) — номер
  /// вложенного нумерованного пункта. Наружу выходит только через
  /// `listItem(_:)`, `visibleText` и рендер.
  private static let ordinalSeparator: Character = "\u{2063}"

  static func encodeListItem(_ text: String, depth: Int, ordinal: Int?) -> String {
    let indent = String(repeating: "\t", count: max(0, depth))
    if let ordinal {
      return indent + String(ordinal) + String(ordinalSeparator) + text
    }
    return indent + text
  }

  static func listItem(_ raw: String) -> ListItem {
    var rest = Substring(raw)
    var depth = 0
    while rest.first == "\t" {
      depth += 1
      rest = rest.dropFirst()
    }
    if let separator = rest.firstIndex(of: ordinalSeparator),
       let ordinal = Int(rest[..<separator]) {
      return ListItem(
        depth: depth,
        ordinal: ordinal,
        text: String(rest[rest.index(after: separator)...])
      )
    }
    return ListItem(depth: depth, ordinal: nil, text: String(rest))
  }

  /// Глубина по отступу строки: два пробела или одна табуляция — уровень,
  /// не больше трёх уровней, чтобы случайный отступ в двадцать пробелов не
  /// уносил пункт за край экрана.
  static func listDepth(of raw: String) -> Int {
    var columns = 0
    for character in raw {
      if character == " " { columns += 1 }
      else if character == "\t" { columns += 2 }
      else { break }
    }
    return min(columns / 2, 3)
  }

  /// Подписи пунктов на экране и в буфере: «1.», «•», «◦». Номер верхнего
  /// уровня считает только пункты верхнего уровня — вложенные его не сдвигают
  /// (иначе за «1.» с двумя подпунктами шло «4.»).
  static func listMarkers(
    for items: [String],
    ordered: Bool,
    start: Int
  ) -> [String] {
    var topLevelIndex = 0
    return items.map { raw in
      let item = listItem(raw)
      if item.depth == 0 {
        defer { topLevelIndex += 1 }
        return ordered ? "\(start + topLevelIndex)." : "•"
      }
      if let ordinal = item.ordinal {
        return "\(ordinal)."
      }
      return "◦"
    }
  }

  /// Keyed by the raw text: sanitizing is a pure function of it, and a cache
  /// hit no longer runs the link scan on every redraw. `transient` as in
  /// `parse` (D-750).
  static func inline(_ text: String, transient: Bool = false) -> AttributedString {
    let cache = transient ? transientInlineCache : inlineCache
    if let cached = cache.object(forKey: text as NSString) {
      return cached.value
    }
    MarkdownParserDiagnostics.inlineMisses += 1
    let sanitized = sanitizingUnsafeLinks(in: text)
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace,
      failurePolicy: .returnPartiallyParsedIfPossible
    )
    // Bare `https://…` and `www.…` runs come back as links from the parser
    // itself (Markdown autolinks), so a naked URL in an answer is tappable
    // without any help from us.
    // D-370: явная ссылка `[позвонить](tel:+7…)` проходит `sanitizingUnsafeLinks`
    // и открывается системой (`InAppBrowser.handles` отдаёт не-web схемы
    // в `.systemAction`). Угадывать телефоны детектором в обычном тексте
    // здесь не стали: разбор бежит на каждый такт стрима.
    let parsed = (try? AttributedString(markdown: sanitized, options: options))
      ?? AttributedString(sanitized)
    cache.setObject(CachedInlineString(parsed), forKey: text as NSString)
    return parsed
  }

  /// Видимый текст абзаца, заголовка или ячейки: инлайн-разметка снята
  /// (`**жирный**` → «жирный»), переносы и пробелы сохранены. Это то, что
  /// человек видит на экране, и то, что уходит в буфер как plain text.
  static func plainText(of text: String) -> String {
    String(inline(text).characters)
  }

  /// Visible copy payload: markers such as `##` and `---` do not belong on
  /// the pasteboard. Thematic breaks contribute nothing; tables stay tabular.
  static func visibleText(from content: String) -> String {
    visibleText(from: parse(content))
  }

  static func visibleText(from blocks: [MarkdownBlock]) -> String {
    blocks.compactMap(visibleString(for:)).joined(separator: "\n\n")
  }

  static func parseTableRow(_ line: String) -> [String] {
    var value = line.trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("|") {
      value.removeFirst()
    }
    if value.hasSuffix("|") {
      value.removeLast()
    }
    return value
      .split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }

  static func isTableSeparator(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.contains("|") else { return false }
    let cells = parseTableRow(trimmed)
    // Таблица в одну колонку — тоже таблица: в расширенном редакторе колонку
    // можно убрать, и до правки такое сообщение уезжало в чат палками
    // «| Пункт |» вместо сетки.
    guard cells.count >= 1 else { return false }
    return cells.allSatisfy { cell in
      let value = cell.trimmingCharacters(in: .whitespaces)
      guard !value.isEmpty else { return true }
      let withoutColons = value.replacingOccurrences(of: ":", with: "")
      return withoutColons.count >= 3
        && withoutColons.allSatisfy { $0 == "-" }
    }
  }

  /// CommonMark thematic break: three or more of `-`, `*` or `_`, optional
  /// spaces between. Table separators (`|---|`) are not breaks. `===` is
  /// setext, not a rule — it is handled separately as a heading underline.
  static func isThematicBreak(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.contains("|") else { return false }
    let compact = trimmed.filter { !$0.isWhitespace }
    guard compact.count >= 3, let marker = compact.first else { return false }
    guard marker == "-" || marker == "*" || marker == "_" else { return false }
    return compact.allSatisfy { $0 == marker }
  }

  /// Один блок как его видит человек. Инлайн-маркеры сняты (D-362: раньше
  /// «**сначала**» уезжало в буфер со звёздочками), переносы внутри абзаца
  /// сохранены (D-363), пункты списка носят те же «•»/«◦»/номера, что и на
  /// экране (D-364). Строки таблицы — через « | », как в макете листа
  /// «Выделить текст»: этот же текст показывается в листе и кладётся в буфер.
  static func visibleString(for block: MarkdownBlock) -> String? {
    switch block {
    case .heading(_, let text), .paragraph(let text), .blockquote(let text):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : plainText(of: text)
    case .list(let ordered, let start, let items):
      let markers = listMarkers(for: items, ordered: ordered, start: start)
      return zip(items, markers).map { raw, marker in
        let item = listItem(raw)
        return String(repeating: "  ", count: item.depth) + marker + " " + plainText(of: item.text)
      }.joined(separator: "\n")
    case .code(let code, _, _):
      let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : code
    case .table(let headers, let rows):
      return ([headers] + rows)
        .map { $0.map(plainText(of:)).joined(separator: " | ") }
        .joined(separator: "\n")
    case .thematicBreak:
      return nil
    }
  }

  private static func heading(in line: String) -> (level: Int, text: String)? {
    let hashes = line.prefix(while: { $0 == "#" })
    guard (1...6).contains(hashes.count) else { return nil }
    let remainder = line.dropFirst(hashes.count)
    let text: String
    if remainder.first?.isWhitespace == true {
      text = remainder.trimmingCharacters(in: .whitespaces)
    } else if remainder.isEmpty {
      return nil
    } else {
      // The model often emits `#Заголовок` without the space CommonMark wants.
      text = String(remainder)
    }
    guard !text.isEmpty else { return nil }
    return (hashes.count, text)
  }

  /// Setext H1 only. Dashes stay thematic breaks so `---` between sections
  /// does not become a heading underline.
  private static func isSetextH1(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 3 else { return false }
    return trimmed.allSatisfy { $0 == "=" }
  }

  /// `>= 5` is a comparison, not a quote. Nested `>>` still counts.
  private static func blockquoteText(in line: String) -> String? {
    guard line.hasPrefix(">") else { return nil }
    let after = line.dropFirst()
    if after.first == "=" { return nil }
    if after.first == " " {
      return String(after.dropFirst())
    }
    return String(after)
  }

  private static func isUnorderedItem(_ line: String) -> Bool {
    line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
  }

  /// Пункт чек-листа GFM: `- [ ] купить хлеб` / `- [x] купить хлеб`.
  /// Всё остальное в квадратных скобках — обычный пункт списка: `- [1] сноска`
  /// чек-боксом не становится.
  static func taskItem(in line: String) -> (isChecked: Bool, text: String)? {
    guard isUnorderedItem(line) else { return nil }
    let rest = line.dropFirst(2)
    guard rest.hasPrefix("[") else { return nil }
    let box = rest.dropFirst()
    var iterator = box.startIndex
    guard iterator < box.endIndex else { return nil }
    let mark = box[iterator]
    iterator = box.index(after: iterator)
    guard iterator < box.endIndex, box[iterator] == "]" else { return nil }
    let isChecked: Bool
    switch mark {
    case " ": isChecked = false
    case "x", "X": isChecked = true
    default: return nil
    }
    let body = box[box.index(after: iterator)...]
    guard !body.isEmpty else { return (isChecked, "") }
    guard body.hasPrefix(" ") else { return nil }
    return (
      isChecked,
      String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
    )
  }

  private static func checkboxLine(
    _ item: (isChecked: Bool, text: String)
  ) -> String {
    let box = item.isChecked ? "☑" : "☐"
    return item.text.isEmpty ? box : box + " " + item.text
  }

  /// Номер, которым помечен пункт: `2026. Год` → 2026.
  static func orderedMarker(_ line: String) -> Int? {
    guard let end = orderedMarkerEnd(of: line) else { return nil }
    return Int(line[..<end])
  }

  /// Конец номера пункта: индекс точки или скобки после цифр («3. », «3) »).
  /// Скобка — вторая привычная форма у моделей и людей; раньше «1) …»
  /// уезжало абзацем с видимой скобкой.
  private static func orderedMarkerEnd(of line: String) -> String.Index? {
    let digits = line.prefix(while: \.isNumber)
    guard !digits.isEmpty, digits.count <= 9 else { return nil }
    let end = digits.endIndex
    guard end < line.endIndex,
          line[end] == "." || line[end] == ")"
    else { return nil }
    return end
  }

  private static func isOrderedItem(_ line: String) -> Bool {
    guard let end = orderedMarkerEnd(of: line),
          line.index(after: end) < line.endIndex,
          line[line.index(after: end)].isWhitespace
    else {
      return false
    }
    return true
  }

  private static func stripListMarker(
    _ line: String,
    ordered: Bool
  ) -> String {
    if ordered, let end = orderedMarkerEnd(of: line) {
      return line[line.index(after: end)...]
        .trimmingCharacters(in: .whitespaces)
    }
    return String(line.dropFirst(2))
  }

  /// v2 only makes http(s)/mailto Markdown links interactive.
  /// Компилируется один раз на процесс. Раньше `NSRegularExpression` строился
  /// на каждый вызов — а вызывается это на каждый видимый параграф на каждый
  /// прогон `body`, то есть 10 раз в секунду во время ответа и пачками при
  /// прокрутке. Образец статического паттерна — `MemoryExtractor.patterns`.
  private nonisolated(unsafe) static let linkExpression: NSRegularExpression? =
    try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)

  private static func sanitizingUnsafeLinks(in text: String) -> String {
    guard let expression = Self.linkExpression else {
      return text
    }
    let source = text as NSString
    var result = text
    let matches = expression.matches(
      in: text,
      range: NSRange(location: 0, length: source.length)
    )
    for match in matches.reversed() {
      guard match.numberOfRanges == 3 else { continue }
      let url = source.substring(with: match.range(at: 2))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      // `tel:` идёт в системную звонилку тем же путём, что `mailto:`
      // (`InAppBrowser`), и телефон из ответа должен набираться одним тапом.
      guard !url.lowercased().hasPrefix("https://"),
            !url.lowercased().hasPrefix("http://"),
            !url.lowercased().hasPrefix("mailto:"),
            !url.lowercased().hasPrefix("tel:")
      else {
        continue
      }
      let label = source.substring(with: match.range(at: 1))
      guard let range = Range(match.range, in: result) else { continue }
      result.replaceSubrange(range, with: label)
    }
    return result
  }

  // NSCache is already thread-safe; the annotation is for the static binding.
  // Every paragraph of a long conversation, so scrolling back through it
  // finds its answers already parsed.
  nonisolated(unsafe) private static let inlineCache: NSCache<NSString, CachedInlineString> = {
    let cache = NSCache<NSString, CachedInlineString>()
    cache.countLimit = 512
    return cache
  }()

  nonisolated(unsafe) private static let parseCache: NSCache<NSString, CachedMarkdownBlocks> = {
    let cache = NSCache<NSString, CachedMarkdownBlocks>()
    cache.countLimit = 128
    return cache
  }()

  nonisolated(unsafe) private static let transientInlineCache: NSCache<NSString, CachedInlineString> = {
    let cache = NSCache<NSString, CachedInlineString>()
    cache.countLimit = 4
    return cache
  }()

  nonisolated(unsafe) private static let transientParseCache: NSCache<NSString, CachedMarkdownBlocks> = {
    let cache = NSCache<NSString, CachedMarkdownBlocks>()
    cache.countLimit = 4
    return cache
  }()
}

/// NSCache values have to be objects; `AttributedString` itself is a struct.
private final class CachedInlineString {
  let value: AttributedString

  init(_ value: AttributedString) {
    self.value = value
  }
}

private final class CachedMarkdownBlocks {
  let value: [MarkdownBlock]

  init(_ value: [MarkdownBlock]) {
    self.value = value
  }
}
