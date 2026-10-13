import Foundation
import OSLog

/// Журнал разбора зависшего хода: какие кадры приходят в сокет, что решает
/// дожатие через REST и каким путём ход наконец закрывается.
///
/// Только для отладочных сборок: в релизе вызовы компилируются в пустоту,
/// чтобы переписка не утекала в системный журнал.
enum ChatDiagnostics {
  #if DEBUG
    private static let log = Logger(subsystem: "com.nika.v3", category: "chat-turn")
  #endif

  static func frame(type: String, taskID: String?, accepted: String, dropped: Bool) {
    #if DEBUG
      // Токены приходят десятки раз в секунду. Печать каждого в stdout на
      // Debug-сборке с телефона сама по себе греет устройство во время ответа.
      if type == "token", !dropped { return }
      // Печать в stdout, а не только в системный журнал: журнал устройства
      // с Mac уже не вычитывается, а stdout ловится запуском через devicectl.
      print("[ход] кадр type=\(type) task=\(taskID ?? "—") accepted=\(accepted) \(dropped ? "ОТБРОШЕН" : "принят")")
      log.info(
        """
        кадр type=\(type, privacy: .public) \
        task=\(taskID ?? "—", privacy: .public) \
        accepted=\(accepted, privacy: .public) \
        \(dropped ? "ОТБРОШЕН" : "принят", privacy: .public)
        """
      )
    #endif
  }

  static func note(_ message: String) {
    #if DEBUG
      print("[ход] \(message)")
      log.info("\(message, privacy: .public)")
    #endif
  }

  /// Почему дожатие считает ход незавершённым: роли и наполнение хвоста
  /// истории — по ним видно, какое условие не выполняется.
  static func reconcile(attempt: Int, tail: [(role: String, taskID: String?, chars: Int, files: Int)]) {
    #if DEBUG
      let rows = tail
        .map { "\($0.role)/task=\($0.taskID ?? "—")/симв=\($0.chars)/влож=\($0.files)" }
        .joined(separator: " | ")
      print("[ход] дожатие #\(attempt): \(rows)")
      log.info("дожатие #\(attempt, privacy: .public): \(rows, privacy: .public)")
    #endif
  }
}
